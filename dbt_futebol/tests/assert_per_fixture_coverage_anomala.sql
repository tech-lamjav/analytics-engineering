{{ config(tags=['guarda'], severity='error') }}
-- Cobertura per-fixture ANÔMALA: a versão GATEÁVEL do assert_per_fixture_coverage.
--
-- Por que existem os dois. O gêmeo (assert_per_fixture_coverage) responde "o que exatamente
-- está faltando" e é a ferramenta de verificação de D+1 de rollout: ele lista TODO buraco, o
-- que o deixa permanentemente ambar (24 linhas na medição de 2026-08-06) e portanto ilegível
-- como sinal diário — um teste que acende sempre vira teste ignorado. Este aqui responde a
-- outra pergunta, a que dá pra automatizar: "algum buraco é GRANDE o bastante p/ não ser da
-- API?". Só este entra na tag `guarda`.
--
-- O modo de falha que ele existe p/ pegar: backfill que estoura a quota da API-Football NÃO
-- falha — a API responde HTTP 200 com `errors` preenchido e o workflow termina SUCCEEDED. Na
-- Serie A ITA (2026-08-03) isso cortou fact_fixture_player_stats em 123 de 380 jogos sem
-- nenhum sinal: 67,6% da liga-temporada muda.
--
-- COMO O LIMIAR FOI ESCOLHIDO (medido 2026-08-06, não estimado). Três desenhos foram
-- falsificados antes deste, e vale registrar p/ ninguém repetir:
--   1. Usar coverage.fixtures.statistics_* de dim_leagues p/ saber onde exigir N/N: INÚTIL.
--      A flag é TRUE p/ TODAS as competições, inclusive Copa do Brasil e Champions, que na
--      prática devolvem vazio por fixture. A API declara cobertura que não entrega.
--   2. Limiar puro de magnitude, sem excluir ninguém: IMPOSSÍVEL. O mata-mata legítimo chega a
--      71,2% de ausência (champions_league 2026, player_stats) e o incidente real foi 67,6% —
--      o ruído é MAIOR que o sinal, então nenhum corte os separa.
--   3. Descer o grão p/ (competition, season, round) e acender só em rodada PARCIALMENTE vazia:
--      NÃO SEPARA. As lacunas estruturais são 70–96% parciais (ex.: copa_do_brasil 2024 "1st
--      Round" = 37 de 40 sem player_stats), e um corte por quota é contíguo na ordem de
--      ingestão, produzindo o mesmo rastro de rodada quase-vazia.
--
-- O que sobrou e funciona: excluir as DUAS competições cujas fases iniciais a API não cobre e
-- pôr um limiar com folga nas demais. Com copa_do_brasil e champions_league fora, o resíduo da
-- base inteira é de 1 a 5 jogos por liga-temporada×fato — máximo 3,2% (libertadores 2024,
-- player_stats). Contra 67,6% do incidente: 3x de folga do lado do ruído, 6,7x do lado do sinal.
--
-- A exclusão é DECISÃO, não acidente, e o critério é "mata-mata cujas fases iniciais a API não
-- cobre" — não "mata-mata". Libertadores e Sudamericana também são mata-mata e ficam DENTRO,
-- porque a ausência delas cabe na tolerância. Competição nova de copa precisa ser medida antes
-- de entrar aqui; enquanto não for, ela fica dentro e acende — que é o lado certo p/ errar.
--
-- LIMITE CONHECIDO: truncamento abaixo do limiar passa. 10% de 380 jogos são 38 fixtures, e
-- abaixo disso o corte é indistinguível do ruído da API com os dados que temos. Quem quer o
-- quadro completo usa o gêmeo, na verificação de D+1.

{% set competicoes_sem_cobertura_inicial = ['copa_do_brasil', 'champions_league'] %}
{% set tolerancia_pct = 10 %}

WITH finalizadas AS (
    SELECT fixture_id, competition, season
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short IN ('FT', 'AET', 'PEN')
      AND competition NOT IN (
          {%- for c in competicoes_sem_cobertura_inicial %}'{{ c }}'{{ ", " if not loop.last }}{%- endfor -%}
      )
),

presentes AS (
    SELECT DISTINCT 'fact_fixture_stats'        AS fato, fixture_id FROM {{ ref('fact_fixture_stats') }}
    UNION ALL
    SELECT DISTINCT 'fact_fixture_events'       AS fato, fixture_id FROM {{ ref('fact_fixture_events') }}
    UNION ALL
    SELECT DISTINCT 'fact_fixture_lineups'      AS fato, fixture_id FROM {{ ref('fact_fixture_lineups') }}
    UNION ALL
    SELECT DISTINCT 'fact_fixture_player_stats' AS fato, fixture_id FROM {{ ref('fact_fixture_player_stats') }}
),

esperado AS (
    SELECT f.fixture_id, f.competition, f.season, fato
    FROM finalizadas f
    CROSS JOIN UNNEST([
        'fact_fixture_stats',
        'fact_fixture_events',
        'fact_fixture_lineups',
        'fact_fixture_player_stats'
    ]) AS fato
)

SELECT
    e.competition,
    e.season,
    e.fato,
    COUNT(*)                                                     AS fixtures_finalizadas,
    COUNTIF(p.fixture_id IS NULL)                                AS sem_linha,
    ROUND(100 * COUNTIF(p.fixture_id IS NULL) / COUNT(*), 1)     AS pct_sem_linha
FROM esperado e
LEFT JOIN presentes p
    ON  p.fixture_id = e.fixture_id
    AND p.fato       = e.fato
GROUP BY e.competition, e.season, e.fato
HAVING pct_sem_linha > {{ tolerancia_pct }}
ORDER BY pct_sem_linha DESC
