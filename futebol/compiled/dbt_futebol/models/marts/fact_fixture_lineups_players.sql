

WITH players AS (
    SELECT * FROM `smartbetting-dados`.`futebol`.`stg_futebol_fixture_lineups_players`
),

fixtures AS (
    SELECT
        fixture_id,
        competition,
        competition_id,
        season,
        date_utc,
        home_team_id,
        away_team_id
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
)

SELECT
    p.fixture_id,
    f.competition,
    f.competition_id,
    f.season,
    f.date_utc,

    p.team_id,
    p.team_name,
    CASE
        WHEN p.team_id = f.home_team_id THEN 'home'
        WHEN p.team_id = f.away_team_id THEN 'away'
    END                                          AS team_side,

    p.is_starter,
    p.player_slot,
    p.player_id,
    p.player_name,
    p.shirt_number,
    p.position,
    p.grid,
    p.lineup_phase,

    p.loaded_at         AS extracted_at,
    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM players p
INNER JOIN fixtures f ON p.fixture_id = f.fixture_id
-- Descarta slots de escalação sem player_id (lixo da API; ~4 linhas) — não são jogadores reais
-- e quebrariam o not_null do mart (a staging mantém raw e só avisa via severity:warn).
WHERE p.player_id IS NOT NULL
-- Latest-wins: "real" (pós-jogo) vence "confirmed" (~T-30min). Um jogador aparece 1x por
-- fase; dedup por (fixture_id, player_id) mantém a fase mais recente. Desempate determinístico
-- por lineup_phase='real' (em loaded_at empatado, "real" vence — regra explícita, tie-stable).
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.fixture_id, p.player_id
    ORDER BY p.loaded_at DESC, (p.lineup_phase = 'real') DESC
) = 1