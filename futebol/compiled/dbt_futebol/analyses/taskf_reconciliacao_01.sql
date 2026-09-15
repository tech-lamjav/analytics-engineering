WITH 

publicado_01 AS (
    SELECT * FROM UNNEST([
        STRUCT<mercado STRING, premissa STRING,
               n_p0 INT64, a_odd_dava_p0 FLOAT64, aconteceu_p0 FLOAT64, diferenca_p0 FLOAT64,
               jogos_medios FLOAT64, pct_amostra_curta FLOAT64,
               peso_p0 FLOAT64, peso_p0_k0 FLOAT64,
               n_p5 INT64, diferenca_p5 FLOAT64, diferenca_p10 FLOAT64>
        ('Gols',         'clean_sheets_altos',     105, 51.5, 68.6,  17.1,  5.3, 77.1, 11.58, 17.10,   24,  -1.7, -10.1),
        ('Handicap',     'raramente_perde_por_2',  445, 63.1, 69.4,   6.3, 14.1, 20.9,  5.67,  6.31,  352,   7.4,   7.7),
        ('Handicap',     'favorito_irregular',     453, 62.3, 68.2,   5.9, 14.8, 17.4,  5.29,  5.88,  374,   7.1,   7.9),
        ('BTTS',         'ataque_dos_dois',         32, 50.6, 62.5,  11.9, 12.1, 37.5,  4.65, 11.91, NULL,  NULL,  NULL),
        ('1X2',          'superioridade_xg',       109, 38.0, 43.1,   5.2,  6.3, 71.6,  3.54,  5.17,   31,  -8.9, -12.3),
        ('Handicap',     'defesa_fora_solida',     322, 62.5, 66.5,   3.9,  8.4, 58.4,  3.39,  3.92,  134,   2.6,   2.8),
        ('Gols',         'defesas_firmes',         246, 64.6, 68.3,   3.7, 11.4, 40.7,  3.05,  3.67, NULL,  NULL,  NULL),
        ('Handicap',     'tende_golear',           154, 44.2, 48.1,   3.9,  3.5, 88.3,  2.91,  3.86,   18, -18.5, -22.3),
        ('Gols',         'linha_descendo',         405, 53.0, 56.0,   3.1, 10.3, 46.9,  2.74,  3.08,  215,   5.3,   5.3),
        ('Dupla Chance', 'lado_coberto_forte',     112, 74.0, 76.8,   2.8,  8.6, 58.0,  1.92,  2.78, NULL,  NULL,  NULL),
        ('Gols',         'ataques_fracos',         357, 51.7, 53.8,   2.1,  9.6, 50.1,  1.81,  2.07,  178,  -1.1,  -1.1),
        ('BTTS',         'defesa_forte',            70, 52.9, 55.7,   2.8,  4.4, 82.9,  1.65,  2.82,   12,  -3.3,  -6.3),
        ('1X2',          'mando',                  107, 43.4, 45.8,   2.4,  9.0, 55.1,  1.63,  2.39,   48,  -6.4,  -8.3),
        ('Dupla Chance', 'equilibrio_defensivo',   144, 63.3, 65.3,   2.0,  9.0, 54.2,  1.49,  2.01,   66,   6.4,   7.7),
        ('Gols',         'xg_baixo_combinado',     307, 64.9, 66.4,   1.5,  8.7, 56.7,  1.31,  1.52,  133,   3.6,   4.1),
        ('BTTS',         'defesas_vazaveis',        58, 47.8, 50.0,   2.2, 10.3, 46.6,  1.20,  2.24,   31,   8.7,   8.7),
        ('Gols',         'historico_under',        144, 70.0, 71.5,   1.5, 17.0,  3.5,  1.11,  1.50,  139,   1.2,   2.1),
        ('1X2',          'superioridade_tabela',    98, 50.2, 51.0,   0.8,  7.6, 64.3,  0.55,  0.82,   35,  -8.2,  -8.2),
        ('Dupla Chance', 'adversario_limitado',    160, 68.7, 69.4,   0.7,  9.7, 50.0,  0.51,  0.66, NULL,  NULL,  NULL),
        ('BTTS',         'historico_btts',          16, 50.0, 50.0,   0.0, 18.4,  0.0,  0.01,  0.03, NULL,  NULL,  NULL),
        ('Gols',         'historico_over',        NULL, NULL, NULL,  -0.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'historico_seco',        NULL, NULL, NULL,  -0.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'forma',                 NULL, NULL, NULL,  -1.4, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'linha_subindo',         NULL, NULL, NULL,  -1.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'supremacia',            NULL, NULL, NULL,  -1.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'ataque_trava',          NULL, NULL, NULL,  -2.2, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'ambos_marcam',          NULL, NULL, NULL,  -2.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'xg_combinado_alto',     NULL, NULL, NULL,  -2.6, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'sem_rodizio',           NULL, NULL, NULL,  -2.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'adversario_fragil_fora',NULL, NULL, NULL,  -2.8, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'mando_forte',           NULL, NULL, NULL,  -3.1, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'forca_mismatch',        NULL, NULL, NULL,  -3.1, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ataque_combinado',      NULL, NULL, NULL,  -3.6, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ambos_vazam',           NULL, NULL, NULL,  -3.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'defesas_vazaveis',      NULL, NULL, NULL,  -5.0, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ritmo_alto',            NULL, NULL, NULL,  -5.3, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'h2h_favoravel',         NULL, NULL, NULL, -10.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Dupla Chance', 'invicto_recente',       NULL, NULL, NULL, -10.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'desfalque_adversario',     7, NULL, NULL, -24.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL)
    ])
)

,

jogos_congelados AS (
    SELECT fixture_id
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      AND (kickoff_utc >= TIMESTAMP('2026-06-16')
     AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00'))
),deriva AS (
    SELECT COUNTIF(o.collection_date > DATE('2026-08-04 12:00:00')) AS capturas_apos_o_teto
    FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot` AS o
    JOIN jogos_congelados USING (fixture_id)
),pinnacle_nas_linhas AS (
    SELECT DISTINCT
        fixture_id,
        market_id,
        COALESCE(CAST(line_value AS STRING), 'NONE') AS line_key
    FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    WHERE bookmaker_id = 4
),

nuladas_pela_22 AS (
    SELECT
        d.market_id,
        p.fixture_id IS NOT NULL AS tinha_pinnacle
    FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig` AS d
    JOIN jogos_congelados USING (fixture_id)
    LEFT JOIN pinnacle_nas_linhas AS p
           ON  p.fixture_id = d.fixture_id
           AND p.market_id  = d.market_id
           AND p.line_key   = COALESCE(CAST(d.line_value AS STRING), 'NONE')
    WHERE d.market_id IN (1, 5, 4, 8, 12)
      AND COALESCE(d.n_outcomes_valor < 2, TRUE)
),

alcance_22 AS (
    SELECT
        CASE market_id
            WHEN 1 THEN '1X2'
            WHEN 5 THEN 'Gols'
            WHEN 4 THEN 'Handicap'
            WHEN 8 THEN 'BTTS'
            WHEN 12 THEN 'Dupla Chance'
        END AS mercado,
        COUNT(*)                                        AS linhas_nuladas,
        IF(market_id = 8, COUNT(*), COUNTIF(tinha_pinnacle)) AS alcanca_o_preferido
    FROM nuladas_pela_22
    GROUP BY market_id
),

medido AS (
    SELECT
        mercado, premissa, benchmark, usado_para_peso,
        jogos_no_universo, medido_em, git_sha,
        n_p0, a_odd_dava_p0, aconteceu_p0, diferenca_p0,jogos_medios_disp AS jogos_medios, pct_amostra_curta, peso_p0, peso_p0_k0,
        n_p5, diferenca_p5, diferenca_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    WHERE celula = 'base'
      AND universo = 'completo'
      AND usado_para_peso
),juntado AS (
    SELECT
        COALESCE(m.mercado,  p.mercado)  AS mercado,
        COALESCE(m.premissa, p.premissa) AS premissa,
        m.jogos_no_universo,
        m.medido_em,
        m.git_sha,
        m.mercado  IS NULL AS so_no_publicado,
        p.mercado  IS NULL AS so_no_medido,

        m.n_p0              AS n_p0_medido,          p.n_p0              AS n_p0_pub,
        m.diferenca_p0      AS dif_p0_medido,        p.diferenca_p0      AS dif_p0_pub,
        m.a_odd_dava_p0     AS a_odd_dava_p0_medido, p.a_odd_dava_p0     AS a_odd_dava_p0_pub,
        m.aconteceu_p0      AS aconteceu_p0_medido,  p.aconteceu_p0      AS aconteceu_p0_pub,
        m.jogos_medios      AS jogos_medios_medido,  p.jogos_medios      AS jogos_medios_pub,
        m.pct_amostra_curta AS pct_curta_medido,     p.pct_amostra_curta AS pct_curta_pub,
        m.peso_p0           AS peso_p0_medido,       p.peso_p0           AS peso_p0_pub,
        m.peso_p0_k0        AS peso_p0_k0_medido,    p.peso_p0_k0        AS peso_p0_k0_pub,
        m.n_p5              AS n_p5_medido,          p.n_p5              AS n_p5_pub,
        m.diferenca_p5      AS dif_p5_medido,        p.diferenca_p5      AS dif_p5_pub,
        m.diferenca_p10     AS dif_p10_medido,       p.diferenca_p10     AS dif_p10_pub
    FROM medido AS m
    FULL OUTER JOIN publicado_01 AS p
      ON  p.mercado  = m.mercado
      AND p.premissa = m.premissa
),

classificado AS (SELECT
        jt.*,GREATEST(
            COALESCE(ABS(dif_p0_medido  - dif_p0_pub),  0),
            COALESCE(ABS(dif_p5_medido  - dif_p5_pub),  0),
            COALESCE(ABS(dif_p10_medido - dif_p10_pub), 0)
        ) AS maior_delta_pp,

        (IF(dif_p0_pub        IS NOT NULL, 1, 0)
       + IF(dif_p5_pub        IS NOT NULL, 1, 0)
       + IF(dif_p10_pub       IS NOT NULL, 1, 0)
       + IF(n_p0_pub          IS NOT NULL, 1, 0)
       + IF(n_p5_pub          IS NOT NULL, 1, 0)
       + IF(a_odd_dava_p0_pub IS NOT NULL, 1, 0)
       + IF(aconteceu_p0_pub  IS NOT NULL, 1, 0)
       + IF(jogos_medios_pub  IS NOT NULL, 1, 0)
       + IF(pct_curta_pub     IS NOT NULL, 1, 0)
       + IF(peso_p0_pub       IS NOT NULL, 1, 0)
       + IF(peso_p0_k0_pub    IS NOT NULL, 1, 0)) AS campos_comparados,(IF(jogos_medios_pub  IS NOT NULL AND jogos_medios_medido  IS DISTINCT FROM jogos_medios_pub,  1, 0)
       + IF(pct_curta_pub     IS NOT NULL AND pct_curta_medido     IS DISTINCT FROM pct_curta_pub,     1, 0)
       + IF(peso_p0_pub       IS NOT NULL AND peso_p0_medido       IS DISTINCT FROM peso_p0_pub,       1, 0)
       + IF(peso_p0_k0_pub    IS NOT NULL AND peso_p0_k0_medido    IS DISTINCT FROM peso_p0_k0_pub,    1, 0)
       + IF(n_p0_pub          IS NOT NULL AND n_p0_medido          IS DISTINCT FROM n_p0_pub,          1, 0)
       + IF(n_p5_pub          IS NOT NULL AND n_p5_medido          IS DISTINCT FROM n_p5_pub,          1, 0)
       + IF(a_odd_dava_p0_pub IS NOT NULL AND a_odd_dava_p0_medido IS DISTINCT FROM a_odd_dava_p0_pub, 1, 0)
       + IF(aconteceu_p0_pub  IS NOT NULL AND aconteceu_p0_medido  IS DISTINCT FROM aconteceu_p0_pub,  1, 0))
                                                                        AS campos_divergentes_fora_da_regua,

        d.capturas_apos_o_teto,
        COALESCE(a.alcanca_o_preferido, 0) AS linhas_da_22_no_preferido,CASE
            WHEN premissa IN ("linha_subindo", "linha_descendo")
                 AND d.capturas_apos_o_teto > 0            THEN 'deriva_de_odds'
            WHEN COALESCE(a.alcanca_o_preferido, 0) > 0    THEN 'correcao_22'
            ELSE 'investigar'
        END AS origem
    FROM juntado AS jt
    CROSS JOIN deriva AS d
    LEFT JOIN alcance_22 AS a ON a.mercado = jt.mercado
)

SELECT
    mercado,
    premissa,
    origem,
    campos_comparados,
    so_no_medido,
    so_no_publicado,
    n_p0_pub,  n_p0_medido,  n_p0_medido  - n_p0_pub  AS delta_n_p0,
    dif_p0_pub,  dif_p0_medido,  ROUND(dif_p0_medido  - dif_p0_pub,  1) AS delta_p0,
    dif_p5_pub,  dif_p5_medido,  ROUND(dif_p5_medido  - dif_p5_pub,  1) AS delta_p5,
    dif_p10_pub, dif_p10_medido, ROUND(dif_p10_medido - dif_p10_pub, 1) AS delta_p10,
    n_p5_pub, n_p5_medido, n_p5_medido - n_p5_pub AS delta_n_p5,
    a_odd_dava_p0_pub, a_odd_dava_p0_medido,
    aconteceu_p0_pub,  aconteceu_p0_medido,
    jogos_medios_pub,  jogos_medios_medido,
    pct_curta_pub,     pct_curta_medido,
    peso_p0_pub,       peso_p0_medido,
    peso_p0_k0_pub,    peso_p0_k0_medido,
    campos_divergentes_fora_da_regua,
    capturas_apos_o_teto,
    linhas_da_22_no_preferido,
    ROUND(maior_delta_pp, 1) AS maior_delta_pp,
    0.25 AS tolerancia_pp,CASE
        WHEN so_no_medido OR so_no_publicado    THEN 'SEM_CONTRAPARTE'
        WHEN campos_comparados = 0              THEN 'NADA_A_COMPARAR'
        WHEN maior_delta_pp = 0
             AND campos_divergentes_fora_da_regua = 0 THEN 'EXATO'
        WHEN origem = 'deriva_de_odds'
             AND maior_delta_pp <= 0.25    THEN 'DENTRO_DA_TOLERANCIA'
        WHEN origem = 'deriva_de_odds'          THEN 'DERIVA_ACIMA_DA_TOLERANCIA'
        WHEN origem = 'correcao_22'             THEN 'CORRECAO_22_ALCANCA'
        ELSE                                         'INVESTIGAR'
    END AS veredito,
    jogos_no_universo,
    medido_em,
    git_sha
FROM classificado
ORDER BY maior_delta_pp DESC, mercado, premissa