

WITH jogos_encerrados AS (
    SELECT fixture_id, competition, competition_id, season, round, home_team_id, away_team_id,
           kickoff_utc, goals_home, goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      AND DATE(kickoff_utc) <= DATE('2026-09-10')
),

-- AE#162 — total de rodadas da fase de pontos corridos de cada (competition_id, season).
-- Informação de CALENDÁRIO (o chaveamento inteiro já existe em fact_fixtures antes da
-- temporada acabar — conferido: temporada em andamento tem o MESMO MAX(round) das já
-- encerradas), não medição — usar não é look-ahead, mesmo raciocínio do group_name em
-- int_futebol_team_form_pit.
total_rodadas AS (
    SELECT competition_id, season,
           MAX(CAST(REGEXP_EXTRACT(round, r'(\d+)$') AS INT64)) AS total_rodadas
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE round LIKE 'Regular Season%'
    GROUP BY 1, 2
),

-- AE#162 — zona de tabela do VISITANTE e reta final, na leitura de standings mais recente
-- ANTES do apito (nunca a mais recente disponível hoje — ver
-- reference_dbt_snapshot_idade_artefato). O histórico de standings só começa em 11/06/2026:
-- jogo mais antigo que isso não tem snapshot anterior e as duas colunas saem NULL
-- (degradação graciosa, documentada no pré-registro). `s.played_total` é a campanha do
-- visitante ATÉ aquele snapshot — mesma fonte que dá o rank/zona, sem join extra.
zona_visitante AS (
    SELECT
        j.fixture_id,
        (CASE
        WHEN s.rank_description IS NULL THEN NULL
        WHEN s.rank_description LIKE '%Relegation%' THEN 'rebaixamento'
        WHEN s.rank_description LIKE '%Champions League%'
          OR s.rank_description LIKE '%Europa League%'
          OR s.rank_description LIKE '%Conference League%'
          OR s.rank_description LIKE '%Libertadores%'
          OR s.rank_description LIKE '%Sudamericana%'
          OR s.rank_description LIKE '%UEFA%'
          OR s.rank_description LIKE '%ECL%'
        THEN 'vaga_continental'
        WHEN s.rank_description LIKE '%Promotion%' THEN 'promocao'
        ELSE 'classificacao'
    END IS NOT NULL)      AS zona_em_disputa,
        SAFE_DIVIDE(s.played_total, tr.total_rodadas) >= 0.80            AS reta_final
    FROM jogos_encerrados j
    JOIN `smartbetting-dados`.`futebol`.`fact_standings_snapshot` s
      ON  s.league_id       = j.competition_id
      AND s.season          = j.season
      AND s.team_id         = j.away_team_id
      AND s.snapshot_date   < DATE(j.kickoff_utc)
    LEFT JOIN total_rodadas tr
      ON  tr.competition_id = j.competition_id
      AND tr.season         = j.season
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY j.fixture_id ORDER BY s.snapshot_date DESC
    ) = 1
),

odds_56 AS (
    SELECT *
    FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    WHERE market_id = 56
      AND janela_usada = 't24h'
),

-- Resultado REAL do jogo (não PIT): o escanteio final de cada lado, p/ liquidar. 1 linha por
-- fixture com os dois lados pivotados — mesmo padrão de PARES_ESCANTEIO do script ad-hoc.
resultado_escanteios AS (
    SELECT
        fixture_id,
        MAX(IF(team_side = 'home', corner_kicks, NULL)) AS corners_home,
        MAX(IF(team_side = 'away', corner_kicks, NULL)) AS corners_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_stats`
    GROUP BY fixture_id
),

pit_home AS (SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_team_corner_form_pit`),
pit_away AS (SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_team_corner_form_pit`),

apostas AS (
    SELECT
        o.fixture_id,
        o.outcome_side,
        o.line_value,
        o.best_odd,
        o.n_casas,
        o.prob_justa_fechamento,
        IF(o.valor_fonte = 'pinnacle', 'pinnacle', 'consenso') AS benchmark,
        j.competition,
        j.season,
        j.kickoff_utc,
        LEAST(COALESCE(ph.played_total_disponivel, 0), COALESCE(pa.played_total_disponivel, 0)) AS min_jogos,

        -- AE#162 — insumo da premissa "Decisão" (lado de baixo, Away). mata_mata é
        -- propriedade do JOGO (não depende de lado); reta_final/zona_em_disputa são do
        -- VISITANTE especificamente (ver pré-registro da issue #162).
        (j.round NOT LIKE 'Regular Season%'
         AND j.round NOT LIKE 'Group Stage%'
         AND j.round NOT LIKE 'League Stage%')                                         AS mata_mata,
        COALESCE(zv.reta_final, FALSE)                                                 AS reta_final_visitante,
        COALESCE(zv.zona_em_disputa, FALSE)                                            AS zona_em_disputa_visitante,

        -- Liquidação: PAR COMPLEMENTAR, line_value na ótica do MANDANTE (AE#158) — mesma
        -- fórmula algébrica de task01_liquidacao() p/ o market_id 4, com corner_kicks no
        -- lugar de goals.
        IF(o.outcome_side = 'Home',
           r.corners_home + o.line_value > r.corners_away,
           r.corners_away - o.line_value > r.corners_home)                            AS ganhou,

        -- Insumos PIT (AE#159), expostos p/ o catálogo de premissas montar em cima.
        ph.possession_avg10        AS h_posse,
        pa.possession_avg10        AS a_posse,
        ph.xg_avg10                AS h_xg,
        pa.xg_avg10                AS a_xg,
        ph.corners_for_avg10       AS h_corner_for,
        pa.corners_for_avg10       AS a_corner_for,
        ph.corners_against_avg10   AS h_corner_against,
        pa.corners_against_avg10   AS a_corner_against,
        ph.shots_insidebox_avg10   AS h_area,
        pa.shots_insidebox_avg10   AS a_area,
        ph.corners_for_avg_mando5  AS h_mando5,
        pa.corners_for_avg_mando5  AS a_mando5,
        -- Escanteio previsto do jogo, fórmula do ClickUp wdx6zf1tt8:
        -- (a_favor_mandante + sofridos_visitante + a_favor_visitante + sofridos_mandante) / 2
        SAFE_DIVIDE(ph.corners_for_avg10 + pa.corners_against_avg10
                  + pa.corners_for_avg10 + ph.corners_against_avg10, 2)                AS escanteio_previsto

    FROM odds_56 o
    JOIN jogos_encerrados j
      ON j.fixture_id = o.fixture_id
    JOIN resultado_escanteios r
      ON r.fixture_id = o.fixture_id
    LEFT JOIN pit_home ph
      ON ph.fixture_id = o.fixture_id AND ph.team_id = j.home_team_id
    LEFT JOIN pit_away pa
      ON pa.fixture_id = o.fixture_id AND pa.team_id = j.away_team_id
    LEFT JOIN zona_visitante zv
      ON zv.fixture_id = o.fixture_id
    WHERE o.best_odd                IS NOT NULL
      AND o.prob_justa_fechamento   IS NOT NULL   -- só linhas que o de-vig realmente emitiu (AE#158)
      AND r.corners_home IS NOT NULL AND r.corners_away IS NOT NULL  -- resultado real existe p/ liquidar
      AND (MOD(CAST(ROUND(ABS(o.line_value) * 4) AS INT64), 4) = 2)                 -- só meia linha (AE#101/#113)
      AND COALESCE(o.n_casas >= 3, FALSE)
)

,

apostas_unica AS (
    SELECT *
    FROM apostas
    WHERE min_jogos >= 10
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id, outcome_side
        ORDER BY n_casas DESC, ABS(line_value) ASC, line_value ASC
    ) = 1
),

premissas_linha AS (
    
    SELECT
        fixture_id, outcome_side, line_value,
        'domina_posse'      AS premissa,
        (COALESCE((h_posse - a_posse) >= 5.8, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'cria_mais_chance'      AS premissa,
        (COALESCE((h_xg - a_xg) >= 0.34, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_mais_escanteio'      AS premissa,
        (COALESCE((h_corner_for - a_corner_for) >= 1.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'ataca_mais_area'      AS premissa,
        (COALESCE((h_area - a_area) >= 1.6, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_escanteio_mando'      AS premissa,
        (COALESCE(h_mando5 >= 6.4, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'jogo_muito_escanteio'      AS premissa,
        (COALESCE(escanteio_previsto >= 10.3, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'jogo_pouco_escanteio'      AS premissa,
        (COALESCE(escanteio_previsto <= 9.05, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Away'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_mais_escanteio'      AS premissa,
        (COALESCE((a_corner_for - h_corner_for) >= 1.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Away'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_escanteio_mando'      AS premissa,
        (COALESCE(a_mando5 >= 5.2, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Away'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'decisao'      AS premissa,
        (COALESCE((mata_mata OR (reta_final_visitante AND zona_em_disputa_visitante)), FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas
    WHERE outcome_side = 'Away'

),

premissas_jogo AS (
    
    SELECT
        fixture_id, outcome_side, line_value,
        'domina_posse'      AS premissa,
        (COALESCE((h_posse - a_posse) >= 5.8, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'cria_mais_chance'      AS premissa,
        (COALESCE((h_xg - a_xg) >= 0.34, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_mais_escanteio'      AS premissa,
        (COALESCE((h_corner_for - a_corner_for) >= 1.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'ataca_mais_area'      AS premissa,
        (COALESCE((h_area - a_area) >= 1.6, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_escanteio_mando'      AS premissa,
        (COALESCE(h_mando5 >= 6.4, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'jogo_muito_escanteio'      AS premissa,
        (COALESCE(escanteio_previsto >= 10.3, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Home'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'jogo_pouco_escanteio'      AS premissa,
        (COALESCE(escanteio_previsto <= 9.05, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Away'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_mais_escanteio'      AS premissa,
        (COALESCE((a_corner_for - h_corner_for) >= 1.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Away'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'forca_escanteio_mando'      AS premissa,
        (COALESCE(a_mando5 >= 5.2, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Away'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value,
        'decisao'      AS premissa,
        (COALESCE((mata_mata OR (reta_final_visitante AND zona_em_disputa_visitante)), FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_unica
    WHERE outcome_side = 'Away'

),

agregado_linha AS (
    SELECT
        'linha' AS base,
        pl.outcome_side AS lado,
        pl.premissa,
        COUNTIF(pl.acesa) AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL)) AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL)) AS p_real
    FROM premissas_linha pl
    JOIN apostas a
      ON  a.fixture_id   = pl.fixture_id
      AND a.outcome_side = pl.outcome_side
      AND COALESCE(a.line_value, -999) = COALESCE(pl.line_value, -999)
    WHERE a.benchmark = 'pinnacle'
    GROUP BY pl.outcome_side, pl.premissa
    HAVING COUNTIF(pl.acesa) > 0
),

agregado_jogo AS (
    SELECT
        'jogo_lado' AS base,
        pl.outcome_side AS lado,
        pl.premissa,
        COUNTIF(pl.acesa) AS n,
        AVG(IF(pl.acesa, a.prob_justa_fechamento, NULL)) AS p_odd,
        AVG(IF(pl.acesa, CAST(a.ganhou AS INT64), NULL)) AS p_real
    FROM premissas_jogo pl
    JOIN apostas_unica a
      ON  a.fixture_id   = pl.fixture_id
      AND a.outcome_side = pl.outcome_side
      AND COALESCE(a.line_value, -999) = COALESCE(pl.line_value, -999)
    WHERE a.benchmark = 'pinnacle'
    GROUP BY pl.outcome_side, pl.premissa
    HAVING COUNTIF(pl.acesa) > 0
),

universo_lado AS (
    SELECT 'linha' AS base, outcome_side AS lado, COUNT(*) AS total
    FROM apostas WHERE min_jogos >= 10
    GROUP BY 1, 2

    UNION ALL

    SELECT 'jogo_lado' AS base, outcome_side AS lado, COUNT(*) AS total
    FROM apostas_unica
    GROUP BY 1, 2
),

taxa_acender AS (
    SELECT 'linha' AS base, outcome_side AS lado, premissa, COUNTIF(acesa) AS n_acesas
    FROM premissas_linha GROUP BY 1, 2, 3

    UNION ALL

    SELECT 'jogo_lado' AS base, outcome_side AS lado, premissa, COUNTIF(acesa) AS n_acesas
    FROM premissas_jogo GROUP BY 1, 2, 3
),

cobertura_pinnacle AS (
    SELECT 'linha' AS base, COUNT(*) AS total, COUNTIF(benchmark = 'pinnacle') AS com_pinnacle
    FROM apostas WHERE min_jogos >= 10

    UNION ALL

    SELECT 'jogo_lado' AS base, COUNT(*) AS total, COUNTIF(benchmark = 'pinnacle') AS com_pinnacle
    FROM apostas_unica
)

SELECT
    'ganho' AS bloco, base, lado, premissa,
    n AS n_ou_total,
    ROUND((p_real - p_odd) * 100, 2) AS valor,
    CAST(NULL AS INT64) AS extra
FROM (
    SELECT * FROM agregado_linha
    UNION ALL
    SELECT * FROM agregado_jogo
)

UNION ALL

SELECT
    'taxa' AS bloco, t.base, t.lado, t.premissa,
    t.n_acesas AS n_ou_total,
    ROUND(100.0 * SAFE_DIVIDE(t.n_acesas, u.total), 1) AS valor,
    u.total AS extra
FROM taxa_acender t
JOIN universo_lado u USING (base, lado)

UNION ALL

SELECT
    'cobertura' AS bloco, base, CAST(NULL AS STRING) AS lado, CAST(NULL AS STRING) AS premissa,
    total AS n_ou_total,
    ROUND(100.0 * SAFE_DIVIDE(com_pinnacle, total), 1) AS valor,
    com_pinnacle AS extra
FROM cobertura_pinnacle

ORDER BY bloco, base, lado, valor DESC