

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
-- A fase entra no grão (#38). Antes o dedup era por (fixture_id, player_id) e a "real",
-- que chega depois do jogo, sobrescrevia a "confirmed" — look-ahead entrando pela porta
-- do dedup, e a confirmada é a única evidência pré-apito de quem entra em campo.
-- O latest-wins continua existindo DENTRO de cada fase, para absorver re-execução do pipeline.
-- O desempate por (is_starter, player_slot) NÃO é decorativo: a API às vezes repete o mesmo
-- jogador em dois slots da MESMA fase e do MESMO loaded_at (11 grupos hoje, alguns startXI +
-- substitutes, outros dois slots do startXI). Sem ele o vencedor muda entre builds do mesmo
-- código — a classe de irreprodutibilidade que a #78 já custou uma vez. Titular vence reserva
-- (a linha mais informativa), o menor slot desempata o resto, e `team_id` fecha a ordenação:
-- os três primeiros critérios empatam por completo se o mesmo jogador aparecer nos blocos dos
-- DOIS times (a API já trocou identidade de clube antes), e aí team_side viraria entre builds.
--
-- ⚠️ Nenhum teste de unicidade pega a remoção deste desempate — ROW_NUMBER()=1 devolve uma
-- linha por partição sob QUALQUER ORDER BY. Quem protege é o unit test
-- `fixture_lineups_players_desempate_dentro_da_fase_e_deterministico`.
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.fixture_id, p.player_id, p.lineup_phase
    ORDER BY p.loaded_at DESC, p.is_starter DESC, p.player_slot ASC, p.team_id ASC
) = 1