/*
    [F-1] Congela o BASELINE da Costura A — a saída de PRODUÇÃO do int_futebol_team_form_pit, e a
    impressão digital do insumo que a produziu.

    O lado esquerdo da igualdade que a guarda tests/assert_taskf_pit_default_igual_baseline.sql
    verifica do lado direito: a saída não se mexe nas linhas cujo insumo não se mexeu.

    ⚠️ NÃO É PASSO DE ROTINA. Re-congelar sem uma mudança de comportamento que o justifique apaga
    a guarda: o baseline passaria a sair do mesmo código que ele deveria auditar, e a Costura A
    ficaria verde por construção. Re-congelar é decisão de quem revisa, no mesmo commit da
    mudança que a justifica — nunca um passo executado porque a guarda ficou vermelha.

    RODADO TRÊS VEZES, e cada uma está registrada porque cada uma mudou o que a guarda quer dizer:

      2026-08-12 12:22 UTC, commit a3b954e, 21.054 linhas, 37 partições — do `futebol_taskF`,
      célula `base`. Congelava "o default preserva o comportamento de antes das vars".

      2026-08-25 17:59 UTC, commit 887a1f9, 21.078 linhas, 37 partições — **de PRODUÇÃO**, passo
      de deploy da #91. A #91 (ADR 0010) virou os defaults para `todas` + `ultimos_10` e produção
      passou a USAR o default: a premissa antiga morreu por decisão no mesmo commit em que deixou
      de ser desejável. A guarda deixou de ser de vazamento-de-andaime e virou guarda de DERIVA
      sobre o caminho que o board de fato serve. O baseline anterior ficou preservado nas cópias
      `baseline_*_pre91` do mesmo dataset.

      2026-08-28 14:25:03 UTC, carimbo 687950f, 21.374 linhas (#123) — **de PRODUÇÃO**, mesmo
      sentido, RECORTE NOVO. A digital do insumo deixou de ser por (competition_id, season) e passou
      a ser por LINHA (fixture_id, team_id), porque a partição parou de ser o fecho da conta quando
      a #91 virou o default para `todas`. Sem este recongelamento no mesmo commit, nenhuma linha
      casaria contra a digital antiga e a guarda não ficaria vermelha: ficaria VAZIA.

      A defasagem T0→T1 (ver o aviso mais abaixo) foi de 24 minutos: a materialização de produção
      do `int_futebol_team_form_pit` é de 14:01:12 UTC, com as mesmas 21.374 linhas. A guarda,
      rodada em seguida, ficou VERDE com cobertura 1,0 — 21.374 de 21.374.

    ─────────────────────────────────────────────────────────────────────────────────────────────
    Tabelas gravadas, todas FORA do dbt de propósito — nenhuma é modelo, então nenhum `dbt run` as
    reconstrói:

      baseline_int_futebol_team_form_pit  a saída congelada, sem dbt_loaded_at (que muda a cada
                                          build por construção e não é comportamento).

      baseline_pit_fingerprint_linha      impressão digital do INSUMO por (fixture_id, team_id),
                                          emitida pela macro taskf_fingerprint_insumo_pit — a
                                          MESMA que a guarda usa. O contrato congelado dela está no
                                          cabeçalho da macro; as duas pontas leem de lá justamente
                                          para não haver duas cópias que precisam ficar idênticas
                                          para sempre.

      baseline_pit_meta                   quando, de qual commit, quantas linhas.

    ⚠️ `baseline_pit_fingerprint` (a digital ANTIGA, por partição) não é mais escrita nem lida.
    A tabela fica no dataset como registro histórico, pelo mesmo precedente das cópias
    `baseline_*_pre91` — o que sai é a declaração dela em sources.yml, porque source que ninguém lê
    é convite a alguém voltar a lê-la.

    ─────────────────────────────────────────────────────────────────────────────────────────────
    ⚠️ COMO RODAR: `--target prod`, NÃO `--target taskF`. As três tabelas de baseline moram no
    `futebol_taskF` porque são artefato da medição (os nomes acima são literais e não seguem o
    target), mas o que elas congelam tem de sair de PRODUÇÃO. Congelar a partir do `futebol_taskF`
    carimbaria o baseline de produção com os fatos parados do dataset de medição — pior que não
    recongelar, e foi por isso que a receita anterior (`--target taskF`, com um `dbt run
    --select +int_futebol_team_form_pit` antes para povoar a ancestria) saiu daqui.

    Não há `dbt run` nenhum neste caminho: o `int_futebol_team_form_pit` de produção é `table` e
    já está materializado pelo agendado. O que se congela é a saída que o board serve, não uma
    reconstrução local dela. Confira antes que ela é pós-deploy da mudança que justifica o
    recongelamento (`futebol.__TABLES__.last_modified_time` contra o carimbo do Cloud Run job).

    ⚠️ DEFASAGEM ENTRE OS DOIS LADOS DO CONGELAMENTO. A saída congelada é a materialização de
    produção (instante T0, do último `dbt run` agendado); a digital é calculada AGORA, das fontes
    vivas (instante T1). Linha cujo insumo se mexeu dentro de [T0, T1] congela com o par
    desencontrado e fica vermelha até alguém recongelar. Por isso: congelar logo depois de uma
    execução agendada, rodar a guarda nos minutos seguintes, e recongelar se aparecerem
    divergências — é a mesma disciplina do congelamento de 25/08.

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target prod \
        --select taskf_congela_baseline --vars '{freeze_git_sha: <sha da imagem em producao>}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_congela_baseline.sql

    O `freeze_git_sha` é o `PROCEDENCIA_SHA` do job — o commit que PRODUZIU a tabela —, nunca o
    `git rev-parse HEAD` local: de um worktree ele carimba um commit que nem está no master.

      gcloud run jobs describe dbt-futebol --region us-east1 \
        --format="value(spec.template.spec.template.spec.containers[0].env)" | tr ';' '\n' \
        | grep PROCEDENCIA_SHA

    Depois, a verificação que fecha o passo:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt test --target prod \
        --select assert_taskf_pit_default_igual_baseline

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)
*/

CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_int_futebol_team_form_pit` AS
SELECT * EXCEPT (dbt_loaded_at)
FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`;


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_fingerprint_linha` AS
WITH 

fp_fixtures_base AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc,
        status_short, score_fulltime_home, score_fulltime_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- O grão de saída do modelo: os dois lados de cada jogo, inclusive jogo futuro.
fp_targets AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           home_team_id AS team_id, away_team_id AS adversario_id
    FROM fp_fixtures_base
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           away_team_id, home_team_id
    FROM fp_fixtures_base
),

-- Mesma definição de "partida encerrada" do modelo (#71: AET/PEN entram), e mesmo par
-- (time, jogo). `fixture_id` entra na digital porque BIT_XOR de dois structs idênticos se
-- CANCELA: dois jogos com o mesmo placar, mesmo mando e mesmo kickoff sumiriam da impressão.
fp_team_log AS (
    SELECT fixture_id, competition_id, season, kickoff_utc,
           home_team_id AS team_id, TRUE AS is_home,
           score_fulltime_home AS gf, score_fulltime_away AS ga
    FROM fp_fixtures_base
    WHERE 
    status_short IN ('FT', 'AET', 'PEN')
      AND score_fulltime_home IS NOT NULL
      AND score_fulltime_away IS NOT NULL
    UNION ALL
    SELECT fixture_id, competition_id, season, kickoff_utc,
           away_team_id, FALSE,
           score_fulltime_away, score_fulltime_home
    FROM fp_fixtures_base
    WHERE 
    status_short IN ('FT', 'AET', 'PEN')
      AND score_fulltime_home IS NOT NULL
      AND score_fulltime_away IS NOT NULL
),

-- (2) e (3) do fecho: os 10 anteriores do TIME em qualquer competição, e a contagem SEM teto.
-- O COUNT é window (avaliado antes do QUALIFY), igual ao `played_disponivel` do modelo.
fp_hist_time_pares AS (
    SELECT
        t.fixture_id,
        t.team_id,
        l.fixture_id     AS log_fixture_id,
        l.competition_id AS log_competition_id,
        l.season         AS log_season,
        l.kickoff_utc    AS log_kickoff_utc,
        l.is_home,
        l.gf,
        l.ga,
        COUNT(l.fixture_id) OVER (PARTITION BY t.fixture_id, t.team_id) AS n_hist_time_disponivel
    FROM fp_targets t
    LEFT JOIN fp_team_log l
        ON  l.team_id     = t.team_id
        AND l.kickoff_utc < t.kickoff_utc
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY t.fixture_id, t.team_id
        ORDER BY l.kickoff_utc DESC
    ) <= 10
),

fp_hist_time AS (
    SELECT
        fixture_id,
        team_id,
        MAX(n_hist_time_disponivel) AS n_hist_time_disponivel,
        COUNT(log_fixture_id)       AS n_hist_time_usado,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
            log_fixture_id, log_competition_id, log_season,
            log_kickoff_utc, is_home, gf, ga
        ))))                        AS fp_hist_time
    FROM fp_hist_time_pares
    GROUP BY fixture_id, team_id
),

-- (4) do fecho: os jogos anteriores da COMPETIÇÃO/temporada da âncora, de TODOS os times. É o
-- insumo do CTE `tabela` (ADR 0008) e portanto de points/goal_diff/ppg — e do `rank` de T, que
-- ranqueia contra os adversários de grupo. Por ÂNCORA: as duas linhas do jogo dividem o valor.
fp_hist_comp_por_ancora AS (
    SELECT
        a.fixture_id,
        COUNT(l.fixture_id) AS n_hist_comp,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
            l.fixture_id, l.team_id, l.is_home, l.gf, l.ga, l.kickoff_utc
        ))))                AS fp_hist_comp
    FROM fp_fixtures_base a
    LEFT JOIN fp_team_log l
        ON  l.competition_id = a.competition_id
        AND l.season         = a.season
        AND l.kickoff_utc    < a.kickoff_utc
    GROUP BY a.fixture_id
),

-- (5a) do fecho: o ELENCO de (C,S) — conjunto DISTINTO de team_id, nunca de fixtures. Ver o
-- cabeçalho: é o único insumo que lê o futuro, e digitalizá-lo como fixtures reproduziria a
-- armadilha do recorte "por time".
fp_roster AS (
    SELECT
        competition_id,
        season,
        COUNT(*)                                                   AS n_roster,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(team_id)))) AS fp_roster
    FROM (SELECT DISTINCT competition_id, season, team_id FROM fp_targets)
    GROUP BY competition_id, season
),

-- (5b) do fecho: o grupo de cada time, com o MESMO QUALIFY do modelo.
fp_team_group AS (
    SELECT league_id AS competition_id, season, team_id, group_name
    FROM `smartbetting-dados`.`futebol`.`fact_standings_snapshot`
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY league_id, season, team_id
        ORDER BY CASE WHEN group_name LIKE '%third-placed%' THEN 1 ELSE 0 END,
                 snapshot_date DESC
    ) = 1
),

fp_standings AS (
    SELECT
        competition_id,
        season,
        COUNT(*) AS n_grupos,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(team_id, group_name)))) AS fp_standings
    FROM fp_team_group
    GROUP BY competition_id, season
),

fp_insumo_por_linha AS (
    SELECT
        t.fixture_id,
        t.team_id,
        t.competition_id,
        t.season,

        -- (1) a âncora, SEM status/placar dela — ver o cabeçalho.
        FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
            t.fixture_id, t.competition, t.competition_id, t.season,
            t.kickoff_utc, t.team_id, t.adversario_id
        )))                                   AS fp_ancora,

        COALESCE(h.n_hist_time_disponivel, 0) AS n_hist_time_disponivel,
        COALESCE(h.n_hist_time_usado, 0)      AS n_hist_time_usado,
        h.fp_hist_time,

        COALESCE(c.n_hist_comp, 0)            AS n_hist_comp,
        c.fp_hist_comp,

        COALESCE(r.n_roster, 0)               AS n_roster,
        r.fp_roster,

        COALESCE(s.n_grupos, 0)               AS n_grupos,
        s.fp_standings,

        -- A digital combinada. TO_JSON_STRING de STRUCT é determinístico e distingue NULL de
        -- ausente, então o join da guarda é UMA igualdade — e a diagnose fica nas colunas acima,
        -- que dizem QUAL dos cinco insumos se mexeu.
        FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
            t.fixture_id, t.competition, t.competition_id, t.season,
            t.kickoff_utc, t.team_id, t.adversario_id,
            COALESCE(h.n_hist_time_disponivel, 0),
            COALESCE(h.n_hist_time_usado, 0),
            h.fp_hist_time,
            COALESCE(c.n_hist_comp, 0),
            c.fp_hist_comp,
            COALESCE(r.n_roster, 0),
            r.fp_roster,
            COALESCE(s.n_grupos, 0),
            s.fp_standings
        )))                                   AS fp_insumo_linha

    FROM fp_targets t
    LEFT JOIN fp_hist_time h
        ON  h.fixture_id = t.fixture_id AND h.team_id = t.team_id
    LEFT JOIN fp_hist_comp_por_ancora c
        ON  c.fixture_id = t.fixture_id
    LEFT JOIN fp_roster r
        ON  r.competition_id = t.competition_id AND r.season = t.season
    LEFT JOIN fp_standings s
        ON  s.competition_id = t.competition_id AND s.season = t.season
)


SELECT * FROM fp_insumo_por_linha;


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_meta` AS
SELECT
    CURRENT_TIMESTAMP()                          AS congelado_em,
    'desconhecido' AS git_sha,
    (SELECT COUNT(*) FROM `smartbetting-dados`.`futebol_taskF`.`baseline_int_futebol_team_form_pit`) AS n_linhas,
    -- ⚠️ Era `n_particoes` até a #123, quando a digital passou a ser por linha. O nome mudou junto
    -- com o grão: uma coluna chamada "partições" contando linhas é a mesma classe de rótulo
    -- mentiroso que o recorte antigo era.
    (SELECT COUNT(*) FROM `smartbetting-dados`.`futebol_taskF`.`baseline_pit_fingerprint_linha`)     AS n_linhas_digital;