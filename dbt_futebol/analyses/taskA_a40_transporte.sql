{#
    A4.0 — A PORTA DE 40 TRANSPORTA PARA A NOTA DE CATÁLOGO?

    A tabela de ROI por faixa que sustenta a porta de 40 foi medida sobre a NOTA PONDERADA:
    premissas pesadas pelo ganho do Teste 2 (`max(ganho,0) × n/(n+k)`, piso de 5 jogos),
    normalizada 0–100 por mercado. O que a A4 põe em produção é a NOTA DE CATÁLOGO, com os
    pesos postos à mão — e a decisão de não reescrever os 39 pesos está fechada.

    São dois vetores de peso diferentes. Esta análise mede se a curva sobrevive à troca.

    Mesma máquina da `task01_teste4.sql` (metades temporais por jogo, faixas, erro-padrão
    agrupado por fixture, inclinação contínua). O que muda:

      FONTES DE PESO
        A/B/C/D  as do Teste 4, intactas — servem de referência e reproduzem o publicado.
        E        catálogo: os pesos que estão em produção HOJE, lidos dos modelos.
        F        catálogo sem `linha_subindo`/`linha_descendo` (decisão D1 da spec, que
                 tira da nota as duas premissas que leem movimento de odd). Pesa 0 nelas,
                 o que derruba o teto do Gols de 56/52 p/ 50/46.
                 ⚠ Desde a #103 (ADR 0012) a fonte F é o que PRODUÇÃO faz — as duas premissas
                 foram removidas do modelo. Esta análise não roda mais como está: o catálogo
                 do `task01_base` já não as tem e a leitura delas falha no BigQuery. Ela fica
                 como registro da medição que fundamentou a decisão, e não é reescrita pelo
                 mesmo motivo da `taskA_linha_de_base.sql`.
        E e F não são ajustadas em metade nenhuma — o catálogo é fixo. Por isso saem
        avaliadas nas duas metades, e é a 2ª que compara com a C.

      NORMALIZAÇÃO POR LADO
        O teto passa a ser por (fonte, mercado, LADO). As fontes A–D têm todas as premissas
        marcadas 'ambos', então o teto por lado colapsa no teto por mercado e elas
        reproduzem o publicado byte a byte. Só E/F usam os lados de verdade:
          1X2       Home 51 · Away 47 (só `mando` difere: 8 em casa, 4 fora) · Draw 43*
          Gols      Over 56 · Under 52   (E)  |  Over 50 · Under 46  (F)
          Handicap  Favorito 40 · Azarão 30 · Pick 0
          BTTS      Sim 34 · Não 28
          DC        34
        * o Draw não tem lado apostado, então nenhuma premissa dispara e o numerador é
          sempre 0 — o teto dele é irrelevante e a nota sai 0 de qualquer jeito.

      COMPOSIÇÕES
        1. nota_premissas            Σ dos pesos acesos. Comparável com o publicado.
        2. score_pos_a1              + corroboração − penalidades. Comparável com o publicado.
        3. nota_menos_pen_contexto   Σ − penalidades específicas do mercado, com piso em 0.
                                     É a fórmula que vai a produção (decisão D5 da spec).

    O fatorial que interessa:
      C × comp.1   a curva publicada (peso medido, sem penalidade).
      E × comp.3   o que vai ao ar (peso de catálogo, com penalidade de contexto).
      E × comp.1   isola o efeito do vetor de peso.
      C × comp.3   isola o efeito da penalidade de contexto.

    REGRA DE DECISÃO, fixada antes de olhar:
      · faixa 00–20 de E×3 segue negativa a >= 2 EP  ->  a porta de 40 transporta, A4 segue.
      · faixas achatam                               ->  o corte sai desta medição, não da outra.
      · ordenação inverte                            ->  A4 trava e a decisão volta pro PM.

    ⚠️ Linhas de conjunto incompleto (o bug da task [D], `prob_justa = 1,0` com um só lado
    precificado) já saem fora aqui, como no Teste 4. A [D] torna a proteção estrutural.

    Rodar com:
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_a40_transporte
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/taskA_a40_transporte.sql
#}

WITH {{ task01_base() }},

validas AS (
    SELECT * FROM apostas WHERE NOT conjunto_incompleto
),

metades AS (
    SELECT
        fixture_id,
        NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc FROM validas)
),

{# LADO da aposta. É o eixo que a normalização passa a respeitar: dentro do mesmo mercado
   os dois lados têm conjuntos de premissa disjuntos (menos no 1X2 e na DC, onde só o
   `mando` difere). No Handicap o lado sai do SINAL do handicap na ótica do próprio lado —
   `line_value` vem na ótica do mandante e é o mesmo p/ Home e Away. #}
apostas_m AS (
    SELECT
        v.*,
        m.metade,
        CASE v.market_id
            WHEN 4 THEN CASE
                            WHEN IF(v.outcome_side = 'Home', v.line_value, -v.line_value) < 0 THEN 'Favorito'
                            WHEN IF(v.outcome_side = 'Home', v.line_value, -v.line_value) > 0 THEN 'Azarao'
                            ELSE 'Pick'
                        END
            WHEN 12 THEN 'unico'
            ELSE v.outcome_side
        END AS lado
    FROM validas AS v
    JOIN metades AS m USING (fixture_id)
),

lados AS (
    SELECT  1 AS market_id, lado FROM UNNEST(['Home', 'Away', 'Draw'])        AS lado
    UNION ALL SELECT 5, lado FROM UNNEST(['Over', 'Under'])                   AS lado
    UNION ALL SELECT 4, lado FROM UNNEST(['Favorito', 'Azarao', 'Pick'])      AS lado
    UNION ALL SELECT 8, lado FROM UNNEST(['Yes', 'No'])                       AS lado
    UNION ALL SELECT 12, 'unico'
),

para_peso AS (
    SELECT a.*, pl.premissa, pl.acesa
    FROM apostas_m AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    WHERE a.benchmark = CASE a.market_id
                            WHEN 12 THEN 'derivada'
                            WHEN 8  THEN 'consenso'
                            ELSE         'sharp'
                        END
      AND a.min_jogos >= 5
),

pesos_t2 AS (
    SELECT 'A. t2_full' AS fonte, market_id, premissa, 'ambos' AS lado,
           GREATEST((AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
                   - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100, 0)
           * SAFE_DIVIDE(COUNTIF(acesa), COUNTIF(acesa) + 50) AS peso
    FROM para_peso
    GROUP BY market_id, premissa

    UNION ALL
    SELECT 'B. t2_h1', market_id, premissa, 'ambos',
           GREATEST((AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
                   - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100, 0)
           * SAFE_DIVIDE(COUNTIF(acesa), COUNTIF(acesa) + 50)
    FROM para_peso WHERE metade = 1
    GROUP BY market_id, premissa
),

t1_linhas AS (
    SELECT
        pl.market_id, pl.fixture_id, pl.outcome_side, pl.line_value, pl.premissa, pl.acesa,
        COALESCE(pit.min_jogos, 0)          AS min_jogos,
        {{ task01_liquidacao('pl.', 'j.') }} AS ganhou
    FROM prem_long AS pl
    JOIN jogos_encerrados AS j ON j.fixture_id = pl.fixture_id
    LEFT JOIN pit ON pit.fixture_id = pl.fixture_id
    WHERE {{ task01_meia_linha('pl.') }}
),
t1_base AS (
    SELECT market_id, outcome_side, line_value, AVG(CAST(ganhou AS INT64)) AS taxa_base
    FROM (SELECT DISTINCT market_id, fixture_id, outcome_side, line_value, ganhou FROM t1_linhas)
    GROUP BY 1, 2, 3
),
pesos_t1 AS (
    SELECT 'D. t1_controle' AS fonte, l.market_id, l.premissa, 'ambos' AS lado,
           GREATEST((AVG(IF(l.acesa, CAST(l.ganhou AS INT64), NULL))
                   - AVG(IF(l.acesa, b.taxa_base, NULL))) * 100, 0)
           * SAFE_DIVIDE(COUNTIF(l.acesa), COUNTIF(l.acesa) + 50) AS peso
    FROM t1_linhas AS l
    JOIN t1_base AS b
      ON  b.market_id                  = l.market_id
      AND b.outcome_side               = l.outcome_side
      AND COALESCE(b.line_value, -999) = COALESCE(l.line_value, -999)
    WHERE l.min_jogos >= 5
    GROUP BY l.market_id, l.premissa
),

{# OS PESOS DE CATÁLOGO — os que estão em produção hoje, lidos dos cinco modelos de
   premissa. Se um peso mudar lá, muda aqui. `mando` é a única premissa com peso por lado
   (8 em casa, 4 fora), e é o que separa o teto 51 do 47 no 1X2. #}
catalogo AS (
    SELECT * FROM UNNEST([
        {# 1X2 — Home Σ51 · Away Σ47 #}
        STRUCT( 1 AS market_id, 'forca_mismatch'         AS premissa, 'ambos' AS lado, 12.0 AS peso),
        STRUCT( 1, 'superioridade_xg',       'ambos',  8.0),
        STRUCT( 1, 'mando',                  'Home',   8.0),
        STRUCT( 1, 'mando',                  'Away',   4.0),
        STRUCT( 1, 'desfalque_adversario',   'ambos',  8.0),
        STRUCT( 1, 'superioridade_tabela',   'ambos',  6.0),
        STRUCT( 1, 'forma',                  'ambos',  5.0),
        STRUCT( 1, 'h2h_favoravel',          'ambos',  4.0),

        {# Gols — Over Σ56 · Under Σ52 #}
        STRUCT( 5, 'ataque_combinado',       'Over',  12.0),
        STRUCT( 5, 'defesas_vazaveis',       'Over',  10.0),
        STRUCT( 5, 'xg_combinado_alto',      'Over',   8.0),
        STRUCT( 5, 'ritmo_alto',             'Over',   8.0),
        STRUCT( 5, 'ambos_vazam',            'Over',   6.0),
        STRUCT( 5, 'historico_over',         'Over',   6.0),
        STRUCT( 5, 'linha_subindo',          'Over',   6.0),
        STRUCT( 5, 'defesas_firmes',         'Under', 12.0),
        STRUCT( 5, 'clean_sheets_altos',     'Under', 10.0),
        STRUCT( 5, 'xg_baixo_combinado',     'Under', 10.0),
        STRUCT( 5, 'ataques_fracos',         'Under',  8.0),
        STRUCT( 5, 'historico_under',        'Under',  6.0),
        STRUCT( 5, 'linha_descendo',         'Under',  6.0),

        {# Handicap — Favorito Σ40 · Azarão Σ30 #}
        STRUCT( 4, 'supremacia',             'Favorito', 12.0),
        STRUCT( 4, 'tende_golear',           'Favorito', 10.0),
        STRUCT( 4, 'adversario_fragil_fora', 'Favorito',  8.0),
        STRUCT( 4, 'mando_forte',            'Favorito',  6.0),
        STRUCT( 4, 'sem_rodizio',            'Favorito',  4.0),
        STRUCT( 4, 'raramente_perde_por_2',  'Azarao',   12.0),
        STRUCT( 4, 'defesa_fora_solida',     'Azarao',   10.0),
        STRUCT( 4, 'favorito_irregular',     'Azarao',    8.0),

        {# BTTS — Sim Σ34 · Não Σ28 #}
        STRUCT( 8, 'ambos_marcam',           'Yes',  12.0),
        STRUCT( 8, 'ataque_dos_dois',        'Yes',   8.0),
        STRUCT( 8, 'defesas_vazaveis',       'Yes',   8.0),
        STRUCT( 8, 'historico_btts',         'Yes',   6.0),
        STRUCT( 8, 'defesa_forte',           'No',   12.0),
        STRUCT( 8, 'ataque_trava',           'No',   10.0),
        STRUCT( 8, 'historico_seco',         'No',    6.0),

        {# Dupla Chance — Σ34, lado único #}
        STRUCT(12, 'lado_coberto_forte',     'ambos', 12.0),
        STRUCT(12, 'equilibrio_defensivo',   'ambos',  8.0),
        STRUCT(12, 'adversario_limitado',    'ambos',  8.0),
        STRUCT(12, 'invicto_recente',        'ambos',  6.0)
    ])
),

pesos_catalogo AS (
    SELECT 'E. catalogo' AS fonte, market_id, premissa, lado, peso FROM catalogo
    UNION ALL
    SELECT 'F. catalogo_sem_mov', market_id, premissa, lado,
           IF(premissa IN ('linha_subindo', 'linha_descendo'), 0.0, peso)
    FROM catalogo
),

pesos AS (
    SELECT * FROM pesos_t2
    UNION ALL SELECT * FROM pesos_t1
    UNION ALL SELECT * FROM pesos_catalogo
),

{# Teto por (fonte, mercado, LADO). Peso marcado 'ambos' conta em todos os lados — é o que
   faz A–D reproduzirem o teto por mercado do Teste 4. #}
teto AS (
    SELECT p.fonte, l.market_id, l.lado, SUM(p.peso) AS pts_max
    FROM lados AS l
    JOIN pesos AS p
      ON  p.market_id = l.market_id
      AND (p.lado = 'ambos' OR p.lado = l.lado)
    GROUP BY p.fonte, l.market_id, l.lado
),

notas AS (
    SELECT
        a.fixture_id, a.market_id, a.lado, a.metade, a.ganhou, a.best_odd,
        a.pts_corroboracao, a.penalidades_globais_pts, a.penalidades_especificas_pts,
        p.fonte,
        SUM(IF(pl.acesa, p.peso, 0)) AS nota_pts,
        ANY_VALUE(t.pts_max)         AS pts_max
    FROM apostas_m AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    JOIN pesos AS p
      ON  p.market_id = pl.market_id
      AND p.premissa  = pl.premissa
      AND (p.lado = 'ambos' OR p.lado = a.lado)
    JOIN teto AS t
      ON t.fonte = p.fonte AND t.market_id = a.market_id AND t.lado = a.lado
    GROUP BY a.fixture_id, a.market_id, a.lado, a.metade, a.ganhou, a.best_odd,
             a.pts_corroboracao, a.penalidades_globais_pts, a.penalidades_especificas_pts,
             a.outcome_side, a.line_value, p.fonte
),

avaliado AS (
    SELECT
        CASE
            WHEN fonte = 'B. t2_h1' AND metade = 2 THEN 'C. t2_h1 -> 2a metade (OUT-OF-SAMPLE)'
            WHEN fonte = 'B. t2_h1'                THEN 'B. t2_h1 -> 1a metade (in-sample)'
            {# E/F não são ajustadas em metade nenhuma: o catálogo é fixo. As duas metades
               são igualmente válidas, e a 2ª é a que compara com a C. #}
            WHEN fonte IN ('E. catalogo', 'F. catalogo_sem_mov')
                 THEN CONCAT(fonte, IF(metade = 2, ' -> 2a metade', ' -> 1a metade'))
            ELSE fonte
        END                                                          AS avaliacao,
        composicao.nome                                              AS composicao,
        fixture_id,
        LEAST(GREATEST(SAFE_DIVIDE(composicao.pts, composicao.teto) * 100, 0), 100) AS nota_pct,
        IF(ganhou, best_odd, 0) - 1                                  AS lucro
    FROM notas
    CROSS JOIN UNNEST([
        STRUCT('1. nota_premissas' AS nome, nota_pts AS pts, pts_max AS teto),
        STRUCT('2. score_pos_a1',
               nota_pts + pts_corroboracao
                        - penalidades_globais_pts - penalidades_especificas_pts,
               pts_max + 15),
        {# A fórmula que vai a produção: contexto menos penalidade de contexto, piso em 0. #}
        STRUCT('3. nota_menos_pen_contexto',
               GREATEST(nota_pts - penalidades_especificas_pts, 0),
               pts_max)
    ]) AS composicao
    WHERE pts_max > 0
),

com_faixa AS (
    SELECT *,
           CASE WHEN nota_pct >= 80 THEN 'e. 80-100'
                WHEN nota_pct >= 60 THEN 'd. 60-80'
                WHEN nota_pct >= 40 THEN 'c. 40-60'
                WHEN nota_pct >= 20 THEN 'b. 20-40'
                ELSE                     'a. 00-20' END AS faixa,
           AVG(lucro) OVER (PARTITION BY avaliacao, composicao,
                            CASE WHEN nota_pct >= 80 THEN 5 WHEN nota_pct >= 60 THEN 4
                                 WHEN nota_pct >= 40 THEN 3 WHEN nota_pct >= 20 THEN 2
                                 ELSE 1 END)            AS media_faixa
    FROM avaliado
),

por_fixture AS (
    SELECT avaliacao, composicao, faixa, fixture_id,
           SUM(lucro - media_faixa) AS resid_jogo
    FROM com_faixa
    GROUP BY 1, 2, 3, 4
),
erro AS (
    SELECT avaliacao, composicao, faixa,
           SUM(POW(resid_jogo, 2)) AS soma_quad,
           COUNT(*)                AS n_jogos
    FROM por_fixture GROUP BY 1, 2, 3
),

faixas AS (
    SELECT
        c.avaliacao, c.composicao, c.faixa,
        COUNT(*)                                   AS n_apostas,
        e.n_jogos,
        ROUND(AVG(c.nota_pct), 1)                  AS nota_media,
        ROUND(AVG(c.lucro) * 100, 1)               AS roi,
        ROUND(SAFE_DIVIDE(SQRT(e.soma_quad), COUNT(*)) * 100, 1) AS ep_cluster,
        CAST(NULL AS FLOAT64)                      AS inclinacao
    FROM com_faixa AS c
    JOIN erro AS e USING (avaliacao, composicao, faixa)
    GROUP BY c.avaliacao, c.composicao, c.faixa, e.soma_quad, e.n_jogos
),

continuo AS (
    SELECT
        avaliacao, composicao, 'z. CONTINUO (todas)' AS faixa,
        COUNT(*)                                       AS n_apostas,
        COUNT(DISTINCT fixture_id)                     AS n_jogos,
        ROUND(AVG(nota_pct), 1)                        AS nota_media,
        ROUND(AVG(lucro) * 100, 1)                     AS roi,
        CAST(NULL AS FLOAT64)                          AS ep_cluster,
        ROUND(COVAR_SAMP(lucro, nota_pct)
              / NULLIF(VAR_SAMP(nota_pct), 0) * 100, 3) AS inclinacao
    FROM com_faixa
    GROUP BY avaliacao, composicao
)

SELECT * FROM faixas
UNION ALL SELECT * FROM continuo
ORDER BY composicao, avaliacao, faixa
