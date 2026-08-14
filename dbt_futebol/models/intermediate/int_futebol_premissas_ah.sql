{{ config(
    materialized='table',
    description='S3 do Motor de Score — premissas de contexto do mercado HANDICAP ASIATICO (market_id 4). ⚠️ Task 0 (look-ahead): supremacia/tende_golear/adversario_fragil_fora/mando_forte/sem_rodizio/defesa_fora_solida leem int_futebol_team_form_pit (point-in-time por fixture) — o lado FAVORITO era 100% contaminado. raramente_perde_por_2 e favorito_irregular já eram limpos (margin_stats com kickoff_utc <) e não mudaram. 2 linhas por (fixture, line_value): outcome_side Home e Away. Convenção dos dados (API-Football, confirmada 2026-06-24): line_value é o handicap na ÓTICA DO MANDANTE e é o MESMO p/ os dois lados — "Home -1.5" e "Away -1.5" são o PAR complementar (de-vig soma ~1.03, pin_n_outcomes=2). Logo o handicap NA ÓTICA DO LADO = IF(side=Home, line_value, -line_value): side_handicap<0 => FAVORITO (dá handicap), >0 => AZARÃO (recebe), =0 => pick (nenhuma premissa dispara). Favorito: 5 premissas (Σ40, §12.3); Azarão: 3 (Σ30). Penalidade específica: handicap_alto (-12, |line_value|>=2.5). Degradação graciosa: dado ausente -> premissa FALSE. evidencias[]/avisos[] = bullets pro front. Gate/edge/Score saem no mart fact_value_opportunities (gate de completude Pinnacle = par >=2, igual O/U).
    ⚠️ Reconciliação §12.3: o bloco "Azarão" do playbook mistura rótulos S/O (ex.: "favorito_irregular | S venceu por 2+..."); aqui as premissas seguem o NOME/INTENÇÃO: raramente_perde_por_2 e defesa_fora_solida medem o AZARÃO (S); favorito_irregular mede o FAVORITO (O). Ao calibrar, alinhar o .md a esta leitura. ⚠️ MEDIÇÃO (task [F], ADR 0007): o margin_stats aceita as DUAS vars da medição — pit_escopo (da_competicao|todas) e pit_recorte (temporada|ultimos_10) —, cujos DEFAULTS reproduzem exatamente o comportamento descrito acima; no default o SQL compilado é idêntico ao de antes de as vars existirem. Produção nunca a passa; ela serve às células de medição, materializadas no dataset futebol_taskF. supremacia e sem_rodizio NÃO seguem o eixo (rank/ppg/n_teams vêm do team_form_pit, que os mantém competição-scoped em todas as células, ADR 0008). ⚠️ O margin_stats não tem filtro de season nem no default — ele já atravessa temporada hoje —, então sob `todas` ele passa a contar todas as competições E todo o tempo coletado. Contador de cegueira (#41, ADR 0003): premissas_cegas[] e premissas_sem_dado dizem quais premissas APLICÁVEIS a cada linha não puderam ser avaliadas por falta de insumo — geradas do mapa futebol_insumos_premissa(), nunca escritas à mão. O score NÃO muda: a premissa cega já não acendia e continua não acendendo; o que muda é o board passar a dizer o que não levou em conta. A aplicabilidade aqui é o LADO (is_favorito/is_azarao) — sem ela toda linha contaria 3 ou 5 cegas por desenho. A lista de ligas de pontos corridos do sem_rodizio saiu para futebol_ligas_pontos_corridos(), lida também pelo mapa.'
) }}
{#- EIXOS DE ESCOPO E RECORTE DA MEDIÇÃO DA TASK [F] (issue #49, ADR 0007) — produção nunca passa estas vars.

    Além do que vem do team_form_pit, este modelo tem UMA fonte de histórico competição-scoped
    própria: o `margin_stats`, que alimenta `raramente_perde_por_2` e `favorito_irregular`. Ela
    responde ao mesmo eixo, senão a célula sai MISTURADA — `tende_golear` com histórico juntado e
    `raramente_perde_por_2` sem —, e um número assim não responde a pergunta da spec. Vale notar
    que a spec #49 e o ticket #52 enumeram só o `last5` de Gols, o de BTTS e o spine de xG; a
    regra que eles declaram, porém, é "todas as fontes de histórico competição-scoped", e o
    critério de saída da spec (user story 26) fixa em QUATRO as premissas que ficam fora do
    merge — as quatro de tabela da ADR 0008. Deixar esta fonte de fora faria seis.

    ⚠️ Este `margin_stats` NÃO tem filtro de season hoje: já atravessa temporada. O eixo mexe só
    na dimensão competição, então sob `todas` ele vira histórico de todas as competições e de
    todo o tempo coletado. É correto — e é achado para a tabela de 39 linhas, porque significa que
    estas duas premissas nunca sofreram o zeramento de virada de temporada que as outras sofrem.

    `supremacia` e `sem_rodizio` ficam de fora por desenho: leem rank/ppg/n_teams do
    team_form_pit, que os mantém competição-scoped em todas as células (ADR 0008).

    Valores aceitos, validação e o porquê do fail-closed em macros/taskf_eixos.sql. No default
    (`da_competicao`/`temporada`) o SQL compilado é IDÊNTICO ao de antes destas vars.

    O eixo de RECORTE (`pit_recorte`) alcança o mesmo `margin_stats` desde a #54, e ele é o único
    site em que o recorte ENCOLHE o histórico: sem filtro de season para remover, sob
    `ultimos_10` entra só o teto de contagem. Ver o comentário no CTE. -#}
{%- set eixos              = taskf_eixos() %}
{%- set pit_escopo         = eixos.escopo %}
{%- set pit_recorte        = eixos.recorte %}
{%- set tamanho_do_recorte = eixos.tamanho_do_recorte %}

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM {{ ref('fact_fixtures') }}
),

-- Universo de linhas: canônicas (toda fixture, p/ validar mesmo sem odds na pausa FIFA) +
-- linhas reais das odds (market_id=4). Canônicas cobrem favorito (-) e azarão (+) dos dois lados.
canonical_lines AS (
    SELECT f.fixture_id, l AS line_value
    FROM fixtures f, UNNEST([-1.5, -0.5, 0.5, 1.5]) AS l
),
market_lines AS (
    SELECT DISTINCT fixture_id, line_value
    FROM {{ ref('fact_odds_snapshot') }}
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
    FROM {{ ref('int_futebol_team_form_pit') }}
),

-- Margem (gols pró − contra) por time em cada jogo FINALIZADO; vira a base de
-- "perde/vence por 2+". Reusa o padrão de fixtures finalizadas do O/U.
finished AS (
    SELECT competition_id, kickoff_utc, home_team_id, away_team_id, goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),
team_results AS (
    SELECT home_team_id AS team_id, competition_id, kickoff_utc, goals_home - goals_away AS margin FROM finished
    UNION ALL
    SELECT away_team_id, competition_id, kickoff_utc, goals_away - goals_home FROM finished
),
fixture_teams AS (
    SELECT fixture_id, competition_id, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, kickoff_utc, away_team_id FROM fixtures
),
-- Por (fixture-alvo, time): nº de jogos anteriores na mesma liga e % derrotas/vitórias por 2+.
{#- O FROM/JOIN existe UMA vez e é renderizado nas duas formas do CTE (agregação direta no
    default, pares ranqueados sob recorte de contagem): é aqui que os dois eixos entram, e duas
    cópias de um predicado de eixo não ficam iguais para sempre. Mesma técnica do `agregados_pit`
    do int_futebol_team_form_pit.

    ⚠️ ESTE SITE É O ÚNICO EM QUE O RECORTE NÃO SUBSTITUI UM FILTRO DE SEASON — ele não tem um.
    O `margin_stats` já atravessa temporada hoje (ver o cabeçalho do modelo), então aqui
    `base` → `recorte` é TODO O TEMPO COLETADO → as N últimas partidas, e não temporada → as N
    últimas. Nas duas premissas que ele alimenta (`raramente_perde_por_2`, `favorito_irregular`) o
    recorte ENCOLHE o histórico em vez de alargá-lo, ao contrário de todos os outros sites. Quem
    ler a tabela de deltas comparando premissas precisa saber disso. -#}
{%- set margin_from %}
    FROM fixture_teams ft
    JOIN team_results r
        ON r.team_id        = ft.team_id
       {%- if pit_escopo == 'da_competicao' %}
       AND r.competition_id = ft.competition_id
       {%- endif %}
       AND r.kickoff_utc    < ft.kickoff_utc
{%- endset %}
{%- if pit_recorte == 'ultimos_10' %}
-- MEDIÇÃO — recorte de contagem: os pares (jogo-alvo, time) × partida anterior são ranqueados e
-- só os N mais recentes sobrevivem, ANTES da agregação. O corte mora num CTE à parte porque
-- QUALIFY na mesma SELECT do GROUP BY filtraria depois de a conta estar feita. O desempate é
-- pela própria margem: `kickoff_utc` é TIMESTAMP e empate real seria dado torto, mas com ele o
-- conjunto sobrevivente é determinístico mesmo assim.
margin_pares AS (
    SELECT ft.fixture_id, ft.team_id, r.margin
{{- margin_from }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ft.fixture_id, ft.team_id
        ORDER BY r.kickoff_utc DESC, r.margin DESC
    ) <= {{ tamanho_do_recorte }}
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
{%- else %}
margin_stats AS (
    SELECT
        ft.fixture_id, ft.team_id,
        COUNT(*)             AS n_games,
        COUNTIF(r.margin <= -2) AS n_lost2,
        COUNTIF(r.margin >=  2) AS n_won2
{{- margin_from }}
    GROUP BY ft.fixture_id, ft.team_id
),
{%- endif %}

-- Métricas brutas por outcome×linha.
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome, o.line_value,
        o.s_is_home, o.side_handicap,
        (o.side_handicap < 0) AS is_favorito,
        (o.side_handicap > 0) AS is_azarao,

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
        m.is_favorito AND m.competition IN {{ futebol_ligas_pontos_corridos_sql() }}
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
        {{ futebol_premissas_cegas('int_futebol_premissas_ah') }} AS premissas_cegas
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
