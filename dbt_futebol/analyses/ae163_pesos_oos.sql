{#
    AE#163 (spec #157) — pesos do catálogo de handicap de escanteios com CONTROLE FORA DA
    AMOSTRA (ADR 0001) e veredito de sobrevivência. Entregável final da spec #157: nenhuma
    tabela de mart, modelo de premissa, ou coluna do funil — só analyses/ e o modelo do #159.

    Protocolo declarado no comentário de pré-registro da issue #163, ANTES de qualquer query
    de ROI/faixa/peso:

      - Partição temporal: NTILE(2) sobre kickoff_utc (contagem de jogos igual, não dias
        corridos) — mesma técnica de task01_premissa_forte.sql.
      - DUAS DIREÇÕES: A = peso ajustado na metade 1, medido na metade 2;
                        B = peso ajustado na metade 2, medido na metade 1.
        Nunca peso e resultado da mesma metade.
      - UMA linha por (fixture_id, outcome_side): a mais líquida (n_casas desc), empate pela
        mais central (|line_value| asc), empate residual por line_value (determinístico).
      - Score: 100 × soma_pesos_das_acesas / 50 (teto DECLARADO 50 nos dois lados — não a
        soma do catálogo de cada lado). Faixas Alta >=60 / Média [30,60) / Baixa <30.
      - Régua de aceite (ClickUp wdx6zf1tt8), mecânica: (1) Alta>Média>Baixa nos dois lados,
        fora da amostra; (2) Baixa <= -3,77% (o ROI do mercado inteiro sem filtro, #161);
        (3) uma oportunidade por jogo/lado (resolvido pela regra de seleção acima); (4) soma
        dos pesos medidos = teto de 50 (reportado, não testado — o teto é definição, não
        resultado).

    Rodar com:
      dbt compile --select ae163_pesos_oos
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae163_pesos_oos.sql
#}

WITH {{ ae161_base_escanteios(cutoff=none, janela_fixa=none, gates_do_board=true) }},

-- Piso do catálogo + UMA linha por (fixture, lado) — a mais líquida.
apostas_unica AS (
    SELECT *
    FROM apostas
    WHERE min_jogos >= 10
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id, outcome_side
        ORDER BY n_casas DESC, ABS(line_value) ASC, line_value ASC
    ) = 1
),

metades AS (
    SELECT fixture_id, NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc FROM apostas_unica)
),

-- Catálogo completo (10 premissas, Decisão incluída — AE#162), grão (aposta, premissa).
premissas_por_lado AS (
    {%- set combos = [] -%}
    {%- for p in ae161_premissas_home() -%}
        {%- set _ = combos.append(('Home', p)) -%}
    {%- endfor -%}
    {%- for p in ae161_premissas_away(incluir_decisao=true) -%}
        {%- set _ = combos.append(('Away', p)) -%}
    {%- endfor -%}
    {%- for lado, p in combos %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        fixture_id, outcome_side,
        '{{ p.premissa }}'           AS premissa,
        COALESCE({{ p.sql }}, FALSE) AS acesa
    FROM apostas_unica
    WHERE outcome_side = '{{ lado }}'
    {%- endfor %}
),

linhas AS (
    SELECT a.*, m.metade, pl.premissa, pl.acesa
    FROM apostas_unica AS a
    JOIN metades AS m USING (fixture_id)
    JOIN premissas_por_lado AS pl
      ON pl.fixture_id = a.fixture_id AND pl.outcome_side = a.outcome_side
),

-- Ganho do Teste 2 por (direção, lado, premissa), calculado SÓ com a metade de AJUSTE e só
-- benchmark pinnacle (mesma regra "usado_para_peso" do #161/#162 — consenso não pesa).
ganho_por_direcao AS (
    SELECT
        'A' AS direcao, outcome_side AS lado, premissa,
        COUNTIF(acesa)                                                                AS n,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100                           AS diferenca_pp
    FROM linhas
    WHERE metade = 1 AND benchmark = 'pinnacle'
    GROUP BY outcome_side, premissa
    HAVING COUNTIF(acesa) > 0

    UNION ALL

    SELECT
        'B' AS direcao, outcome_side, premissa,
        COUNTIF(acesa)                                                                AS n,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100                           AS diferenca_pp
    FROM linhas
    WHERE metade = 2 AND benchmark = 'pinnacle'
    GROUP BY outcome_side, premissa
    HAVING COUNTIF(acesa) > 0
),

pesos AS (
    SELECT
        direcao, lado, premissa, n, diferenca_pp,
        ROUND(GREATEST(diferenca_pp, 0) * SAFE_DIVIDE(n, n + 50), 2) AS peso
    FROM ganho_por_direcao
),

-- Score de cada aposta na metade de MEDIÇÃO, com os pesos da metade de AJUSTE OPOSTA.
-- Direção A: peso da metade 1, medido na metade 2. Direção B: o inverso.
score AS (
    SELECT
        'A' AS direcao, l.fixture_id, l.outcome_side, l.kickoff_utc, l.best_odd, l.ganhou,
        SUM(COALESCE(w.peso, 0)) AS soma_pesos
    FROM linhas l
    LEFT JOIN pesos w
      ON w.direcao = 'A' AND w.lado = l.outcome_side AND w.premissa = l.premissa AND l.acesa
    WHERE l.metade = 2
    GROUP BY l.fixture_id, l.outcome_side, l.kickoff_utc, l.best_odd, l.ganhou

    UNION ALL

    SELECT
        'B' AS direcao, l.fixture_id, l.outcome_side, l.kickoff_utc, l.best_odd, l.ganhou,
        SUM(COALESCE(w.peso, 0)) AS soma_pesos
    FROM linhas l
    LEFT JOIN pesos w
      ON w.direcao = 'B' AND w.lado = l.outcome_side AND w.premissa = l.premissa AND l.acesa
    WHERE l.metade = 1
    GROUP BY l.fixture_id, l.outcome_side, l.kickoff_utc, l.best_odd, l.ganhou
),

faixado AS (
    SELECT
        *,
        ROUND(100.0 * soma_pesos / 50.0, 1) AS score_0_100,
        CASE
            WHEN 100.0 * soma_pesos / 50.0 >= 60 THEN 'Alta'
            WHEN 100.0 * soma_pesos / 50.0 >= 30 THEN 'Média'
            ELSE 'Baixa'
        END AS faixa,
        IF(ganhou, best_odd - 1, -1) AS lucro
    FROM score
),

resultado AS (
    SELECT
        direcao, outcome_side AS lado, faixa,
        COUNT(*)                       AS n,
        ROUND(AVG(lucro) * 100, 2)     AS roi_pct
    FROM faixado
    GROUP BY 1, 2, 3
),

-- Diagnóstico da régua (item 3, "uma oportunidade por jogo/lado"): tem que dar 1,0 nas duas
-- direções — cada (fixture, lado) aparece EXATAMENTE uma vez por direção.
checagem_unicidade AS (
    SELECT direcao, COUNT(*) AS linhas,
           COUNT(DISTINCT CONCAT(CAST(fixture_id AS STRING), '|', outcome_side)) AS chaves_distintas
    FROM faixado GROUP BY 1
)

SELECT
    'faixa' AS bloco, direcao, lado, faixa, n, roi_pct,
    NULL AS linhas_check, NULL AS chaves_check
FROM resultado

UNION ALL

SELECT
    'checagem_unica' AS bloco, direcao, NULL, NULL, NULL, NULL,
    linhas, chaves_distintas
FROM checagem_unicidade

ORDER BY bloco, direcao, lado, faixa
