{{ config(
    materialized='table',
    description='S5 do Motor de Score — premissas de contexto do mercado DUPLA CHANCE (market_id 12). ⚠️ Task 0 (look-ahead): equilibrio_defensivo/adversario_limitado leem int_futebol_team_form_pit (point-in-time por fixture) no lugar de fact_team_season_stats; lado_coberto_forte herda a correção via int_futebol_premissas_1x2 (era a premissa MAIS contaminada, com as duas fontes sujas). invicto_recente já era limpa. 2 linhas por fixture: 1X (mandante ou empate, S=Home) e X2 (empate ou visitante, S=Away). DC é aposta de proteção: vale quando o mercado superprecifica a zebra do lado DESCOBERTO (O). 4 premissas (Σ34, sem clamp — bem abaixo de 55), espelha §12.5. lado_coberto_forte REUSA forca_mismatch/superioridade_tabela do int_futebol_premissas_1x2 (do lado S); adversario_limitado reusa o h2h_favoravel do 1X2. equilibrio_defensivo e invicto_recente derivam de fact_team_season_stats (gols sofridos no total) e dos jogos FINALIZADOS da MESMA season/competição anteriores ao jogo (goleados = cedeu 3+, e derrotas nos últimos 5) — o filtro de season evita sangrar a temporada passada pela pausa de off-season. O 12 (sem empate) NÃO é produzido (não casa com o padrão S/O da §12.5). Penalidade específica (odd_muito_baixa <1,20) e o gate próprio (melhor_odd >=1,25, sem odd_juice) são aplicados no mart fact_value_opportunities. Degradação graciosa: dado ausente -> premissa FALSE. evidencias[]/avisos[] = bullets pro front. ⚠️ MEDIÇÃO (task [F], ADR 0007): o team_hist aceita as DUAS vars da medição — pit_escopo (da_competicao|todas) e pit_recorte (temporada|ultimos_10, cujo teto de 10 alcança o thrash_rate e não o last5_lost). ⚠️ Desde a #91 (ADR 0010) os DEFAULTS são `todas` + `ultimos_10` — a célula `ambos` — e NÃO reproduzem mais o comportamento descrito acima; ele descreve o ramo `da_competicao`/`temporada`, hoje alcançável só passando as vars. Produção USA o default, que é a célula `ambos` da [F]; as vars seguem existindo para as OUTRAS células da medição, materializadas no dataset futebol_taskF. lado_coberto_forte e adversario_limitado seguem o que o 1X2 fizer: leem x_superioridade_tabela e x_h2h_favoravel de lá, já colapsados em booleano. Contador de cegueira (#41, ADR 0003): premissas_cegas[] e premissas_sem_dado dizem quais premissas APLICÁVEIS a cada linha não puderam ser avaliadas por falta de insumo — geradas do mapa futebol_insumos_premissa(), nunca escritas à mão. O score NÃO muda: a premissa cega já não acendia e continua não acendendo; o que muda é o board passar a dizer o que não levou em conta. Para isso, s_losses_last5 vira NULL sem histórico e os x_* deixaram de ser COALESCEados: quando a premissa correspondente está na lista premissas_cegas do 1X2, o reuso chega NULL — a cegueira deixa de atravessar dois modelos sem rastro.'
) }}
{#- EIXOS DE ESCOPO E RECORTE DA MEDIÇÃO DA TASK [F] (issue #49, ADR 0007) — desde a #91 o DEFAULT destas vars é o que produção usa.

    Além do que vem do team_form_pit, este modelo tem UMA fonte de histórico competição-scoped
    própria: o `team_hist`, que alimenta `equilibrio_defensivo` (thrash_rate) e `invicto_recente`
    (last5_lost). Ela responde ao mesmo eixo, senão a célula sai MISTURADA — o `s_ga_total` da
    mesma premissa `equilibrio_defensivo` vem do team_form_pit e viria juntado, e o `thrash_rate`
    ao lado dele não —, e um número assim não responde a pergunta da spec. Como no Handicap, esta
    fonte não está na enumeração da spec #49; está na regra que ela declara. Ver o cabeçalho do
    int_futebol_premissas_ah.sql.

    `lado_coberto_forte` e `adversario_limitado` seguem o que o 1X2 fizer: leem
    x_superioridade_tabela e x_h2h_favoravel de lá, já colapsados em booleano.

    Valores aceitos, validação e o porquê do fail-closed em macros/taskf_eixos.sql. ⚠️ Desde a #91 o default é `todas`/`ultimos_10` — o
    SQL compilado no default deixou de ser o de antes destas vars, por decisão.

    O eixo de RECORTE (`pit_recorte`) alcança a MESMA fonte desde a #54: sob `ultimos_10` o
    filtro de season sai e entra um teto de contagem, que atinge o `thrash_rate` (média sobre
    tudo o que está no recorte) e não atinge o `last5_lost` (janela de 5 dentro do recorte). -#}
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

-- 2 outcomes: 1X (S=Home, O=Away) e X2 (S=Away, O=Home). s_1x2_outcome casa o lado S no 1X2.
outcomes AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           '1X' AS outcome, home_team_id AS s_team_id, away_team_id AS o_team_id,
           'Home' AS s_1x2_outcome
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'X2', away_team_id, home_team_id, 'Away'
    FROM fixtures
),

-- Reuso das premissas do 1X2 (do lado S): forca_mismatch + superioridade_tabela (lado_coberto_forte)
-- e h2h_favoravel (adversario_limitado). Garante consistência com o ramo 1X2.
reuse_1x2 AS (
    SELECT fixture_id, outcome AS x1_outcome,
           forca_mismatch, superioridade_tabela, h2h_favoravel,
           -- a lista de premissas do 1X2 que não puderam ser avaliadas naquele jogo: é por ela
           -- que a cegueira de lá deixa de morrer no FALSE ao atravessar para cá (#41).
           premissas_cegas
    FROM {{ ref('int_futebol_premissas_1x2') }}
),

-- Correção da Task 0 (look-ahead): agregados POINT-IN-TIME por (fixture, time), só com jogos
-- anteriores ao kickoff, no lugar de fact_team_season_stats (1 snapshot por season).
pit AS (
    SELECT
        fixture_id, team_id,
        goals_against_avg_total,
        wins_total, draws_total, played_total
    FROM {{ ref('int_futebol_team_form_pit') }}
),

-- Jogos finalizados (mesma competição, MESMA season, anteriores) -> goleados (cedeu 3+) e
-- resultado por time. O filtro de season (aplicado no team_hist) evita sangrar jogos da
-- temporada passada pela pausa de off-season (consistente com tss/1X2/O/U/BTTS, season-scoped).
finished AS (
    SELECT competition_id, season, kickoff_utc, home_team_id, away_team_id,
           score_fulltime_home, score_fulltime_away
    FROM {{ ref('fact_fixtures') }}
    WHERE {{ futebol_jogo_encerrado() }}
),
team_results_long AS (
    SELECT home_team_id AS team_id, competition_id, season, kickoff_utc,
           score_fulltime_away AS conceded,
           (score_fulltime_away > score_fulltime_home) AS lost FROM finished
    UNION ALL
    SELECT away_team_id, competition_id, season, kickoff_utc,
           score_fulltime_home, (score_fulltime_home > score_fulltime_away) FROM finished
),
team_fixtures AS (
    SELECT fixture_id, competition_id, season, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, competition_id, season, kickoff_utc, away_team_id FROM fixtures
),
-- % de jogos cedendo 3+ (equilibrio_defensivo) e o array de derrotas dos últimos 5 (invicto_recente).
{#- O FROM/JOIN existe UMA vez e é renderizado nas duas formas do CTE (agregação direta no
    default, pares ranqueados sob recorte de contagem): é aqui que os dois eixos entram, e duas
    cópias de um predicado de eixo não ficam iguais para sempre. Mesma técnica do `agregados_pit`
    do int_futebol_team_form_pit.

    As duas colunas do CTE reagem ao teto de formas diferentes, e as duas estão certas: o
    `thrash_rate` é média sobre TUDO que está no recorte, então o teto muda o denominador dele; o
    `last5_lost` é uma janela de 5 dentro do recorte, e 5 é subconjunto de 10 — o teto não o
    alcança, só a saída do filtro de season o alcança. -#}
{%- set hist_from %}
    FROM team_fixtures tf
    JOIN team_results_long h
        ON h.team_id        = tf.team_id
       {%- if pit_escopo == 'da_competicao' %}
       AND h.competition_id = tf.competition_id
       {%- endif %}
       {%- if pit_recorte == 'temporada' %}
       AND h.season         = tf.season
       {%- endif %}
       AND h.kickoff_utc    < tf.kickoff_utc
{%- endset %}
{%- if pit_recorte == 'ultimos_10' %}
-- MEDIÇÃO — recorte de contagem: os pares (jogo-alvo, time) × partida anterior são ranqueados e
-- só os N mais recentes sobrevivem, ANTES da agregação. O corte mora num CTE à parte porque
-- QUALIFY na mesma SELECT do GROUP BY filtraria depois de a conta estar feita. O desempate é
-- pelos próprios valores: `kickoff_utc` é TIMESTAMP e empate real seria dado torto, mas com ele
-- o conjunto sobrevivente é determinístico mesmo assim.
hist_pares AS (
    SELECT tf.fixture_id, tf.team_id, h.conceded, h.lost, h.kickoff_utc
{{- hist_from }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY tf.fixture_id, tf.team_id
        ORDER BY h.kickoff_utc DESC, h.conceded DESC, h.lost DESC
    ) <= {{ tamanho_do_recorte }}
),
team_hist AS (
    SELECT
        fixture_id, team_id,
        SAFE_DIVIDE(COUNTIF(conceded >= 3), COUNT(*))                AS thrash_rate,
        ARRAY_AGG(lost ORDER BY kickoff_utc DESC LIMIT 5)            AS last5_lost
    FROM hist_pares
    GROUP BY fixture_id, team_id
),
{%- else %}
team_hist AS (
    SELECT
        tf.fixture_id, tf.team_id,
        SAFE_DIVIDE(COUNTIF(h.conceded >= 3), COUNT(*))              AS thrash_rate,
        ARRAY_AGG(h.lost ORDER BY h.kickoff_utc DESC LIMIT 5)        AS last5_lost
{{- hist_from }}
    GROUP BY tf.fixture_id, tf.team_id
),
{%- endif %}

-- Métricas brutas derivadas (por outcome).
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome,

        -- gols sofridos no total dos dois (equilibrio_defensivo)
        s.goals_against_avg_total  AS s_ga_total,
        od.goals_against_avg_total AS o_ga_total,
        -- % de jogos goleados dos dois
        st.thrash_rate             AS s_thrash_rate,
        ot.thrash_rate             AS o_thrash_rate,

        -- aproveitamento do adversário descoberto O (total)
        (od.wins_total * 3 + od.draws_total) / NULLIF(od.played_total * 3, 0) * 100 AS o_aproveitamento,

        -- invicto de S nos últimos 5 (derrotas e nº de jogos com histórico). Lê last5_lost do
        -- próprio st (team_hist já traz thrash_rate E last5_lost por (fixture,time)) — sem self-join extra.
        -- O IF na frente é a classe (b) do mapa (#41): COUNT sobre array VAZIO devolve 0 sem
        -- nenhum NULL para detectar, e "não perdeu nenhum dos últimos 5" é exatamente o que a
        -- premissa procura — o zero forjado aqui é o disfarce mais perigoso dos três modelos.
        -- (s_games_last5 já chega NULL sozinho: ARRAY_LENGTH(NULL) é NULL.)
        IF(st.last5_lost IS NULL, NULL, (SELECT COUNT(*) FROM UNNEST(st.last5_lost) l WHERE l)) AS s_losses_last5,
        ARRAY_LENGTH(st.last5_lost)                            AS s_games_last5,

        -- Reuso 1X2 (lado S) — classe (c) do mapa (#41). Estas três chegavam COALESCEadas para
        -- FALSE, e o FALSE do 1X2 já era o colapso de "avaliada e não acendeu" com "não pôde ser
        -- avaliada": a cegueira atravessava dois modelos sem deixar rastro. Agora chega NULL
        -- quando a premissa correspondente está na lista de cegas do 1X2 — ou quando não há
        -- linha de 1X2 nenhuma para o lado S. A premissa segue FALSE nos dois casos, pelo
        -- COALESCE da CTE `flags` logo abaixo.
        IF(x.fixture_id IS NULL OR {{ futebol_premissa_esta_cega('x', 'int_futebol_premissas_1x2', 'forca_mismatch') }},       NULL, x.forca_mismatch)       AS x_forca_mismatch,
        IF(x.fixture_id IS NULL OR {{ futebol_premissa_esta_cega('x', 'int_futebol_premissas_1x2', 'superioridade_tabela') }}, NULL, x.superioridade_tabela) AS x_superioridade_tabela,
        IF(x.fixture_id IS NULL OR {{ futebol_premissa_esta_cega('x', 'int_futebol_premissas_1x2', 'h2h_favoravel') }},        NULL, x.h2h_favoravel)        AS x_h2h_favoravel
    FROM outcomes o
    LEFT JOIN pit s        ON s.fixture_id  = o.fixture_id AND s.team_id  = o.s_team_id
    LEFT JOIN pit od       ON od.fixture_id = o.fixture_id AND od.team_id = o.o_team_id
    LEFT JOIN team_hist st ON st.fixture_id = o.fixture_id AND st.team_id = o.s_team_id
    LEFT JOIN team_hist ot ON ot.fixture_id = o.fixture_id AND ot.team_id = o.o_team_id
    LEFT JOIN reuse_1x2 x  ON x.fixture_id  = o.fixture_id AND x.x1_outcome = o.s_1x2_outcome
),

-- Premissas (booleanos) e pesos.
flags AS (
    SELECT
        m.*,
        -- lado coberto forte: reusa forca_mismatch/superioridade_tabela do 1X2 (lado S)
        COALESCE(m.x_forca_mismatch OR m.x_superioridade_tabela, FALSE)           AS lado_coberto_forte,
        -- equilíbrio defensivo: os dois cedem pouco e quase não são goleados
        ( COALESCE(m.s_ga_total <= 1.3 AND m.o_ga_total <= 1.3, FALSE)
          AND COALESCE(m.s_thrash_rate < 0.30 AND m.o_thrash_rate < 0.30, FALSE) ) AS equilibrio_defensivo,
        -- adversário limitado: O com baixo aproveitamento OU retrospecto ruim vs S (h2h)
        ( COALESCE(m.o_aproveitamento < 45, FALSE)
          OR COALESCE(m.x_h2h_favoravel, FALSE) )                                  AS adversario_limitado,
        -- invicto recente: S sem derrota nos últimos 5 (exige >=3 jogos p/ não disparar sem dado)
        ( COALESCE(m.s_games_last5 >= 3, FALSE) AND COALESCE(m.s_losses_last5 = 0, FALSE) ) AS invicto_recente
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        ( 12 * CAST(f.lado_coberto_forte   AS INT64)
        +  8 * CAST(f.equilibrio_defensivo AS INT64)
        +  8 * CAST(f.adversario_limitado  AS INT64)
        +  6 * CAST(f.invicto_recente      AS INT64)
        ) AS pts_premissas,
        0 AS penalidades_dc_pts
    FROM flags f
),

-- Cegueira (#41, ADR 0003): premissas que se aplicavam a esta linha, não acenderam, e não
-- acenderam por FALTA DE INSUMO. Gerada do mapa futebol_insumos_premissa(), nunca escrita à
-- mão. As quatro se aplicam às duas saídas (a Dupla Chance não tem premissa por lado), e duas
-- delas herdam do 1X2 a cegueira das premissas reusadas.
cegueira AS (
    SELECT
        s.*,
        {{ futebol_premissas_cegas('int_futebol_premissas_dc') }} AS premissas_cegas
    FROM scored s
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    -- flags (transparência/debug)
    lado_coberto_forte,
    equilibrio_defensivo,
    adversario_limitado,
    invicto_recente,
    -- agregados
    pts_premissas,
    penalidades_dc_pts,
    -- cegueira: a lista é o que torna o número auditável.
    premissas_cegas,
    ARRAY_LENGTH(premissas_cegas) AS premissas_sem_dado,

    -- "por quê": premissas que dispararam, ordenadas por peso.
    ARRAY(SELECT e FROM UNNEST([
        IF(lado_coberto_forte,
           'o lado coberto (favorito + empate) é o mais forte do confronto', NULL),
        IF(equilibrio_defensivo,
           FORMAT('defesas equilibradas: os dois cedem pouco (%.1f e %.1f gols/jogo) e quase não são goleados',
                  s_ga_total, o_ga_total), NULL),
        IF(adversario_limitado,
           'adversário descoberto é limitado (aproveitamento baixo ou retrospecto ruim no confronto)', NULL),
        IF(invicto_recente,
           FORMAT('sem derrota nos últimos %d jogos', s_games_last5), NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: a penalidade específica (odd_muito_baixa) é odds-based, anexada no mart.
    CAST([] AS ARRAY<STRING>) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM cegueira
