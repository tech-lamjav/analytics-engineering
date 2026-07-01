

WITH odds AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`stg_futebol_odds`
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