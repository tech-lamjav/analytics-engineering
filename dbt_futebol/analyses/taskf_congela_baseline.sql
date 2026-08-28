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
FROM {{ ref('int_futebol_team_form_pit') }};


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_fingerprint_linha` AS
WITH {{ taskf_fingerprint_insumo_pit() }}
SELECT * FROM fp_insumo_por_linha;


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_meta` AS
SELECT
    CURRENT_TIMESTAMP()                          AS congelado_em,
    '{{ var("freeze_git_sha", "desconhecido") }}' AS git_sha,
    (SELECT COUNT(*) FROM {{ source('futebol_taskF', 'baseline_int_futebol_team_form_pit') }}) AS n_linhas,
    -- ⚠️ Era `n_particoes` até a #123, quando a digital passou a ser por linha. O nome mudou junto
    -- com o grão: uma coluna chamada "partições" contando linhas é a mesma classe de rótulo
    -- mentiroso que o recorte antigo era.
    (SELECT COUNT(*) FROM {{ source('futebol_taskF', 'baseline_pit_fingerprint_linha') }})     AS n_linhas_digital;
