/*
    [F-1] Congela o BASELINE da Costura A — a saída do int_futebol_team_form_pit ANTES de a var
    de escopo/recorte entrar no modelo.

    Por que existe: a ADR 0007 deixa no código de produção uma var que produção nunca usa. A
    promessa que a acompanha é "o default preserva o comportamento de hoje". Este congelamento é
    o lado esquerdo da igualdade que transforma essa promessa em fato verificável — o direito é
    tests/assert_taskf_pit_default_igual_baseline.sql.

    ⚠️ RODA UMA VEZ SÓ, e ANTES de a var entrar no modelo. Re-congelar depois da var apaga a
    guarda: o baseline passaria a sair do mesmo código que ele deveria auditar, e a Costura A
    ficaria verde por construção. Se um dia for preciso re-congelar (mudança legítima de
    comportamento do modelo), isso é decisão de quem revisa, não passo de rotina.

    JÁ FOI RODADO: 2026-08-12 12:22 UTC, commit a3b954e, 21.054 linhas e 37 partições.

    Três tabelas, todas FORA do dbt de propósito — nenhuma é modelo, então nenhum `dbt run` as
    reconstrói:

      baseline_int_futebol_team_form_pit  a saída congelada, sem dbt_loaded_at (que muda a cada
                                          build por construção e não é comportamento).
      baseline_pit_fingerprint            impressão digital do INSUMO por (competition_id,
                                          season), emitida pela macro taskf_fingerprint_insumo_pit
                                          — a MESMA que o teste usa. O contrato congelado dela
                                          está no cabeçalho da macro; as duas pontas leem de lá
                                          justamente para não haver duas cópias que precisam ficar
                                          idênticas para sempre.
      baseline_pit_meta                   quando, de qual commit, quantas linhas.

    Como rodar (do dbt_futebol/). O passo 1 é o que povoa o dataset de medição: com --target
    taskF todo `ref()` resolve para futebol_taskF, então a ancestria (staging + fact_fixtures +
    fact_standings_snapshot) tem de existir lá antes — o `+` no seletor é o que a constrói, lendo
    as sources cruas, que são fixas no dataset de origem e não seguem o target:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt run --target taskF \
        --select +int_futebol_team_form_pit

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_congela_baseline --vars '{freeze_git_sha: '"$(git rev-parse --short HEAD)"'}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_congela_baseline.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)
*/

CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_int_futebol_team_form_pit` AS
SELECT * EXCEPT (dbt_loaded_at)
FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`;


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_fingerprint` AS
WITH 

fp_fixtures_pit AS (
    SELECT
        competition_id,
        season,
        COUNT(*) AS n_fixtures,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
            fixture_id, competition, home_team_id, away_team_id,
            kickoff_utc, status_short, goals_home, goals_away
        )))) AS fp_fixtures
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    GROUP BY competition_id, season
),

-- Mesmo QUALIFY do modelo: o insumo que ele de fato lê, e não a tabela crua. O snapshot ganha
-- uma linha por dia por time, então digitalizar o cru mudaria todo dia e jogaria todas as
-- competições fora da comparação — a guarda passaria em branco.
fp_team_group_pit AS (
    SELECT league_id AS competition_id, season, team_id, group_name
    FROM `smartbetting-dados`.`futebol`.`fact_standings_snapshot`
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY league_id, season, team_id
        ORDER BY CASE WHEN group_name LIKE '%third-placed%' THEN 1 ELSE 0 END,
                 snapshot_date DESC
    ) = 1
),

fp_standings_pit AS (
    SELECT
        competition_id,
        season,
        COUNT(*) AS n_grupos,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(team_id, group_name)))) AS fp_standings
    FROM fp_team_group_pit
    GROUP BY competition_id, season
),

fp_insumo_pit AS (
    SELECT
        f.competition_id,
        f.season,
        f.n_fixtures,
        f.fp_fixtures,
        COALESCE(s.n_grupos, 0) AS n_grupos,
        s.fp_standings
    FROM fp_fixtures_pit f
    LEFT JOIN fp_standings_pit s USING (competition_id, season)
)


SELECT * FROM fp_insumo_pit;


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_meta` AS
SELECT
    CURRENT_TIMESTAMP()                          AS congelado_em,
    'desconhecido' AS git_sha,
    (SELECT COUNT(*) FROM `smartbetting-dados`.`futebol_taskF`.`baseline_int_futebol_team_form_pit`) AS n_linhas,
    (SELECT COUNT(*) FROM `smartbetting-dados`.`futebol_taskF`.`baseline_pit_fingerprint`)           AS n_particoes;