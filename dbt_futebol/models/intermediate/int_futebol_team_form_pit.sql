{{ config(
    materialized='table',
    cluster_by=['fixture_id', 'team_id'],
    description='Correção da Task 0 (look-ahead) — agregados de forma POINT-IN-TIME por (fixture_id, team_id): tudo é calculado SÓ com jogos FINALIZADOS da MESMA competição/season e com kickoff ANTERIOR ao do jogo-alvo. Substitui as duas fontes contaminadas dos 5 modelos de premissas: (A) fact_team_season_stats, que tem 1 único snapshot por (time, liga, season) — p/ 2024/2025 é a temporada FECHADA (played_total=38 aplicado à rodada 1, ~51% de cada média sendo futuro e 100% dos jogos com o próprio resultado dentro da média); e (B2) o standings_latest (MAX(snapshot_date) sem âncora no kickoff), cujo histórico só começa em 11/06/2026 e que p/ 24/25 é a tabela final. Reconstrói do fact_fixtures o mesmo conjunto de colunas consumido pelos modelos (gols pró/contra casa/fora/total, clean sheet, failed to score, played/wins/draws) MAIS a tabela do campeonato no instante do jogo (rank/points/ppg/n_wins_last5). O rank sai DENTRO do grupo (group_name das standings = estrutura do chaveamento, conhecida antes dos jogos — não é medição): liga de pontos corridos = 1 grupo, logo rank global 1-20 (Brasileirão/Série B/La Liga/PL/Serie A ITA) ou 1-36 (Champions, fase de liga); Libertadores/Sudamericana/Copa do Mundo = rank por grupo (1-4 / 1-12), igual à API; Copa do Brasil não tem standings -> sem grupo -> rank NULL, como já era. Degradação graciosa por construção: no início de temporada played_total=0 -> médias NULL -> premissa FALSE (honesto: na rodada 1 não existe passado). played_* fica exposto p/ que a recalibragem possa decidir um piso de amostra. ⚠️ MEDIÇÃO (task [F], ADR 0007): aceita as vars pit_escopo (da_competicao|todas) e pit_recorte (temporada|ultimos_10), cujos DEFAULTS reproduzem exatamente o descrito acima — no default o SQL compilado é idêntico ao de antes das vars existirem. Produção nunca as passa; elas servem às células de medição, materializadas no dataset futebol_taskF. A tabela do campeonato (rank/points/ppg/n_teams/goal_diff) NÃO segue os eixos: classificação existe dentro de uma competição, então ela permanece competição+temporada em todas as células, por construção (ADR 0008).'
) }}
{#-
    EIXOS DE MEDIÇÃO DA TASK [F] (issue #49, ADR 0007) — não usados em produção.

    `pit_escopo`  = quais COMPETIÇÕES contam no histórico do time.
                    da_competicao (default) = só a competição do jogo, o que roda hoje.
                    todas                   = qualquer competição do time.

    `pit_recorte` = qual TRECHO do passado conta.
                    temporada (default) = a temporada corrente, o que roda hoje.
                    ultimos_10          = os 10 jogos anteriores, contagem móvel que atravessa
                                          a virada de temporada por construção.

    ⚠️ `recorte`, nunca `janela`: janela é a janela de coleta de odds (daily/t24h/t1h/t15m) e as
    duas coisas não têm relação. Ver o glossário no CONTEXT.md.

    ⚠️ ESTE MODELO NÃO É A ÚNICA FONTE QUE O EIXO DE ESCOPO ALCANÇA. Cada um dos cinco modelos de
    premissas tem histórico competição-scoped próprio — os `last5` de Gols, BTTS e Dupla Chance, o
    `margin_stats` do Handicap e o spine de xG/ritmo — e todos leem a MESMA var. São nove
    predicados de join em seis modelos; a tabela de quem-alcança-o-quê está na ADR 0007. Mexer só
    aqui produziria célula misturada (`clean_sheets_altos` juntado ao lado de `historico_over` não
    juntado), que é exatamente o número que não responde a pergunta da spec.

    Os valores aceitos e a validação vivem em macros/taskf_eixos.sql, uma vez só: sete cópias da
    lista — os seis modelos mais a taskf_celula() — não ficam iguais para sempre, e a divergência
    seria muda.

    Os dois defaults reproduzem o comportamento de hoje, e a igualdade é fato verificado, não
    promessa: tests/assert_taskf_pit_default_igual_baseline.sql compara a saída no default contra
    o baseline congelado antes de esta var existir. No default o SQL compilado é IDÊNTICO ao de
    antes da var — nenhum ramo novo é emitido.

    Produção nunca passa estas vars. Quem mede escolhe a célula na linha de comando, contra o
    target `taskF` (dataset de medição), nunca contra dev/prod — que apontam para o dataset do
    board:

      dbt run --target taskF --select int_futebol_team_form_pit \
        --vars '{pit_escopo: todas, pit_recorte: ultimos_10}'
-#}
{%- set eixos       = taskf_eixos() -%}
{%- set pit_escopo  = eixos.escopo -%}
{%- set pit_recorte = eixos.recorte -%}
{#- Fora do default, a tabela do campeonato precisa do próprio agregado, competição-scoped
    (ADR 0008) — e o rank/ppg passam a sair dele, não do agregado da célula. -#}
{%- set tabela_propria = (pit_escopo != 'da_competicao') or (pit_recorte != 'temporada') -%}
{%- set tab = 'tb' if tabela_propria else 'p' -%}
{#- A lista de agregados existe UMA vez e é renderizada nas duas formas do CTE pit (junção direta
    no default, pares ranqueados sob recorte de contagem) — para as duas formas não derivarem. -#}
{%- set agregados_pit %}
        -- jogos / resultados
        COUNTIF(l.is_home)                          AS played_home,
        COUNTIF(NOT l.is_home)                      AS played_away,
        COUNT(l.team_id)                            AS played_total,
        COUNTIF(l.is_home       AND l.gf > l.ga)    AS wins_home,
        COUNTIF(l.is_home       AND l.gf = l.ga)    AS draws_home,
        COUNTIF(NOT l.is_home   AND l.gf > l.ga)    AS wins_away,
        COUNTIF(NOT l.is_home   AND l.gf = l.ga)    AS draws_away,
        COUNTIF(l.gf > l.ga)                        AS wins_total,
        COUNTIF(l.gf = l.ga)                        AS draws_total,

        -- gols marcados / sofridos (médias por venue e no total)
        SAFE_DIVIDE(SUM(IF(l.is_home,     l.gf, 0)), COUNTIF(l.is_home))     AS goals_for_avg_home,
        SAFE_DIVIDE(SUM(IF(NOT l.is_home, l.gf, 0)), COUNTIF(NOT l.is_home)) AS goals_for_avg_away,
        SAFE_DIVIDE(SUM(l.gf),                       COUNT(l.team_id))       AS goals_for_avg_total,
        SAFE_DIVIDE(SUM(IF(l.is_home,     l.ga, 0)), COUNTIF(l.is_home))     AS goals_against_avg_home,
        SAFE_DIVIDE(SUM(IF(NOT l.is_home, l.ga, 0)), COUNTIF(NOT l.is_home)) AS goals_against_avg_away,
        SAFE_DIVIDE(SUM(l.ga),                       COUNT(l.team_id))       AS goals_against_avg_total,

        -- defesa / ataque agregados
        COUNTIF(l.ga = 0)                           AS clean_sheet_total,
        COUNTIF(l.gf = 0)                           AS failed_to_score_total,

        -- insumos da tabela do campeonato
        COUNTIF(l.gf > l.ga) * 3 + COUNTIF(l.gf = l.ga)  AS points,
        COALESCE(SUM(l.gf), 0)                           AS goals_for_total,
        COALESCE(SUM(l.gf) - SUM(l.ga), 0)               AS goal_diff,

        -- forma: os últimos 5 resultados ANTES do jogo (substitui o parse de standings.form)
        ARRAY_AGG(
            CASE WHEN l.gf > l.ga THEN 'W'
                 WHEN l.gf = l.ga THEN 'D'
                 WHEN l.gf < l.ga THEN 'L' END
            IGNORE NULLS ORDER BY l.kickoff_utc DESC LIMIT 5
        ) AS last5_desc
{%- endset %}

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc,
        status_short, goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
),

-- Grão de saída: os dois lados de cada jogo (inclusive jogos futuros).
targets AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           home_team_id AS team_id
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           away_team_id
    FROM fixtures
),

-- Jogos FINALIZADOS viram 1 linha por (time, jogo), com o eixo casa/fora. É a única fonte de
-- performance daqui p/ baixo — mesmo idioma das CTEs last5/margin_stats/team_hist que já existem.
team_log AS (
    SELECT competition_id, season, kickoff_utc, home_team_id AS team_id,
           TRUE AS is_home, goals_home AS gf, goals_away AS ga
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
    UNION ALL
    SELECT competition_id, season, kickoff_utc, away_team_id,
           FALSE, goals_away, goals_home
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),

-- Universo de times por (liga, season) — tirado de fixtures, não de standings, p/ a Copa do
-- Brasil (sem tabela) também ter n_teams.
league_teams AS (
    SELECT DISTINCT competition_id, season, team_id
    FROM targets
),
league_size AS (
    SELECT competition_id, season, COUNT(*) AS n_teams
    FROM league_teams
    GROUP BY competition_id, season
),

-- Grupo de cada time. É estrutura de chaveamento (o sorteio), conhecida antes dos jogos —
-- entra só p/ o rank PIT ser calculado no mesmo recorte que o rank da API. Dedup igual ao
-- standings_latest que estava nos modelos: prefere o grupo principal ao "third-placed".
team_group AS (
    SELECT league_id AS competition_id, season, team_id, group_name
    FROM {{ ref('fact_standings_snapshot') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY league_id, season, team_id
        ORDER BY CASE WHEN group_name LIKE '%third-placed%' THEN 1 ELSE 0 END,
                 snapshot_date DESC
    ) = 1
),

-- Cada fixture é uma ÂNCORA DE TEMPO. Cruzada com TODOS os times da liga porque o rank exige a
-- tabela inteira naquele instante, não só os dois times do jogo (o filtro p/ os dois vem no fim).
anchors AS (
    SELECT fixture_id, competition_id, season, kickoff_utc FROM fixtures
),
{% if pit_recorte == 'ultimos_10' %}
-- MEDIÇÃO — recorte de CONTAGEM. O par (âncora, time) × jogo anterior vira linha, e só os 10
-- kickoffs mais recentes sobrevivem. Atravessa temporada por construção: é isso que separa a
-- coluna direita da esquerda do 2x2. O LEFT JOIN sem correspondência devolve kickoff NULL, que
-- o ROW_NUMBER mantém em 1 — o time sem passado segue com played_total = 0.
pares AS (
    SELECT
        a.fixture_id,
        lt.team_id AS anchor_team_id,
        a.competition_id,
        a.season,
        l.team_id,
        l.is_home,
        l.gf,
        l.ga,
        l.kickoff_utc
    FROM anchors a
    JOIN league_teams lt
        ON  lt.competition_id = a.competition_id
        AND lt.season         = a.season
    LEFT JOIN team_log l
        ON  l.team_id        = lt.team_id
        {%- if pit_escopo == 'da_competicao' %}
        AND l.competition_id = a.competition_id
        {%- endif %}
        AND l.kickoff_utc    < a.kickoff_utc
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY a.fixture_id, lt.team_id
        ORDER BY l.kickoff_utc DESC
    ) <= 10
),

pit AS (
    SELECT
        l.fixture_id,
        l.anchor_team_id AS team_id,
        l.competition_id,
        l.season,
{{ agregados_pit }}
    FROM pares l
    GROUP BY l.fixture_id, l.anchor_team_id, l.competition_id, l.season
),
{% else %}
pit AS (
    SELECT
        a.fixture_id,
        lt.team_id,
        a.competition_id,
        a.season,
{{ agregados_pit }}
    FROM anchors a
    JOIN league_teams lt
        ON  lt.competition_id = a.competition_id
        AND lt.season         = a.season
    LEFT JOIN team_log l
        ON  l.team_id        = lt.team_id
        {%- if pit_escopo == 'da_competicao' %}
        AND l.competition_id = a.competition_id
        {%- endif %}
        AND l.season         = a.season
        AND l.kickoff_utc    < a.kickoff_utc
    GROUP BY a.fixture_id, lt.team_id, a.competition_id, a.season
),
{% endif %}
{%- if tabela_propria %}
-- MEDIÇÃO — a tabela do campeonato NÃO segue a célula (ADR 0008). Classificação existe dentro de
-- uma competição: não há rank num histórico que atravessa competições, e o sem_rodizio chega a
-- comparar o rank contra o tamanho da liga. Este agregado é o de hoje, competição + temporada,
-- e é dele que saem rank e ppg em qualquer célula — por isso as quatro premissas de tabela dão
-- número idêntico nas quatro, por construção.
tabela AS (
    SELECT
        a.fixture_id,
        lt.team_id,
        COUNT(l.team_id)                                 AS played_total,
        COUNTIF(l.gf > l.ga) * 3 + COUNTIF(l.gf = l.ga)  AS points,
        COUNTIF(l.gf > l.ga)                             AS wins_total,
        COALESCE(SUM(l.gf), 0)                           AS goals_for_total,
        COALESCE(SUM(l.gf) - SUM(l.ga), 0)               AS goal_diff
    FROM anchors a
    JOIN league_teams lt
        ON  lt.competition_id = a.competition_id
        AND lt.season         = a.season
    LEFT JOIN team_log l
        ON  l.team_id        = lt.team_id
        AND l.competition_id = a.competition_id
        AND l.season         = a.season
        AND l.kickoff_utc    < a.kickoff_utc
    GROUP BY a.fixture_id, lt.team_id
),
{% endif %}
-- Tabela do campeonato no instante do jogo. Critério de desempate = pontos > vitórias > saldo >
-- gols pró (o do Brasileirão), + team_id p/ ser determinístico. ROW_NUMBER e não RANK porque o
-- rank da API é estrito (não repete posição), e o modelo compara diferenças de rank.
-- rank NULL quando o time ainda não jogou na temporada: antes da rodada 1 a tabela não existe e
-- todo mundo empataria em 0 -> `s_rank <= 6` do sem_rodizio dispararia p/ a liga inteira.
ranked AS (
    SELECT
        p.*{% if tabela_propria %} EXCEPT (points, goals_for_total, goal_diff),
        tb.points,
        tb.goal_diff,
        tb.played_total AS played_total_tabela{% endif %},
        tg.group_name,
        IF(tg.group_name IS NULL OR {{ tab }}.played_total = 0, NULL,
           ROW_NUMBER() OVER (
               PARTITION BY p.fixture_id, tg.group_name
               ORDER BY {{ tab }}.points DESC, {{ tab }}.wins_total DESC, {{ tab }}.goal_diff DESC,
                        {{ tab }}.goals_for_total DESC, p.team_id
           )
        ) AS rank
    FROM pit p
    {%- if tabela_propria %}
    JOIN tabela tb
        ON  tb.fixture_id = p.fixture_id
        AND tb.team_id    = p.team_id
    {%- endif %}
    LEFT JOIN team_group tg
        ON  tg.competition_id = p.competition_id
        AND tg.season         = p.season
        AND tg.team_id        = p.team_id
)

SELECT
    t.fixture_id,
    t.team_id,
    t.competition,
    t.competition_id,
    t.season,
    t.kickoff_utc,

    -- jogos / resultados (todos PIT)
    r.played_home,
    r.played_away,
    r.played_total,
    r.wins_home,
    r.draws_home,
    r.wins_away,
    r.draws_away,
    r.wins_total,
    r.draws_total,

    -- gols
    r.goals_for_avg_home,
    r.goals_for_avg_away,
    r.goals_for_avg_total,
    r.goals_against_avg_home,
    r.goals_against_avg_away,
    r.goals_against_avg_total,
    r.clean_sheet_total,
    r.failed_to_score_total,

    -- tabela do campeonato no instante do jogo
    r.rank,
    r.points,
    r.goal_diff,
    SAFE_DIVIDE(r.points, r.played_total{% if tabela_propria %}_tabela{% endif %}) AS ppg,
    ls.n_teams,
    r.group_name,

    -- forma (últimos 5 antes do jogo). form_last5 sai do mais ANTIGO p/ o mais RECENTE, igual à
    -- convenção do campo form da API (que os modelos liam com RIGHT(form, 5)).
    (SELECT COUNT(*) FROM UNNEST(r.last5_desc) x WHERE x = 'W') AS n_wins_last5,
    ARRAY_LENGTH(COALESCE(r.last5_desc, []))                    AS n_games_last5,
    ARRAY_TO_STRING(ARRAY_REVERSE(COALESCE(r.last5_desc, [])), '') AS form_last5,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM targets t
JOIN ranked r
    ON  r.fixture_id = t.fixture_id
    AND r.team_id    = t.team_id
LEFT JOIN league_size ls
    ON  ls.competition_id = t.competition_id
    AND ls.season         = t.season
