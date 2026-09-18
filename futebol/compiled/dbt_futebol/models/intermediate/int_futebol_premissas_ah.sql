

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- Universo de linhas: canônicas (toda fixture, p/ validar mesmo sem odds na pausa FIFA) +
-- linhas reais das odds (market_id=4). Canônicas cobrem favorito (-) e azarão (+) dos dois lados.
canonical_lines AS (
    SELECT f.fixture_id, l AS line_value
    FROM fixtures f, UNNEST([-1.5, -0.5, 0.5, 1.5]) AS l
),
market_lines AS (
    SELECT DISTINCT fixture_id, line_value
    FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
    WHERE market_id = 4 AND line_value IS NOT NULL
),
lines AS (
    SELECT fixture_id, line_value FROM canonical_lines
    UNION DISTINCT
    SELECT fixture_id, line_value FROM market_lines
),

-- 2 outcomes (Home/Away) por (fixture, linha). Resolve S (lado apostado), O (adversário),
-- mando e o handicap na ótica do lado (sinal define favorito/azarão).
outcomes AS (
    SELECT
        l.fixture_id, f.competition, f.competition_id, f.season, f.kickoff_utc,
        l.line_value,
        side AS outcome,
        (side = 'Home')                                       AS s_is_home,
        IF(side = 'Home', f.home_team_id, f.away_team_id)     AS s_team_id,
        IF(side = 'Home', f.away_team_id, f.home_team_id)     AS o_team_id,
        IF(side = 'Home', l.line_value, -l.line_value)        AS side_handicap
    FROM lines l
    JOIN fixtures f USING (fixture_id)
    CROSS JOIN UNNEST(['Home', 'Away']) AS side
),

-- Correção da Task 0 (look-ahead): forma E tabela POINT-IN-TIME por (fixture, time), só com
-- jogos anteriores ao kickoff. Substitui fact_team_season_stats (temporada fechada em 24/25) e
-- o standings_latest (tabela final). n_teams vem junto, por (liga, season).
pit AS (
    SELECT
        fixture_id, team_id,
        goals_for_avg_home, goals_for_avg_away,
        goals_against_avg_home, goals_against_avg_away,
        wins_home, draws_home, played_home,
        rank, ppg, n_teams
    FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`
),

-- Margem (gols pró − contra) por time em cada jogo FINALIZADO; vira a base de
-- "perde/vence por 2+". Reusa o padrão de fixtures finalizadas do O/U.
finished AS (
    SELECT competition_id, kickoff_utc, home_team_id, away_team_id,
           score_fulltime_home, score_fulltime_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE 
    status_short IN ('FT', 'AET', 'PEN')
      AND score_fulltime_home IS NOT NULL
      AND score_fulltime_away IS NOT NULL
),
team_results AS (
    SELECT home_team_id AS team_id, competition_id, kickoff_utc,
           score_fulltime_home - score_fulltime_away AS margin FROM finished
    UNION ALL
    SELECT away_team_id, competition_id, kickoff_utc,
           score_fulltime_away - score_fulltime_home FROM finished
),
fixture_teams AS (
    SELECT fixture_id, competition_id, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, kickoff_utc, away_team_id FROM fixtures
),
-- Por (fixture-alvo, time): nº de jogos anteriores na mesma liga e % derrotas/vitórias por 2+.
-- MEDIÇÃO — recorte de contagem: os pares (jogo-alvo, time) × partida anterior são ranqueados e
-- só os N mais recentes sobrevivem, ANTES da agregação. O corte mora num CTE à parte porque
-- QUALIFY na mesma SELECT do GROUP BY filtraria depois de a conta estar feita. O desempate é
-- pela própria margem: `kickoff_utc` é TIMESTAMP e empate real seria dado torto, mas com ele o
-- conjunto sobrevivente é determinístico mesmo assim.
margin_pares AS (
    SELECT ft.fixture_id, ft.team_id, r.margin
    FROM fixture_teams ft
    JOIN team_results r
        ON r.team_id        = ft.team_id
       AND r.kickoff_utc    < ft.kickoff_utc
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ft.fixture_id, ft.team_id
        ORDER BY r.kickoff_utc DESC, r.margin DESC
    ) <= 10
),
margin_stats AS (
    SELECT
        fixture_id, team_id,
        COUNT(*)             AS n_games,
        COUNTIF(margin <= -2) AS n_lost2,
        COUNTIF(margin >=  2) AS n_won2
    FROM margin_pares
    GROUP BY fixture_id, team_id
),

-- A odd da linha 0 (B3, #109/decisão do Victor 25/08): quem tem a MENOR odd é o
-- favorito; empate (ou odd ausente) desempata pelo mando. `QUALIFY` já reduz a 1 linha
-- por fixture — no máximo Home e Away entram aqui (market_id=4, line_value=0), a janela
-- corrente resolve as duas juntas (mesma janela pros dois lados, ver
-- `futebol_devig_janela_corrente()`), e a ORDER BY escolhe a de menor odd, com o mando
-- como critério de desempate.
odds_linha_zero AS (
    SELECT
        fixture_id,
        outcome_side = 'Home' AS home_e_favorito_por_odd
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
    WHERE market_id = 4 AND line_value = 0
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id
        ORDER BY best_odd ASC, IF(outcome_side = 'Home', 0, 1) ASC
    ) = 1
),

-- Métricas brutas por outcome×linha.
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome, o.line_value,
        o.s_is_home, o.side_handicap,
        -- ⚠️ B3 (#109, 2026-09-01): linha 0 (side_handicap=0) não fica mais sem lado. A ODD
        -- decide quem é favorito (decisão do Victor, 25/08) — MESMA regra que
        -- `macros/futebol_lado.sql` usa, e os dois têm de concordar (é o que casa esta
        -- linha com o p95 do lado no funil). Sem odd pra essa linha, cai no mando —
        -- degradação graciosa, nunca NULL. Antes desta entrega as duas eram FALSE em
        -- handicap zero: nenhuma premissa disparava, a linha nunca tinha nota.
        (o.side_handicap < 0
            OR (o.side_handicap = 0 AND COALESCE(olz.home_e_favorito_por_odd, o.s_is_home)))     AS is_favorito,
        (o.side_handicap > 0
            OR (o.side_handicap = 0 AND NOT COALESCE(olz.home_e_favorito_por_odd, o.s_is_home))) AS is_azarao,

        -- ataque/defesa de S no campo deste jogo (tende_golear, defesa_fora_solida)
        IF(o.s_is_home, s.goals_for_avg_home,     s.goals_for_avg_away)     AS s_gf_venue,
        IF(o.s_is_home, s.goals_against_avg_home, s.goals_against_avg_away)  AS s_ga_venue,
        -- defesa de O no campo de O neste jogo (adversario_fragil_fora)
        IF(o.s_is_home, od.goals_against_avg_away, od.goals_against_avg_home) AS o_ga_venue,

        -- aproveitamento de S como mandante (mando_forte)
        (s.wins_home * 3 + s.draws_home) / NULLIF(s.played_home * 3, 0) * 100 AS pct_pts_home,

        -- tabela do campeonato NO INSTANTE DO JOGO (supremacia)
        s.rank    AS s_rank,
        od.rank   AS o_rank,
        s.ppg     AS s_ppg,
        od.ppg    AS o_ppg,
        s.n_teams AS n_teams,

        -- margens (raramente_perde_por_2 = S; favorito_irregular = O)
        sm.n_games AS s_n_games, sm.n_lost2 AS s_lost2,
        om.n_games AS o_n_games, om.n_won2  AS o_won2
    FROM outcomes o
    LEFT JOIN pit s   ON s.fixture_id  = o.fixture_id AND s.team_id  = o.s_team_id
    LEFT JOIN pit od  ON od.fixture_id = o.fixture_id AND od.team_id = o.o_team_id
    LEFT JOIN margin_stats sm ON sm.fixture_id = o.fixture_id AND sm.team_id = o.s_team_id
    LEFT JOIN margin_stats om ON om.fixture_id = o.fixture_id AND om.team_id = o.o_team_id
    LEFT JOIN odds_linha_zero olz ON olz.fixture_id = o.fixture_id
),

-- Premissas (booleanos). Gated por favorito/azarão -> só o lado certo dispara; soma <=40 (fav) ou <=30 (dog).
flags AS (
    SELECT
        m.*,
        -- Favorito (Σ40)
        m.is_favorito AND (COALESCE(m.o_rank - m.s_rank >= 8, FALSE)
                           OR COALESCE(m.s_ppg >= 1.5 * m.o_ppg, FALSE))       AS supremacia,
        m.is_favorito AND COALESCE(m.s_gf_venue >= 2.0 AND m.s_ga_venue <= 1.0, FALSE) AS tende_golear,
        m.is_favorito AND COALESCE(m.o_ga_venue >= 1.6, FALSE)                  AS adversario_fragil_fora,
        m.is_favorito AND m.s_is_home AND COALESCE(m.pct_pts_home >= 60, FALSE) AS mando_forte,
        -- sem_rodizio = proxy COARSE de motivação (jogo importante, sem rodízio): só ligas de
        -- pontos corridos (Brasileirão, Série B, La Liga, Premier League e Serie A ITA — 20 times, mesma dinâmica
        -- G6/Z3 de Europa/rebaixamento, então rank<=6 / rank>=n-3 vale sem mudança; revisar na recalibração por
        -- liga) e S em zona de disputa (G6 ou Z4). Copa -> FALSE (rank é por grupo, proxy não vale).
        -- Bundesliga, Ligue 1 e Primeira Liga -> TRUE, e são as três de 18 times (as outras 5 têm
        -- 20). A Primeira Liga é o caso mais LIMPO das três: o playoff dela tem 2 jogos nas duas
        -- temporadas medidas (a da Ligue 1 varia, 2 em 24/25 e 4 em 25/26). Entram
        -- porque n_teams vem do standings por (liga, season), então `rank >= n_teams - 3` se ajusta
        -- sozinho (15-18) sem constante nova. RESSALVA IDÊNTICA NAS DUAS: ambas têm 3 vagas em risco
        -- (2 quedas diretas + 1 playoff contra a 2ª divisão — 2. Bundesliga e Ligue 2), então a faixa
        -- de 4 posições sobre-inclui o 15º e o proxy fica levemente mais frouxo que nas ligas de 20
        -- (22% do grid vs 20%). Aceitável no nível de grosseria que este proxy já assume; refinar
        -- pertence à recalibração por liga. Na Ligue 1 o playoff é um BRACKET de tamanho variável
        -- (2 jogos em 24/25, 4 em 25/26) e chega a incluir jogo Ligue 2 x Ligue 2 — esses times não
        -- têm linha de standings, então s_rank/n_teams vêm NULL e o COALESCE já os derruba.
        -- Copa do Brasil -> FALSE também (mata-mata sem standings: s_rank/n_teams vêm NULL do
        -- LEFT JOIN e o COALESCE já derruba; fica fora do IN por decisão, não por acidente).
        -- Libertadores/Sudamericana -> FALSE também, mas por outro motivo: elas TÊM standings
        -- (fase de grupos) e o rank é POR GRUPO (1-4), com n_teams contando a season inteira
        -- (~32-54) — se entrassem no IN, `s_rank <= 6` seria TRUE p/ TODOS os times (+4 de
        -- ruído em todo favorito) e no mata-mata a tabela congela nos grupos. Fora do IN por
        -- decisão, não por acidente.
        -- Champions League -> FALSE pelo mesmo motivo: fase de liga (36 times, 8 jogos) vira
        -- mata-mata em fevereiro e a tabela congela; G6/Z3 não modela a dinâmica top-8/9-24.
        -- TODO: refinar com rodada/congestionamento de calendário.
        -- A lista sai de futebol_ligas_pontos_corridos(): ela é lida também pela chave de
        -- aplicabilidade desta premissa no mapa de insumos, e duas cópias divergem em silêncio.
        m.is_favorito AND m.competition IN ('brasileirao', 'serie_b', 'la_liga', 'premier_league', 'serie_a_ita', 'bundesliga', 'ligue_1', 'primeira_liga')
            AND COALESCE(m.s_rank <= 6 OR m.s_rank >= m.n_teams - 3, FALSE)     AS sem_rodizio,
        -- Azarão (Σ30)
        m.is_azarao AND COALESCE(m.s_n_games >= 5 AND m.s_lost2 / m.s_n_games < 0.30, FALSE) AS raramente_perde_por_2,
        m.is_azarao AND COALESCE(m.s_ga_venue <= 1.1, FALSE)                    AS defesa_fora_solida,
        m.is_azarao AND COALESCE(m.o_n_games >= 5 AND m.o_won2 / m.o_n_games < 0.35, FALSE)  AS favorito_irregular,
        -- penalidade específica (independe do lado): handicap alto raramente confiável
        (ABS(m.line_value) >= 2.5)                                             AS handicap_alto
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        (
            12 * CAST(f.supremacia             AS INT64)
          + 10 * CAST(f.tende_golear           AS INT64)
          +  8 * CAST(f.adversario_fragil_fora AS INT64)
          +  6 * CAST(f.mando_forte            AS INT64)
          +  4 * CAST(f.sem_rodizio            AS INT64)
          + 12 * CAST(f.raramente_perde_por_2  AS INT64)
          + 10 * CAST(f.defesa_fora_solida     AS INT64)
          +  8 * CAST(f.favorito_irregular     AS INT64)
        ) AS pts_premissas,
        12 * CAST(f.handicap_alto AS INT64) AS penalidades_ah_pts
    FROM flags f
),

-- Cegueira (#41, ADR 0003): premissas que se aplicavam a esta linha, não acenderam, e não
-- acenderam por FALTA DE INSUMO. Gerada do mapa futebol_insumos_premissa(), nunca escrita à
-- mão. Aqui a aplicabilidade é o LADO — sem ela toda linha de Handicap contaria as 3 do azarão
-- ou as 5 do favorito, sempre e por desenho, e um contador que diz o mesmo número em toda
-- linha é ignorado exatamente como guarda que nasce vermelha.
cegueira AS (
    SELECT
        s.*,
        ARRAY(SELECT premissa FROM UNNEST([
        IF(COALESCE((is_favorito)
           AND NOT COALESCE(supremacia, FALSE)
           AND (s_rank IS NULL OR o_rank IS NULL OR s_ppg IS NULL OR o_ppg IS NULL), FALSE), 'supremacia', NULL),
        IF(COALESCE((is_favorito)
           AND NOT COALESCE(tende_golear, FALSE)
           AND (s_gf_venue IS NULL OR s_ga_venue IS NULL), FALSE), 'tende_golear', NULL),
        IF(COALESCE((is_favorito)
           AND NOT COALESCE(adversario_fragil_fora, FALSE)
           AND (o_ga_venue IS NULL), FALSE), 'adversario_fragil_fora', NULL),
        IF(COALESCE((is_favorito AND s_is_home)
           AND NOT COALESCE(mando_forte, FALSE)
           AND (pct_pts_home IS NULL), FALSE), 'mando_forte', NULL),
        IF(COALESCE((is_favorito AND competition IN ('brasileirao', 'serie_b', 'la_liga', 'premier_league', 'serie_a_ita', 'bundesliga', 'ligue_1', 'primeira_liga'))
           AND NOT COALESCE(sem_rodizio, FALSE)
           AND (s_rank IS NULL OR n_teams IS NULL), FALSE), 'sem_rodizio', NULL),
        IF(COALESCE((is_azarao)
           AND NOT COALESCE(raramente_perde_por_2, FALSE)
           AND (s_n_games IS NULL OR s_lost2 IS NULL), FALSE), 'raramente_perde_por_2', NULL),
        IF(COALESCE((is_azarao)
           AND NOT COALESCE(defesa_fora_solida, FALSE)
           AND (s_ga_venue IS NULL), FALSE), 'defesa_fora_solida', NULL),
        IF(COALESCE((is_azarao)
           AND NOT COALESCE(favorito_irregular, FALSE)
           AND (o_n_games IS NULL OR o_won2 IS NULL), FALSE), 'favorito_irregular', NULL)
    ]) AS premissa WHERE premissa IS NOT NULL) AS premissas_cegas
    FROM scored s
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    line_value,
    side_handicap,
    is_favorito,
    is_azarao,
    -- flags (transparência/debug)
    supremacia,
    tende_golear,
    adversario_fragil_fora,
    mando_forte,
    sem_rodizio,
    raramente_perde_por_2,
    defesa_fora_solida,
    favorito_irregular,
    handicap_alto,
    -- agregados
    pts_premissas,
    penalidades_ah_pts,
    -- cegueira: a lista é o que torna o número auditável.
    premissas_cegas,
    ARRAY_LENGTH(premissas_cegas) AS premissas_sem_dado,

    -- "por quê": premissas que dispararam, em linguagem de gente, ordenadas por peso.
    ARRAY(SELECT e FROM UNNEST([
        IF(supremacia, 'claramente superior na tabela (rank/pontos)', NULL),
        IF(raramente_perde_por_2,
           FORMAT('raramente perde por 2+ (%d de %d jogos)', s_lost2, s_n_games), NULL),
        IF(tende_golear,
           FORMAT('tende a golear: marca %.1f e cede %.1f gol/jogo %s',
                  s_gf_venue, s_ga_venue, IF(s_is_home, 'em casa', 'fora')), NULL),
        IF(defesa_fora_solida,
           FORMAT('defesa sólida: cede só %.1f gol/jogo %s', s_ga_venue, IF(s_is_home, 'em casa', 'fora')), NULL),
        IF(adversario_fragil_fora,
           FORMAT('adversário frágil: cede %.1f gol/jogo %s', o_ga_venue, IF(s_is_home, 'fora', 'em casa')), NULL),
        IF(favorito_irregular,
           FORMAT('favorito irregular: vence por 2+ em só %d de %d jogos', o_won2, o_n_games), NULL),
        IF(mando_forte, FORMAT('%.0f%% de aproveitamento como mandante', pct_pts_home), NULL),
        IF(sem_rodizio, 'jogo importante na tabela (sem tendência a rodízio)', NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: penalidade específica do handicap.
    ARRAY(SELECT a FROM UNNEST([
        IF(handicap_alto,
           FORMAT('⚠ handicap alto (%.2f) — raramente confiável (−12)', line_value), NULL)
    ]) AS a WHERE a IS NOT NULL) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM cegueira