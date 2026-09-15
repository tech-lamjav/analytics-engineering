

WITH jogos_encerrados AS (
    SELECT fixture_id, competition, competition_id, season, round, home_team_id, away_team_id,
           kickoff_utc, goals_home, goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
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
    FROM (SELECT * EXCEPT (janela_prioridade, janela_e_corrente)
    FROM (SELECT
        d.* EXCEPT (_janela_prioridade, _line_key),
        d._janela_prioridade AS janela_prioridade,
        d._janela_prioridade = MAX(d._janela_prioridade) OVER (
            PARTITION BY d.fixture_id, d.market_id, d._line_key
        ) AS janela_e_corrente
    FROM (
        SELECT
            *,
            CASE janela_usada
        WHEN 't15m'  THEN 4   -- fechamento
        WHEN 't1h'   THEN 3
        WHEN 't24h'  THEN 2
        WHEN 'daily' THEN 1   -- varredura diária, até 7 dias do apito
        ELSE 0
    END AS _janela_prioridade,
            COALESCE(CAST(line_value AS STRING), 'NONE')    AS _line_key
        FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    ) d)
    WHERE janela_e_corrente)
    WHERE market_id = 56
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
      AND COALESCE(o.n_casas >= 4, FALSE)
      AND COALESCE(NOT o.pen_odd_outlier, FALSE)
      AND COALESCE(o.best_odd >= 1.5
               AND o.best_odd <= 4.0, FALSE)
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

metades AS (
    SELECT fixture_id, kickoff_utc, competition,
           NTILE(2) OVER (ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc, competition FROM apostas_unica)
)

SELECT
    metade,
    competition,
    COUNT(*) AS n_jogos,
    MIN(DATE(kickoff_utc)) AS de,
    MAX(DATE(kickoff_utc)) AS ate
FROM metades
GROUP BY metade, competition
ORDER BY metade, n_jogos DESC