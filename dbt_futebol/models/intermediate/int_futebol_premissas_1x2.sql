{{ config(
    materialized='table',
    description='S1 do Motor de Score — premissas de contexto do mercado RESULTADO (1X2). 3 linhas por fixture (outcome Home/Draw/Away). S = lado apostado, O = adversário. ⚠️ Task 0 (look-ahead): forca_mismatch/mando/superioridade_tabela/forma leem int_futebol_team_form_pit (point-in-time por fixture), NÃO mais fact_team_season_stats + standings_latest — que em 24/25 entregavam a temporada fechada e a tabela final a jogos da rodada 1. Cada premissa é um booleano que soma seu peso ao PTS_PREMISSAS (espelha §12.1 do épico MOTOR_SCORE_CONFIABILIDADE.md). Penalidades específicas: pick_empate (-10), desfalque_proprio (-15). Degradação graciosa: dado ausente -> premissa FALSE (Copa sem xG/injuries). evidencias[]/avisos[] = bullets legíveis pro front. O gate/edge/Score são aplicados no mart fact_value_opportunities. ⚠️ MEDIÇÃO (task [F], ADR 0007): o spine de xG aceita as DUAS vars da medição — pit_escopo (da_competicao|todas) e pit_recorte (temporada|ultimos_10, que troca o filtro de season por um teto de 10 partidas) —, cujos DEFAULTS reproduzem exatamente o comportamento descrito acima; no default o SQL compilado é idêntico ao de antes de as vars existirem. Produção nunca a passa; ela serve às células de medição, materializadas no dataset futebol_taskF. superioridade_tabela NÃO segue o eixo (rank/ppg vêm do team_form_pit, que os mantém competição-scoped em todas as células, ADR 0008), e o h2h_favoravel também não, por motivo oposto: o fact_h2h já cruza campeonatos hoje, e restringi-lo seria mudar premissa.'
) }}
{#- EIXOS DE ESCOPO E RECORTE DA MEDIÇÃO DA TASK [F] (issue #49, ADR 0007) — produção nunca passa estas vars.

    Além do que vem do team_form_pit, este modelo tem UMA fonte de histórico competição-scoped
    própria: o spine de xG (CTE `xg`), que alimenta `superioridade_xg`. Ela responde ao mesmo
    eixo, senão a célula sai MISTURADA — `forca_mismatch` com histórico juntado e
    `superioridade_xg` sem —, e um número assim não responde a pergunta da spec.
    `superioridade_tabela` fica de fora por desenho: rank e ppg vêm do team_form_pit, que os
    mantém competição-scoped em todas as células (ADR 0008). O `fact_h2h` também fica de fora, e
    por motivo oposto: ele JÁ cruza campeonatos hoje, e restringi-lo seria mudar premissa.

    Valores aceitos, validação e o porquê do fail-closed em macros/taskf_eixos.sql. No default
    (`da_competicao`/`temporada`) o SQL compilado é IDÊNTICO ao de antes desta var.

    O eixo de RECORTE (`pit_recorte`) alcança a MESMA fonte desde a #54: sob `ultimos_10` o
    filtro de season sai e o spine passa a ler as N partidas mais recentes do time, atravessando
    a virada de temporada. Os dois eixos entram pelo mesmo FROM/JOIN, escrito uma vez logo acima
    do CTE. -#}
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

-- 3 outcomes por fixture; resolve S (apostado) e O (adversário) por lado.
outcomes AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Home' AS outcome, home_team_id AS s_team_id, away_team_id AS o_team_id, TRUE AS s_is_home
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Away', away_team_id, home_team_id, FALSE
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Draw', CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS BOOL)
    FROM fixtures
),

-- Correção da Task 0 (look-ahead): forma E tabela POINT-IN-TIME por (fixture, time), só com
-- jogos anteriores ao kickoff. Uma única fonte no lugar das duas contaminadas —
-- fact_team_season_stats (1 snapshot por season: em 24/25 é a temporada FECHADA aplicada à
-- rodada 1) e standings_latest (MAX(snapshot_date) sem âncora no jogo = tabela final).
pit AS (
    SELECT
        fixture_id, team_id,
        goals_for_avg_home, goals_for_avg_away,
        goals_against_avg_home, goals_against_avg_away,
        wins_home, draws_home, played_home,
        wins_away, draws_away, played_away,
        rank, ppg, n_wins_last5
    FROM {{ ref('int_futebol_team_form_pit') }}
),

-- Spine (fixture-alvo, time) p/ ancorar o xG ao kickoff do jogo (point-in-time).
fixture_team_spine AS (
    SELECT fixture_id, season, competition_id, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, season, competition_id, kickoff_utc, away_team_id FROM fixtures
),
-- xG médio do time ATÉ o jogo: mesma season/competição e jogos ANTERIORES ao kickoff (date_utc <
-- DATE(kickoff)) — time-bounded igual ao h2h/last5, sem look-ahead em fixtures já jogadas. P/ jogos
-- FUTUROS == média da season (todos os jogos com stats são anteriores). Brasileirão preenchido;
-- Copa ~vazio -> NULL -> premissa de xG não dispara.
{#- O FROM/JOIN existe UMA vez e é renderizado nas duas formas do CTE `xg` (média direta no
    default, pares ranqueados sob recorte de contagem). É aqui que os DOIS eixos entram, e é por
    isso que ele não pode ser escrito duas vezes: duas cópias de um predicado de eixo não ficam
    iguais para sempre, e a divergência mediria célula misturada sem levantar nada. Mesma técnica
    do `agregados_pit` do int_futebol_team_form_pit. -#}
{%- set xg_from %}
    FROM fixture_team_spine sp
    JOIN {{ ref('fact_fixture_stats') }} st
        ON  st.team_id        = sp.team_id
        {%- if pit_recorte == 'temporada' %}
        AND st.season         = sp.season
        {%- endif %}
        {%- if pit_escopo == 'da_competicao' %}
        AND st.competition_id = sp.competition_id
        {%- endif %}
        AND st.date_utc       < DATE(sp.kickoff_utc)
    JOIN {{ ref('fact_fixture_stats') }} opp
        ON  opp.fixture_id = st.fixture_id
        AND opp.team_id   != st.team_id
{%- endset %}
{%- if pit_recorte == 'ultimos_10' %}
-- MEDIÇÃO — recorte de contagem. O filtro de season sai e no lugar dele os pares (jogo-alvo,
-- time) × partida anterior são ranqueados, sobrevivendo só os N mais recentes — contagem móvel,
-- que atravessa a virada de temporada por construção. O corte mora num CTE à parte porque
-- QUALIFY na mesma SELECT da agregação filtraria DEPOIS do GROUP BY, com a média já feita.
-- Desempate por fixture_id: `date_utc` é DATE, e duas partidas do mesmo time na mesma data
-- (dado torto) escolheriam sobrevivente ao acaso.
xg_pares AS (
    SELECT
        sp.fixture_id, sp.team_id,
        st.expected_goals  AS xg_for,
        opp.expected_goals AS xg_against
{{- xg_from }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sp.fixture_id, sp.team_id
        ORDER BY st.date_utc DESC, st.fixture_id DESC
    ) <= {{ tamanho_do_recorte }}
),
xg AS (
    SELECT
        fixture_id, team_id,
        AVG(xg_for)     AS xg_for_avg,
        AVG(xg_against) AS xg_against_avg
    FROM xg_pares
    GROUP BY fixture_id, team_id
),
{%- else %}
xg AS (
    SELECT
        sp.fixture_id, sp.team_id,
        AVG(st.expected_goals)  AS xg_for_avg,
        AVG(opp.expected_goals) AS xg_against_avg
{{- xg_from }}
    GROUP BY sp.fixture_id, sp.team_id
),
{%- endif %}

-- ============================================================================
-- S7: desfalque PESADO POR IMPORTÂNCIA. Conta só TITULAR IMPORTANTE fora
-- ('Missing Fixture' AND is_important) por (fixture, time). Fonte:
-- int_futebol_desfalques (injuries x proxy de importância de fact_fixture_player_stats).
-- 'Questionable' (dúvida) NÃO dispara — conservador, fiel à §12.1 ("desfalque de
-- titular"); o tipo segue guardado/exibido em int_futebol_desfalques (front).
-- ============================================================================
desf AS (
    SELECT
        fixture_id,
        team_id,
        COUNTIF(injury_type = 'Missing Fixture' AND is_important) AS missing_important_count
    FROM {{ ref('int_futebol_desfalques') }}
    GROUP BY fixture_id, team_id
),

-- H2H: confrontos diretos ANTERIORES ao jogo; conta vitórias de S (só Home/Away).
h2h AS (
    SELECT
        o.fixture_id, o.outcome,
        COUNT(*) AS h2h_total,
        COUNTIF(
            (h.home_team_id = o.s_team_id AND h.home_team_winner)
         OR (h.away_team_id = o.s_team_id AND h.away_team_winner)
        ) AS s_wins
    FROM outcomes o
    JOIN {{ ref('fact_h2h') }} h
        ON h.h2h_pair_key = CONCAT(
               CAST(LEAST(o.s_team_id, o.o_team_id) AS STRING), '-',
               CAST(GREATEST(o.s_team_id, o.o_team_id) AS STRING))
       AND h.fixture_id  != o.fixture_id
       AND h.kickoff_utc  < o.kickoff_utc
    WHERE o.s_team_id IS NOT NULL
    GROUP BY o.fixture_id, o.outcome
),

-- Métricas brutas derivadas (por outcome).
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome, o.s_is_home,

        -- ataque de S no seu campo / defesa de O no campo dele (forca_mismatch)
        IF(o.s_is_home, s.goals_for_avg_home, s.goals_for_avg_away)          AS s_gf_venue,
        IF(o.s_is_home, od.goals_against_avg_away, od.goals_against_avg_home) AS o_ga_venue,

        -- aproveitamento (mando)
        (s.wins_home * 3 + s.draws_home) / NULLIF(s.played_home * 3, 0) * 100 AS pct_pts_home,
        (s.wins_away * 3 + s.draws_away) / NULLIF(s.played_away * 3, 0) * 100 AS aprov_fora,

        -- xG (superioridade_xg)
        sx.xg_for_avg      AS s_xg_for,
        ox.xg_against_avg  AS o_xg_against,

        -- desfalques pesados por importância (S7): só titular importante fora conta
        COALESCE(si.missing_important_count, 0) AS s_missing,
        COALESCE(oi.missing_important_count, 0) AS o_missing,

        -- tabela do campeonato NO INSTANTE DO JOGO (superioridade_tabela)
        s.rank    AS s_rank,
        od.rank   AS o_rank,
        s.ppg     AS s_ppg,
        od.ppg    AS o_ppg,

        -- forma: vitórias nos 5 jogos ANTERIORES ao kickoff (antes: 'W' no form do último snapshot)
        COALESCE(s.n_wins_last5, 0) AS n_wins_last5,

        -- h2h
        COALESCE(hh.h2h_total, 0) AS h2h_total,
        COALESCE(hh.s_wins, 0)    AS s_wins
    FROM outcomes o
    LEFT JOIN pit s   ON s.fixture_id  = o.fixture_id AND s.team_id  = o.s_team_id
    LEFT JOIN pit od  ON od.fixture_id = o.fixture_id AND od.team_id = o.o_team_id
    LEFT JOIN xg sx   ON sx.fixture_id = o.fixture_id AND sx.team_id = o.s_team_id
    LEFT JOIN xg ox   ON ox.fixture_id = o.fixture_id AND ox.team_id = o.o_team_id
    LEFT JOIN desf si  ON si.fixture_id = o.fixture_id AND si.team_id = o.s_team_id
    LEFT JOIN desf oi  ON oi.fixture_id = o.fixture_id AND oi.team_id = o.o_team_id
    LEFT JOIN h2h hh  ON hh.fixture_id = o.fixture_id AND hh.outcome = o.outcome
),

-- Premissas (booleanos) e pesos.
flags AS (
    SELECT
        m.*,
        COALESCE(m.s_gf_venue >= 1.4 AND m.o_ga_venue >= 1.3, FALSE)        AS forca_mismatch,
        COALESCE(m.s_xg_for - m.o_xg_against >= 0.3, FALSE)                 AS superioridade_xg,
        CASE
            WHEN m.s_is_home       AND m.pct_pts_home >= 55 THEN 8
            WHEN m.s_is_home = FALSE AND m.aprov_fora  >= 45 THEN 4
            ELSE 0
        END                                                                AS pts_mando,
        COALESCE(m.o_missing >= 1 AND m.s_missing = 0, FALSE)              AS desfalque_adversario,
        (COALESCE(m.o_rank - m.s_rank >= 6, FALSE)
            OR COALESCE(m.s_ppg >= 1.3 * m.o_ppg, FALSE))                  AS superioridade_tabela,
        COALESCE(m.n_wins_last5 >= 3, FALSE)                               AS forma,
        COALESCE(m.h2h_total >= 1 AND m.s_wins * 2 >= m.h2h_total, FALSE)  AS h2h_favoravel,
        -- penalidades específicas 1X2
        (m.outcome = 'Draw')                                              AS pick_empate,
        (m.s_missing >= 1)                                                AS desfalque_proprio
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        (f.pts_mando > 0) AS mando,
        (
            12 * CAST(f.forca_mismatch       AS INT64)
          +  8 * CAST(f.superioridade_xg     AS INT64)
          +       f.pts_mando
          +  8 * CAST(f.desfalque_adversario AS INT64)
          +  6 * CAST(f.superioridade_tabela AS INT64)
          +  5 * CAST(f.forma                AS INT64)
          +  4 * CAST(f.h2h_favoravel        AS INT64)
        ) AS pts_premissas,
        (
            10 * CAST(f.pick_empate       AS INT64)
          + 15 * CAST(f.desfalque_proprio AS INT64)
        ) AS penalidades_1x2_pts
    FROM flags f
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    -- flags (transparência/debug)
    forca_mismatch,
    superioridade_xg,
    mando,
    pts_mando,
    desfalque_adversario,
    superioridade_tabela,
    forma,
    h2h_favoravel,
    pick_empate,
    desfalque_proprio,
    s_missing,
    -- agregados
    pts_premissas,
    penalidades_1x2_pts,

    -- "por quê": premissas que dispararam, em linguagem de gente, ordenadas por peso.
    ARRAY(SELECT e FROM UNNEST([
        IF(forca_mismatch,
           FORMAT('marca %.1f gol/jogo %s e o adversário cede %.1f %s',
                  s_gf_venue, IF(s_is_home, 'em casa', 'fora'),
                  o_ga_venue, IF(s_is_home, 'fora', 'em casa')), NULL),
        IF(superioridade_xg,
           FORMAT('cria %.2f xG/jogo contra %.2f que o adversário costuma ceder',
                  s_xg_for, o_xg_against), NULL),
        IF(mando,
           IF(s_is_home,
              FORMAT('%.0f%% dos pontos como mandante', pct_pts_home),
              FORMAT('%.0f%% de aproveitamento como visitante', aprov_fora)), NULL),
        IF(desfalque_adversario,
           FORMAT('adversário com %d titular(es) importante(s) fora e time completo', o_missing), NULL),
        IF(superioridade_tabela, 'claramente superior na tabela', NULL),
        IF(forma, FORMAT('%d vitórias nos últimos 5 jogos', n_wins_last5), NULL),
        IF(h2h_favoravel,
           FORMAT('venceu %d dos últimos %d confrontos diretos', s_wins, h2h_total), NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: penalidades específicas do 1X2.
    ARRAY(SELECT a FROM UNNEST([
        IF(pick_empate, '⚠ empate é a saída mais difícil de prever (−10)', NULL),
        IF(desfalque_proprio,
           FORMAT('⚠ desfalcado: %d titular(es) importante(s) fora (−15)', s_missing), NULL)
    ]) AS a WHERE a IS NOT NULL) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM scored
