{{ config(severity='warn') }}
-- Cobertura per-fixture: fixture FINALIZADA no spine que não tem NENHUMA linha no fato.
--
-- Complemento (direção oposta) dos assert_*_reconciled: aqueles pegam fixture presente no
-- STG e ausente do spine; este pega fixture presente no SPINE e ausente do fato. As duas
-- direções juntas fecham o quadrado.
--
-- Por que existe: backfill que estoura a quota da API-Football NÃO falha. A API responde
-- HTTP 200 com `errors` preenchido e o workflow termina SUCCEEDED — na Serie A ITA (03/08)
-- isso cortou fact_fixture_player_stats em 123 de 380 jogos sem nenhum sinal. O único jeito
-- de ver o corte é este LEFT JOIN, que até aqui era passo manual de D+1 na cabeça de quem
-- rodou o backfill. O count de `sem_linha` é, ao mesmo tempo, o alarme e o custo EXATO em
-- chamadas p/ fechar o buraco com o extractor cirúrgico.
--
-- severity warn (mesma justificativa dos gêmeos de reconciliação): existem buracos LEGÍTIMOS
-- e conhecidos da API — jogo que devolve `results: 0` sem erro (ex.: Fiorentina 3x0 Inter,
-- fixture 1223728, em /fixtures/statistics), mata-mata sem statistics, e liga-temporada cujo
-- per-fixture nunca foi backfillado por decisão. Um teste que falha sempre vira teste ignorado.
-- O que se lê aqui é a VARIAÇÃO contra o baseline registrado na issue do rollout, não o zero.
--
-- Grão: (competition, season, fato). Agregado de propósito — "liga X, season Y, N jogos mudos"
-- é o que se age em cima; a lista de fixture_id só interessa depois, na hora de fechar.

WITH finalizadas AS (
    SELECT fixture_id, competition, season
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short IN ('FT', 'AET', 'PEN')  -- "finalizado" do projeto inclui prorrogação e pênaltis
),

-- 1 linha por (fato, fixture) presente. DISTINCT porque todos os fatos per-fixture são
-- multi-linha por jogo (2 times, N eventos, N jogadores).
presentes AS (
    SELECT DISTINCT 'fact_fixture_stats'        AS fato, fixture_id FROM {{ ref('fact_fixture_stats') }}
    UNION ALL
    SELECT DISTINCT 'fact_fixture_events'       AS fato, fixture_id FROM {{ ref('fact_fixture_events') }}
    UNION ALL
    SELECT DISTINCT 'fact_fixture_lineups'      AS fato, fixture_id FROM {{ ref('fact_fixture_lineups') }}
    UNION ALL
    SELECT DISTINCT 'fact_fixture_player_stats' AS fato, fixture_id FROM {{ ref('fact_fixture_player_stats') }}
),

-- Produto (fixture finalizada × 4 fatos) = o que DEVERIA existir.
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
HAVING sem_linha > 0
ORDER BY sem_linha DESC
