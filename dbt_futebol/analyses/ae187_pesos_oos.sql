{#
    AE#187 (remedição do #185, pedido do Victor em wdx6zf1v4m 17/09) — pesos do catálogo
    de Total de escanteios (market_id 45) com CONTROLE FORA DA AMOSTRA (ADR 0001),
    idêntico ao #185 em tudo EXCETO a partição do split temporal: aqui é
    `NTILE(2) OVER (PARTITION BY competition_id ORDER BY kickoff_utc, fixture_id)`, em vez
    do `NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id)` global que o #185 usou (medido em
    `ae185_confundidor_metade.sql` como ~83% Brasil/CONMEBOL na metade 1). A estratificação
    por competição foi conferida em `ae187_confundidor_estratificado.sql` antes desta query
    — cada competição contribui quase exatamente igual às duas metades (ex.: serie_b 59/58,
    brasileirao 42/41, champions_league 10/10).

    Catálogo candidato: o MESMO `candidato_t` hardcoded do #185 (23 combinações
    premissa×lado que mediram "com ganho" no Teste 2 completo do #183) — conferido no
    corpo da issue #187 que já reflete as 5 correções que o Victor pediu no comentário de
    17/09 (não precisa recalcular).

    Regra de peso, teto, direções A/B e régua de aceite: idênticos ao #185. Só a coluna
    `metade` muda de fonte.

    Rodar com:
      dbt compile --select ae187_pesos_oos
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae187_pesos_oos.sql
#}

CREATE TEMP TABLE apostas_t AS (
    WITH {{ ae183_base_escanteios_total(cutoff=none, janela_fixa=none, gates_do_board=true) }}
    SELECT * FROM apostas
);

-- ÚNICA MUDANÇA EM RELAÇÃO AO #185: PARTITION BY competition_id, não global.
CREATE TEMP TABLE metades_t AS (
    SELECT fixture_id,
           NTILE(2) OVER (PARTITION BY competition_id ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc, competition_id FROM apostas_t)
);

-- Sub-partição DENTRO de cada metade (nunca cruza a fronteira metade 1/2) — usada só pra
-- checar estabilidade na metade de AJUSTE, nunca toca a metade de medição. Mesma técnica
-- do #185, sem estratificação adicional aqui (a fronteira metade 1/2 já é estratificada;
-- dentro dela, a ordem temporal simples é suficiente pro teste de estabilidade).
CREATE TEMP TABLE sub_metades_t AS (
    SELECT j.fixture_id, m.metade,
           NTILE(2) OVER (PARTITION BY m.metade ORDER BY j.kickoff_utc, j.fixture_id) AS sub_metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc FROM apostas_t) j
    JOIN metades_t m USING (fixture_id)
);

CREATE TEMP TABLE premissas_t AS (
    {{ ae183_premissas_escanteios_total_sql(tabela='apostas_t') }}
);

-- Catálogo candidato — idêntico ao #185.
CREATE TEMP TABLE candidato_t AS (
    SELECT * FROM UNNEST([
        STRUCT('Mais' AS lado, 'ataque_de_escanteio'     AS premissa),
        STRUCT('Mais' AS lado, 'finalizacao_na_area'     AS premissa),
        STRUCT('Mais' AS lado, 'volume_de_finalizacao'   AS premissa),
        STRUCT('Mais' AS lado, 'chance_de_gol'           AS premissa),
        STRUCT('Mais' AS lado, 'desequilibrio_de_posse'  AS premissa),
        STRUCT('Mais' AS lado, 'mata_mata'               AS premissa),
        STRUCT('Mais' AS lado, 'finalizacao_de_fora'     AS premissa),
        STRUCT('Mais' AS lado, 'pressao_do_mandante'     AS premissa),
        STRUCT('Mais' AS lado, 'jogo_faltoso'            AS premissa),
        STRUCT('Mais' AS lado, 'bloqueios'                AS premissa),
        STRUCT('Menos' AS lado, 'volume_de_finalizacao'   AS premissa),
        STRUCT('Menos' AS lado, 'bloqueios'                AS premissa),
        STRUCT('Menos' AS lado, 'finalizacao_de_fora'      AS premissa),
        STRUCT('Menos' AS lado, 'chute_de_longe'           AS premissa),
        STRUCT('Menos' AS lado, 'jogo_faltoso'             AS premissa),
        STRUCT('Menos' AS lado, 'finalizacao_na_area'      AS premissa),
        STRUCT('Menos' AS lado, 'escanteio_previsto'       AS premissa),
        STRUCT('Menos' AS lado, 'ataque_de_escanteio'      AS premissa),
        STRUCT('Menos' AS lado, 'desequilibrio_de_posse'   AS premissa),
        STRUCT('Menos' AS lado, 'campeonato_de_escanteio'  AS premissa),
        STRUCT('Menos' AS lado, 'previsao_x_linha'         AS premissa),
        STRUCT('Menos' AS lado, 'chance_de_gol'            AS premissa),
        STRUCT('Menos' AS lado, 'pressao_do_mandante'      AS premissa)
    ])
);

CREATE TEMP TABLE linhas_t AS (
    SELECT
        pc.fixture_id, pc.outcome_side, pc.lado, pc.premissa, pc.acesa,
        pc.ganhou, pc.prob_justa_fechamento, pc.benchmark,
        a.kickoff_utc, a.best_odd,
        m.metade, sm.sub_metade
    FROM premissas_t pc
    JOIN candidato_t c    ON c.lado = pc.lado AND c.premissa = pc.premissa
    JOIN apostas_t a      ON a.fixture_id = pc.fixture_id AND a.outcome_side = pc.outcome_side
    JOIN metades_t m      ON m.fixture_id = a.fixture_id
    JOIN sub_metades_t sm ON sm.fixture_id = a.fixture_id
);

CREATE TEMP TABLE ganho_full_t AS (
    SELECT
        'A' AS direcao, lado, premissa,
        COUNTIF(acesa) AS n,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp
    FROM linhas_t
    WHERE metade = 1 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa
    HAVING COUNTIF(acesa) > 0

    UNION ALL

    SELECT
        'B' AS direcao, lado, premissa,
        COUNTIF(acesa) AS n,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp
    FROM linhas_t
    WHERE metade = 2 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa
    HAVING COUNTIF(acesa) > 0
);

CREATE TEMP TABLE ganho_sub_t AS (
    SELECT
        'A' AS direcao, lado, premissa, sub_metade,
        COUNTIF(acesa) AS n_sub,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp_sub
    FROM linhas_t
    WHERE metade = 1 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa, sub_metade
    HAVING COUNTIF(acesa) > 0

    UNION ALL

    SELECT
        'B' AS direcao, lado, premissa, sub_metade,
        COUNTIF(acesa) AS n_sub,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp_sub
    FROM linhas_t
    WHERE metade = 2 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa, sub_metade
    HAVING COUNTIF(acesa) > 0
);

CREATE TEMP TABLE pesos_t AS (
    WITH estabilidade AS (
        SELECT
            direcao, lado, premissa,
            MAX(IF(sub_metade = 1, diferenca_pp_sub, NULL)) AS diff_sub1,
            MAX(IF(sub_metade = 2, diferenca_pp_sub, NULL)) AS diff_sub2
        FROM ganho_sub_t
        GROUP BY direcao, lado, premissa
    ),
    niveis_tamanho AS (
        SELECT direcao, lado, premissa,
            NTILE(3) OVER (
                PARTITION BY direcao, lado
                ORDER BY diferenca_pp DESC, n DESC, premissa ASC
            ) AS nivel_tamanho
        FROM ganho_full_t
        WHERE diferenca_pp > 0
    )
    SELECT
        gf.direcao, gf.lado, gf.premissa, gf.n,
        ROUND(gf.diferenca_pp, 2) AS diferenca_pp,
        COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AS estavel,
        nt.nivel_tamanho,
        CASE
            WHEN gf.diferenca_pp <= 0 THEN 0
            WHEN     COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 1 THEN 9
            WHEN     COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 2 THEN 6
            WHEN     COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 3 THEN 3
            WHEN NOT COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 1 THEN 3
            WHEN NOT COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 2 THEN 2
            WHEN NOT COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 3 THEN 1
            ELSE 0
        END AS peso
    FROM ganho_full_t gf
    LEFT JOIN estabilidade e    USING (direcao, lado, premissa)
    LEFT JOIN niveis_tamanho nt USING (direcao, lado, premissa)
);

CREATE TEMP TABLE teto_t AS (
    SELECT direcao, lado, SUM(peso) AS teto
    FROM pesos_t
    GROUP BY direcao, lado
);

CREATE TEMP TABLE score_t AS (
    SELECT
        'A' AS direcao, l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd,
        ANY_VALUE(l.ganhou) AS ganhou,
        SUM(IF(l.acesa, COALESCE(w.peso, 0), 0)) AS soma_pesos
    FROM linhas_t l
    LEFT JOIN pesos_t w
      ON w.direcao = 'A' AND w.lado = l.lado AND w.premissa = l.premissa
    WHERE l.metade = 2
    GROUP BY l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd

    UNION ALL

    SELECT
        'B' AS direcao, l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd,
        ANY_VALUE(l.ganhou) AS ganhou,
        SUM(IF(l.acesa, COALESCE(w.peso, 0), 0)) AS soma_pesos
    FROM linhas_t l
    LEFT JOIN pesos_t w
      ON w.direcao = 'B' AND w.lado = l.lado AND w.premissa = l.premissa
    WHERE l.metade = 1
    GROUP BY l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd
);

CREATE TEMP TABLE faixado_t AS (
    SELECT
        s.*,
        t.teto,
        SAFE_DIVIDE(100.0 * s.soma_pesos, t.teto) AS score_0_100,
        CASE
            WHEN t.teto IS NULL OR t.teto = 0 THEN 'sem_teto'
            WHEN SAFE_DIVIDE(100.0 * s.soma_pesos, t.teto) >= 60 THEN 'Alta'
            WHEN SAFE_DIVIDE(100.0 * s.soma_pesos, t.teto) >= 30 THEN 'Média'
            ELSE 'Baixa'
        END AS faixa,
        IF(s.ganhou, s.best_odd - 1, -1) AS lucro
    FROM score_t s
    LEFT JOIN teto_t t ON t.direcao = s.direcao AND t.lado = s.lado
);

WITH checagem_unicidade AS (
    SELECT COUNT(*) AS linhas,
           COUNT(DISTINCT CONCAT(CAST(fixture_id AS STRING), '|', outcome_side)) AS chaves_distintas
    FROM apostas_t
),

resultado AS (
    SELECT
        direcao, lado, faixa,
        COUNT(*)                   AS n,
        ROUND(AVG(lucro) * 100, 2) AS roi_pct
    FROM faixado_t
    GROUP BY 1, 2, 3
)

SELECT
    'faixa' AS bloco, direcao, lado, faixa, n, roi_pct,
    CAST(NULL AS FLOAT64) AS linhas_check, CAST(NULL AS FLOAT64) AS chaves_check,
    CAST(NULL AS BOOL) AS estavel, CAST(NULL AS INT64) AS nivel_tamanho
FROM resultado

UNION ALL

SELECT
    'checagem_unica' AS bloco, CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
    CAST(NULL AS INT64), CAST(NULL AS FLOAT64),
    CAST(linhas AS FLOAT64), CAST(chaves_distintas AS FLOAT64),
    CAST(NULL AS BOOL), CAST(NULL AS INT64)
FROM checagem_unicidade

UNION ALL

SELECT
    'pesos' AS bloco, direcao, lado, premissa, n, diferenca_pp,
    CAST(peso AS FLOAT64) AS linhas_check, CAST(NULL AS FLOAT64) AS chaves_check,
    estavel, nivel_tamanho
FROM pesos_t

UNION ALL

SELECT
    'teto' AS bloco, t.direcao, t.lado, CAST(NULL AS STRING),
    CAST(NULL AS INT64), CAST(NULL AS FLOAT64),
    CAST(t.teto AS FLOAT64) AS linhas_check, CAST(NULL AS FLOAT64) AS chaves_check,
    CAST(NULL AS BOOL), CAST(NULL AS INT64)
FROM teto_t AS t

ORDER BY bloco, direcao, lado, faixa
