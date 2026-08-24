{{ config(
    materialized='table',
    cluster_by=['fixture_id', 'team_id'],
    description='Correção da Task 0 (look-ahead) — agregados de forma POINT-IN-TIME por (fixture_id, team_id): tudo é calculado SÓ com jogos FINALIZADOS da MESMA competição/season e com kickoff ANTERIOR ao do jogo-alvo. Substitui as duas fontes contaminadas dos 5 modelos de premissas: (A) fact_team_season_stats, que tem 1 único snapshot por (time, liga, season) — p/ 2024/2025 é a temporada FECHADA (played_total=38 aplicado à rodada 1, ~51% de cada média sendo futuro e 100% dos jogos com o próprio resultado dentro da média); e (B2) o standings_latest (MAX(snapshot_date) sem âncora no kickoff), cujo histórico só começa em 11/06/2026 e que p/ 24/25 é a tabela final. Reconstrói do fact_fixtures o mesmo conjunto de colunas consumido pelos modelos (gols pró/contra casa/fora/total, clean sheet, failed to score, played/wins/draws) MAIS a tabela do campeonato no instante do jogo (rank/points/ppg/n_wins_last5). O rank sai DENTRO do grupo (group_name das standings = estrutura do chaveamento, conhecida antes dos jogos — não é medição): liga de pontos corridos = 1 grupo, logo rank global 1-20 (Brasileirão/Série B/La Liga/PL/Serie A ITA) ou 1-36 (Champions, fase de liga); Libertadores/Sudamericana/Copa do Mundo = rank por grupo (1-4 / 1-12), igual à API; Copa do Brasil não tem standings -> sem grupo -> rank NULL, como já era. Degradação graciosa por construção: no início de temporada played_total=0 -> médias NULL -> premissa FALSE (honesto: na rodada 1 não existe passado). played_* fica exposto p/ que a recalibragem possa decidir um piso de amostra. ⚠️ MEDIÇÃO (task [F], ADR 0007): aceita as vars pit_escopo (da_competicao|todas) e pit_recorte (temporada|ultimos_10). ⚠️ Desde a #91 (ADR 0010) os DEFAULTS são `todas` + `ultimos_10` — a célula `ambos` — e NÃO reproduzem mais o comportamento descrito acima; ele descreve o ramo `da_competicao`/`temporada`, hoje alcançável só passando as vars. Produção USA o default, que é a célula `ambos` da [F]; as vars seguem existindo para as OUTRAS células da medição, materializadas no dataset futebol_taskF. A tabela do campeonato (rank/points/ppg/n_teams/goal_diff) NÃO segue os eixos: classificação existe dentro de uma competição, então ela permanece competição+temporada em todas as células, por construção (ADR 0008). Sob pit_recorte=ultimos_10 sai também played_total_disponivel — quantas partidas anteriores EXISTEM no escopo, sem o teto do recorte; played_total é a contagem USADA e satura em 10. ⚠️ Desde a #91 o default É `ultimos_10`, então a coluna PASSA a ser emitida sempre — e o piso de amostra do task01_base() lê ELA, não o played_total, que sob o teto satura em 10 (ADR 0007).'
) }}
{#-
    EIXOS DE MEDIÇÃO DA TASK [F] (issue #49, ADR 0007) — desde a #91 o DEFAULT deles É produção.

    `pit_escopo`  = quais COMPETIÇÕES contam no histórico do time.
                    da_competicao          = só a competição do jogo (o que rodava até a #91).
                    todas (default)        = qualquer competição do time.

    `pit_recorte` = qual TRECHO do passado conta.
                    temporada          = a temporada corrente (o que rodava até a #91).
                    ultimos_10 (default) = os 10 jogos anteriores, contagem móvel que atravessa
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

    ⚠️ Desde a #91 (ADR 0010) os defaults são `todas` + `ultimos_10` e NÃO reproduzem
    mais o comportamento anterior — a mudança É a entrega. A guarda
    tests/assert_taskf_pit_default_igual_baseline.sql foi recongelada contra a célula
    `ambos` e segue provando que o default não se move sozinho.

    Produção USA o default. Quem mede as OUTRAS células escolhe na linha de comando, contra o
    target `taskF` (dataset de medição), nunca contra dev/prod — que apontam para o dataset do
    board:

      dbt run --target taskF --select int_futebol_team_form_pit \
        --vars '{pit_escopo: todas, pit_recorte: ultimos_10}'
-#}
{%- set eixos       = taskf_eixos() -%}
{%- set pit_escopo  = eixos.escopo -%}
{%- set pit_recorte = eixos.recorte -%}
{#- O tamanho do recorte de contagem (o 10 de `ultimos_10`) vem da mesma macro que valida os
    eixos, e não de um literal digitado aqui: ele é lido também pelos seis sites de histórico dos
    modelos de premissas e pela análise que confere a saturação. -#}
{%- set tamanho_do_recorte = eixos.tamanho_do_recorte -%}
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
        status_short, score_fulltime_home, score_fulltime_away
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
--
-- ⚠️ #71: este CTE alimenta DOIS consumidores com regras diferentes — os agregados de forma, que
-- seguem os eixos da [F], e o CTE `tabela` (pontos/vitórias/saldo), que a ADR 0008 mantém
-- competição+temporada. A entrada de AET/PEN vale para os dois, e isso é decisão, não descuido:
-- a ADR 0008 fixa o ESCOPO da tabela (qual competição, qual temporada), não a definição de
-- "partida encerrada". Footprint em liga de pontos corridos: 3 jogos na base inteira (2 na Ligue 1
-- — 1 AET e 1 PEN — e 1 AET na Bundesliga), de acesso/rebaixamento — e para eles o placar de 90 que
-- passa a contar é o honesto. Nas copas de mata-mata a `tabela` não existe (Copa do Brasil não
-- tem standings -> rank NULL), então o alcance real é o dos 3 jogos.
team_log AS (
    SELECT competition_id, season, kickoff_utc, home_team_id AS team_id,
           TRUE AS is_home, score_fulltime_home AS gf, score_fulltime_away AS ga
    FROM fixtures
    WHERE {{ futebol_jogo_encerrado() }}
    UNION ALL
    SELECT competition_id, season, kickoff_utc, away_team_id,
           FALSE, score_fulltime_away, score_fulltime_home
    FROM fixtures
    WHERE {{ futebol_jogo_encerrado() }}
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
        l.kickoff_utc,
        -- A contagem DISPONÍVEL: quantas partidas anteriores existem no escopo, SEM o teto do
        -- recorte. A window function é avaliada sobre a entrada inteira do SELECT e o QUALIFY
        -- filtra depois, então este COUNT enxerga as partidas que o teto vai descartar. Sem
        -- linha correspondente o LEFT JOIN devolve team_id NULL e o COUNT dá 0, igual ao
        -- played_total — o time sem passado tem as duas contagens em zero.
        COUNT(l.team_id) OVER (PARTITION BY a.fixture_id, lt.team_id) AS played_disponivel
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
    ) <= {{ tamanho_do_recorte }}
),

pit AS (
    SELECT
        l.fixture_id,
        l.anchor_team_id AS team_id,
        l.competition_id,
        l.season,
{{ agregados_pit }},

        -- MEDIÇÃO — a segunda contagem de amostra (#54). `played_total` acima é a USADA: ela
        -- satura no tamanho do recorte, porque só as partidas que sobreviveram ao teto
        -- alimentaram as médias. Esta é a DISPONÍVEL, sem teto. As duas existem separadas para o
        -- piso de amostra significar a mesma coisa nas quatro células: sob recorte de contagem
        -- um piso sobre a usada estaria cortando uma contagem que não passa de 10, e a mesma
        -- palavra "piso 10" queria dizer duas coisas diferentes em duas células.
        --
        -- ⚠️ Fica DENTRO deste ramo, e não no `agregados_pit` compartilhado: no default a
        -- coluna não é emitida e o SQL compilado segue idêntico ao de antes das vars — que é o
        -- que a ADR 0007 promete e a Costura A verifica. Sob `temporada` ela seria redundante
        -- por construção (sem teto, disponível É a usada), e quem carimba a célula projeta
        -- `played_total` no lugar dela.
        MAX(l.played_disponivel) AS played_total_disponivel
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
    {%- if pit_recorte == 'ultimos_10' %}
    -- Ver o comentário no CTE `pit`: existe só sob recorte de contagem, que é o único caso em
    -- que ela difere do played_total.
    r.played_total_disponivel,
    {%- endif %}
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
