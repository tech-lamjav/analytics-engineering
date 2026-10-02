-- TERMO 4 da ADR 0010 / issue AE#117 -- contagem dos quatro pisos da janela nova.
-- SOMENTE LEITURA, tabelas de PRODUCAO (dataset `futebol`). Nao passa por dbt: e uma analysis
-- so para viver no repo; compile/rode com o bq (SQL sempre por `< arquivo`, nunca como argumento).
--
-- Janela: kickoff_utc em [2026-08-04 12:00:00, 2026-10-01 00:00:00) UTC (declarada em 25/08, #117).
-- Rodar:  bq --headless query --use_legacy_sql=false --project_id=smartbetting-dados --format=csv \
--             < dbt_futebol/analyses/ae117_termo4_pisos.sql
-- A saida do `bq --headless` ecoa o SQL antes do CSV: leia a partir da linha que comeca com `secao,`.
--
-- Para a contagem FINAL, em 01/10 (janela fechada), NAO mude nada: o teto ja e 2026-10-01 00:00 UTC
-- e o filtro FT so enxerga jogo encerrado. So vale depois de o workflow-futebol de 01/10 (ou
-- posterior) reconstruir fact_fixtures e int_futebol_odds_devig -- confira MAX(dbt_loaded_at) > 01/10
-- 00:00 UTC e que nao ha jogo de 30/09 fora de FT/AET/PEN.
--
-- REPLICA A MAO (sem dbt) o task01_base() em aa9f44a:
--   * jogos_encerrados / odds / prem_n / pit / apostas -> macros/task01_base.sql
--     - status_short='FT' AND goals_home IS NOT NULL (AET/PEN ficam FORA); piso 5 = pit;
--       _col_piso = played_total_disponivel no default pit_recorte='ultimos_10'
--       VALIDADO: janela [2026-06-16, 2026-08-04 12:00) devolve 169 jogos / 5.605 linhas na
--       leitura SEM_GATES = linhas_no_universo da ancora 1b9c757
--     - odds = int_futebol_odds_devig reduzido a janela corrente (devig_janela.sql)
--     - INNER JOIN com as premissas (market, fixture, outcome, line); best_odd/edge NOT NULL;
--       market_id IN (1,4,5,8,12); meia-linha (futebol_linha_meia.sql)
--     - gates do board (b4aad43): n_casas>=4, NOT pen_odd_outlier, faixa de odd 1,50-4,00
--       (Dupla Chance 1,25-2,00) -- desligados por task01_base(gates_board=false)
--   * familia -> macros/taskf_familia_competicao.sql (LOGICAL_OR da virada de ano por temporada,
--     lendo TODO o fact_fixtures)
-- Omitidos de `apostas` por nao mudarem o CONJUNTO DE JOGOS: LEFT JOIN de corroboracao e de
-- prem_linha (so acrescentam colunas).
--
-- Duas leituras do universo, ambas reportadas:
--   SEM_GATES = task01_base(gates_board=false): o universo do Teste 2 (ADR 0010, emenda de 29/09)
--   COM_GATES = task01_base() default: leitura secundaria, o universo que o board enxerga
-- e as mesmas duas SEM selecoes (copa_mundo, nations_league, amistosos), sufixo _PRIMARIO: o universo
-- primario da emenda, que e a contagem do termo 4 (AE#117, 01/10). SEM_GATES/COM_GATES continuam
-- aqui porque sao as leituras das contagens provisorias de 29/09 e do comentario de 01/10.
--
-- Saida: UMA tabela longa (secao, ...) -- resumo por piso e detalhe por competicao.

DECLARE janela_ini TIMESTAMP DEFAULT TIMESTAMP('2026-08-04 12:00:00');
DECLARE janela_fim TIMESTAMP DEFAULT TIMESTAMP('2026-10-01 00:00:00');

WITH
-- ---------------------------------------------------------------- familia (macro taskf_familia_competicao)
fam_por_temporada AS (
    SELECT
        competition_id,
        competition,
        season,
        COUNT(*)          AS n_fixtures,
        MIN(kickoff_utc)  AS primeiro_kickoff,
        MAX(kickoff_utc)  AS ultimo_kickoff,
        EXTRACT(YEAR FROM MAX(kickoff_utc)) > EXTRACT(YEAR FROM MIN(kickoff_utc)) AS atravessa_a_virada
    FROM `smartbetting-dados.futebol.fact_fixtures`
    GROUP BY competition_id, competition, season
),
familia_competicao AS (
    SELECT
        competition,
        MIN(competition_id)            AS competition_id,
        COUNT(DISTINCT competition_id) AS n_competition_ids,
        IF(LOGICAL_OR(atravessa_a_virada), 'split_year', 'ano_calendario') AS familia
    FROM fam_por_temporada
    GROUP BY competition
),

-- ---------------------------------------------------------------- task01_base() sem cutoff, janela aplicada cedo
jogos_encerrados AS (
    SELECT fixture_id, competition, season, home_team_id, away_team_id, kickoff_utc, goals_home, goals_away
    FROM `smartbetting-dados.futebol.fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      AND kickoff_utc >= janela_ini
      AND kickoff_utc <  janela_fim
),
odds AS (
    SELECT
        fixture_id, market_id, outcome_side, line_value, best_odd, edge, n_casas, pen_odd_outlier
    FROM (
        SELECT
            d.*,
            d._jp = MAX(d._jp) OVER (PARTITION BY d.fixture_id, d.market_id, d._lk) AS janela_e_corrente
        FROM (
            SELECT
                *,
                CASE janela_usada WHEN 't15m' THEN 4 WHEN 't1h' THEN 3 WHEN 't24h' THEN 2 WHEN 'daily' THEN 1 ELSE 0 END AS _jp,
                COALESCE(CAST(line_value AS STRING), 'NONE') AS _lk
            FROM `smartbetting-dados.futebol.int_futebol_odds_devig`
        ) d
    )
    WHERE janela_e_corrente
),
prem_n AS (
    SELECT 1 AS market_id, fixture_id, outcome AS outcome_side, CAST(NULL AS FLOAT64) AS line_value FROM `smartbetting-dados.futebol.int_futebol_premissas_1x2`
    UNION DISTINCT
    SELECT 5, fixture_id, outcome, line_value FROM `smartbetting-dados.futebol.int_futebol_premissas_ou`
    UNION DISTINCT
    SELECT 4, fixture_id, outcome, line_value FROM `smartbetting-dados.futebol.int_futebol_premissas_ah`
    UNION DISTINCT
    SELECT 8, fixture_id, outcome, CAST(NULL AS FLOAT64) FROM `smartbetting-dados.futebol.int_futebol_premissas_btts`
    UNION DISTINCT
    SELECT 12, fixture_id, outcome, CAST(NULL AS FLOAT64) FROM `smartbetting-dados.futebol.int_futebol_premissas_dc`
),
pit AS (
    SELECT
        j.fixture_id,
        LEAST(COALESCE(h.played_total_disponivel, 0), COALESCE(a.played_total_disponivel, 0)) AS min_jogos
    FROM jogos_encerrados AS j
    LEFT JOIN `smartbetting-dados.futebol.int_futebol_team_form_pit` AS h
           ON h.fixture_id = j.fixture_id AND h.team_id = j.home_team_id
    LEFT JOIN `smartbetting-dados.futebol.int_futebol_team_form_pit` AS a
           ON a.fixture_id = j.fixture_id AND a.team_id = j.away_team_id
),
apostas_base AS (
    SELECT
        o.market_id, o.fixture_id, o.outcome_side, o.line_value, o.best_odd, o.n_casas, o.pen_odd_outlier,
        j.competition, j.kickoff_utc,
        COALESCE(pit.min_jogos, 0) AS min_jogos
    FROM odds AS o
    JOIN jogos_encerrados AS j ON j.fixture_id = o.fixture_id
    JOIN prem_n AS pn
      ON  pn.market_id                  = o.market_id
      AND pn.fixture_id                 = o.fixture_id
      AND pn.outcome_side               = o.outcome_side
      AND COALESCE(pn.line_value, -999) = COALESCE(o.line_value, -999)
    LEFT JOIN pit ON pit.fixture_id = o.fixture_id
    WHERE o.best_odd IS NOT NULL
      AND o.edge     IS NOT NULL
      AND o.market_id IN (1, 5, 4, 8, 12)
      AND (o.market_id NOT IN (4, 5) OR MOD(CAST(ROUND(ABS(o.line_value) * 4) AS INT64), 4) = 2)
),
-- as duas leituras: uma linha por aposta, com o flag do gate do board
apostas AS (
    SELECT
        b.*,
        (   COALESCE(b.n_casas >= 4, FALSE)
        AND COALESCE(NOT b.pen_odd_outlier, FALSE)
        AND COALESCE(
              b.best_odd >= IF(b.market_id = 12, 1.25, 1.50)
              AND
              b.best_odd <= IF(b.market_id = 12, 2.00, 4.00),
              FALSE)
        ) AS passa_gates_board
    FROM apostas_base AS b
),
-- grao de JOGO por leitura: entra (tem >=1 aposta no universo da leitura); piso 5 e do jogo (min_jogos e por fixture)
jogos_leitura AS (
    SELECT 'SEM_GATES' AS leitura, fixture_id, ANY_VALUE(competition) AS competition,
           MAX(min_jogos) AS min_jogos, COUNT(*) AS n_apostas
    FROM apostas GROUP BY fixture_id
    UNION ALL
    SELECT 'COM_GATES', fixture_id, ANY_VALUE(competition), MAX(min_jogos), COUNT(*)
    FROM apostas WHERE passa_gates_board GROUP BY fixture_id
    UNION ALL
    -- As mesmas duas leituras SEM as selecoes (o universo PRIMARIO da emenda de 29/09): e a contagem
    -- que vale para o termo 4. A lista e a de macros/taskf_universos.sql (taskf_janela_nova().fora);
    -- aqui e copia porque esta analysis roda crua no bq, sem dbt.
    SELECT 'SEM_GATES_PRIMARIO', fixture_id, ANY_VALUE(competition),
           MAX(min_jogos), COUNT(*)
    FROM apostas WHERE competition NOT IN ('copa_mundo', 'nations_league', 'amistosos')
    GROUP BY fixture_id
    UNION ALL
    SELECT 'COM_GATES_PRIMARIO', fixture_id, ANY_VALUE(competition), MAX(min_jogos), COUNT(*)
    FROM apostas
    WHERE passa_gates_board AND competition NOT IN ('copa_mundo', 'nations_league', 'amistosos')
    GROUP BY fixture_id
),
jogos_classificados AS (
    SELECT
        jl.leitura, jl.fixture_id, jl.competition, jl.min_jogos, jl.n_apostas,
        f.competition_id, f.familia
    FROM jogos_leitura AS jl
    LEFT JOIN familia_competicao AS f USING (competition)
),
-- referencia: jogos agendados/encerrados na janela, sem exigir preco (para o denominador)
agenda AS (
    SELECT
        competition,
        COUNT(*)                                        AS agendados_na_janela,
        COUNTIF(status_short = 'FT')                    AS encerrados_FT,
        COUNTIF(status_short IN ('PST','CANC','ABD','SUSP','AWD','WO')) AS adiados_cancelados
    FROM `smartbetting-dados.futebol.fact_fixtures`
    WHERE kickoff_utc >= janela_ini AND kickoff_utc < janela_fim
    GROUP BY competition
),
resumo AS (
    SELECT
        leitura,
        COUNT(*)                                                                AS piso1_encerrados_precificados,
        COUNTIF(min_jogos >= 5)                                                 AS piso2_acima_do_piso5,
        COUNTIF(min_jogos >= 5 AND familia = 'split_year')                      AS piso2b_piso5_e_split_year,
        COUNTIF(familia = 'split_year')                                         AS piso3_split_year,
        COUNTIF(competition = 'copa_mundo')                                     AS piso4_copa_do_mundo,
        COUNTIF(familia IS NULL)                                                AS diag_sem_familia,
        COUNTIF(competition = 'unknown')                                        AS diag_competicao_unknown,
        SUM(n_apostas)                                                          AS diag_linhas_de_aposta
    FROM jogos_classificados
    GROUP BY leitura
)

-- ================================================================= SAIDA 1: resumo por piso e leitura
SELECT
    '1_resumo' AS secao,
    leitura,
    CAST(NULL AS INT64)   AS league_id,
    CAST(NULL AS STRING)  AS competicao,
    CAST(NULL AS STRING)  AS familia,
    piso1_encerrados_precificados AS p1_encerrados_precificados,
    piso2_acima_do_piso5          AS p2_acima_piso5,
    piso3_split_year              AS p3_split_year,
    piso4_copa_do_mundo           AS p4_copa_do_mundo,
    piso2b_piso5_e_split_year     AS x_piso5_e_split_year,
    diag_sem_familia              AS x_sem_familia,
    diag_competicao_unknown       AS x_unknown,
    diag_linhas_de_aposta         AS x_linhas_de_aposta,
    CAST(NULL AS INT64)   AS x_agendados,
    CAST(NULL AS INT64)   AS x_encerrados_FT
FROM resumo

UNION ALL

-- ================================================================= SAIDA 2: por competicao e leitura
SELECT
    '2_por_competicao',
    c.leitura,
    ANY_VALUE(c.competition_id),
    c.competition,
    ANY_VALUE(c.familia),
    COUNT(*),
    COUNTIF(c.min_jogos >= 5),
    COUNTIF(c.familia = 'split_year'),
    COUNTIF(c.competition = 'copa_mundo'),
    COUNTIF(c.min_jogos >= 5 AND c.familia = 'split_year'),
    COUNTIF(c.familia IS NULL),
    COUNTIF(c.competition = 'unknown'),
    SUM(c.n_apostas),
    ANY_VALUE(a.agendados_na_janela),
    ANY_VALUE(a.encerrados_FT)
FROM jogos_classificados AS c
LEFT JOIN agenda AS a USING (competition)
GROUP BY c.leitura, c.competition

UNION ALL

-- ================================================================= SAIDA 3: referencia sem preco (agenda por competicao)
SELECT
    '3_agenda_sem_exigir_preco',
    'REFERENCIA',
    f.competition_id,
    a.competition,
    f.familia,
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
    a.agendados_na_janela,
    a.encerrados_FT
FROM agenda AS a
LEFT JOIN familia_competicao AS f USING (competition)

ORDER BY secao, leitura, p1_encerrados_precificados DESC NULLS LAST, competicao
