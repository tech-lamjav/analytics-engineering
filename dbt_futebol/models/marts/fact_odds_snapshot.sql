{{ config(
    materialized='table',
    partition_by={'field': 'collection_date', 'data_type': 'date'},
    cluster_by=['fixture_id', 'bookmaker_name'],
    description='Coração do value betting: odds pré-jogo de TODAS as casas em 3 janelas por jogo (collection_window t24h = abertura ~24h antes; t1h = intermediária ~1h antes; t15m = fechamento ~15min antes, habilita CLV real) — permite CLV (Closing Line Value), EV e detecção de movimento de linha. outcome_side + line_value destrincham o outcome_label (O/U e Asian Handicap viram pareáveis por linha, sem parse frágil no app). FORWARD-ONLY (não dá pra reconstruir as janelas de jogos passados): o raw acumula no GCS (1 arquivo por fixture×janela) e o rebuild full lê tudo. Self-contained: competition vem de league_id, sem joins. Particionada por collection_date (=DATE(collection_timestamp)) e clusterizada por (fixture_id, bookmaker_name). Afunila p/ os 8 mercados-alvo (market_id IN 1,4,5,6,7,8,10,12) mantendo TODAS as casas — Pinnacle (4) é a sharp de referência p/ CLV. minutes_to_kickoff registra o lead exato da captura (a janela é só rótulo). Dedup latest-wins por (fixture_id, bookmaker_id, market_id, outcome_label, collection_window) — skip-if-exists no GCS já garante 1 captura/janela; o QUALIFY segura resíduo. Brasileirão (71) + Copa do Mundo (1) + Série B (72) 2026 (todos coverage.odds=TRUE). Copa do Brasil (73) e CONMEBOL Libertadores (13): ARMADAS em 2026-07-13, CONMEBOL Sudamericana (11) em 2026-07-14, todas no FUTEBOL_ODDS_LEAGUE_IDS (sem Fase 2 futura — decisão de não depender de deploy depois); coverage.odds é SAZONAL (mata-mata), então ficam dormentes até os jogos entrarem na banda t24h — Sudamericana ~20/07 (R32 ida 21–24/07, volta 28–31/07; oitavas 11–13/08 e 18–20/08), CdB ~31/07 (oitavas 01/08), Libertadores 10/08 (ida das oitavas 11/08, volta 18/08). Verificar Pinnacle no feed na 1ª coleta de cada uma.'
) }}

WITH odds AS (
    SELECT * FROM {{ ref('stg_futebol_odds') }}
)

SELECT
    CASE league_id
        WHEN 71 THEN 'brasileirao'
        WHEN 1  THEN 'copa_mundo'
        WHEN 72 THEN 'serie_b'
        WHEN 73 THEN 'copa_do_brasil'
        WHEN 13 THEN 'libertadores'
        WHEN 11 THEN 'sudamericana'
        WHEN 140 THEN 'la_liga'
        WHEN 39 THEN 'premier_league'
        WHEN 2  THEN 'champions_league'
        WHEN 135 THEN 'serie_a_ita'
        WHEN 78  THEN 'bundesliga'
        WHEN 61  THEN 'ligue_1'
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
    -- mercados): O/U (5,6) 'Over 2.5'→(Over, 2.5); Asian Handicap (4) 'Home -1.5'/'Away -1.5'
    -- →(Home/Away, handicap na ÓTICA DO MANDANTE — MESMO sinal/valor p/ Home e Away, então o par
    -- complementar cai na MESMA line_value/partição de de-vig; confirmado vs. dados reais da
    -- Pinnacle 2026-06-26: a API NÃO inverte o sinal no lado visitante); Match Winner (1)/BTTS (8)
    -- →(Home/Draw/Away|Yes/No, line NULL); Double Chance (12) 'Home/Draw'/'Home/Away'/'Draw/Away'
    -- →(1X/12/X2, line NULL — S5 mapeia explícito p/ o de-vig derivar do 1X2 da Pinnacle);
    -- HT/FT (7) 'Home/Away', Exact Score (10) '1:0' → ambos NULL (composto/placar, sem par).
    -- Torna O/U e Asian Handicap pareáveis via (market_id, line_value, outcome_side).
    CASE
        WHEN market_id = 12 THEN CASE outcome_label
            WHEN 'Home/Draw' THEN '1X'
            WHEN 'Home/Away' THEN '12'
            WHEN 'Draw/Away' THEN 'X2'
        END
        ELSE REGEXP_EXTRACT(outcome_label, r'^(Over|Under|Home|Away|Draw|Yes|No)(?:\s*[+-]?\d|$)')
    END AS outcome_side,
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
