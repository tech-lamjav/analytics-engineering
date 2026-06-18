{{ config(
    materialized='table',
    partition_by={'field': 'collection_date', 'data_type': 'date'},
    cluster_by=['fixture_id', 'bookmaker_name'],
    description='Coração do value betting: odds pré-jogo de TODAS as casas em 3 janelas por jogo (collection_window t24h = abertura ~24h antes; t1h = intermediária ~1h antes; t15m = fechamento ~15min antes, habilita CLV real) — permite CLV (Closing Line Value), EV e detecção de movimento de linha. outcome_side + line_value destrincham o outcome_label (O/U e Asian Handicap viram pareáveis por linha, sem parse frágil no app). FORWARD-ONLY (não dá pra reconstruir as janelas de jogos passados): o raw acumula no GCS (1 arquivo por fixture×janela) e o rebuild full lê tudo. Self-contained: competition vem de league_id, sem joins. Particionada por collection_date (=DATE(collection_timestamp)) e clusterizada por (fixture_id, bookmaker_name). Afunila p/ os 8 mercados-alvo (market_id IN 1,4,5,6,7,8,10,12) mantendo TODAS as casas — Pinnacle (4) é a sharp de referência p/ CLV. minutes_to_kickoff registra o lead exato da captura (a janela é só rótulo). Dedup latest-wins por (fixture_id, bookmaker_id, market_id, outcome_label, collection_window) — skip-if-exists no GCS já garante 1 captura/janela; o QUALIFY segura resíduo. Brasileirão (71) + Copa do Mundo (1) 2026 (ambos coverage.odds=TRUE).'
) }}

WITH odds AS (
    SELECT * FROM {{ ref('stg_futebol_odds') }}
)

SELECT
    CASE league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        ELSE 'unknown'
    END                                              AS competition,
    league_id,
    season,
    fixture_id,
    kickoff_utc,

    collection_window,
    collection_timestamp,
    DATE(collection_timestamp)                       AS collection_date,
    -- Lead exato da captura (a banda da janela é só rótulo; CLV usa o valor real).
    TIMESTAMP_DIFF(kickoff_utc, collection_timestamp, MINUTE) AS minutes_to_kickoff,

    bookmaker_id,
    bookmaker_name,
    market_id,
    market_name,
    outcome_label,
    -- Linha + lado destrinchados do outcome_label (parse validado vs. dados reais dos 8
    -- mercados): O/U (5,6) 'Over 2.5'→(Over, 2.5); Asian Handicap (4) 'Home -1.5'/'Away +1.5'
    -- →(Home/Away, handicap ASSINADO na perspectiva do lado); Match Winner (1)/BTTS (8)
    -- →(Home/Draw/Away|Yes/No, line NULL); HT/FT (7) 'Home/Away', Double Chance (12)
    -- 'Home/Draw', Exact Score (10) '1:0' → ambos NULL (composto/placar, sem linha pareável).
    -- Torna O/U e Asian Handicap pareáveis via (market_id, line_value, outcome_side).
    REGEXP_EXTRACT(outcome_label, r'^(Over|Under|Home|Away|Draw|Yes|No)(?:\s*[+-]?\d|$)') AS outcome_side,
    SAFE_CAST(REGEXP_EXTRACT(outcome_label, r'^(?:Over|Under|Home|Away)\s*([+-]?\d+(?:\.\d+)?)') AS FLOAT64) AS line_value,
    odd_decimal,

    api_update,
    loaded_at           AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM odds
-- Afunila p/ os 8 mercados-alvo (IDs validados na API-Football 2026-06-16):
-- 1=Match Winner, 4=Asian Handicap, 5=Goals O/U, 6=Goals O/U 1st Half,
-- 7=HT/FT Double, 8=Both Teams Score, 10=Exact (Correct) Score, 12=Double Chance.
-- Guarda TODAS as casas. odd_decimal > 1.0 (invariante de odds decimais — odd ≤ 1.0 é
-- lixo p/ value betting: não paga lucro/placeholder de mercado indisponível; descarta
-- também odd não-numérica que vira NULL no SAFE_CAST).
WHERE market_id IN (1, 4, 5, 6, 7, 8, 10, 12)
  AND odd_decimal > 1.0
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY fixture_id, bookmaker_id, market_id, outcome_label, collection_window
    ORDER BY loaded_at DESC
) = 1
