/*
    [F-1] Congela o BASELINE da Costura A — a saída do int_futebol_team_form_pit ANTES de a var
    de escopo/recorte entrar no modelo.

    Por que existe: a ADR 0007 deixa no código de produção uma var que produção nunca usa. A
    promessa que a acompanha é "o default preserva o comportamento de hoje". Este congelamento é
    o lado esquerdo da igualdade que transforma essa promessa em fato verificável — o direito é
    tests/assert_taskf_pit_default_igual_baseline.sql.

    ⚠️ NÃO É PASSO DE ROTINA. Re-congelar sem uma mudança de comportamento que o justifique apaga
    a guarda: o baseline passaria a sair do mesmo código que ele deveria auditar, e a Costura A
    ficaria verde por construção. Re-congelar é decisão de quem revisa, no mesmo commit da
    mudança que a justifica — nunca um passo executado porque a guarda ficou vermelha.

    RODADO DUAS VEZES, e a segunda mudou o sentido da guarda:

      2026-08-12 12:22 UTC, commit a3b954e, 21.054 linhas, 37 partições — do `futebol_taskF`,
      célula `base`. Congelava "o default preserva o comportamento de antes das vars".

      2026-08-25 17:59 UTC, commit 887a1f9, 21.078 linhas, 37 partições — **de PRODUÇÃO**, passo
      de deploy da #91. A #91 (ADR 0010) virou os defaults para `todas` + `ultimos_10` e produção
      passou a USAR o default: a premissa antiga morreu por decisão no mesmo commit em que deixou
      de ser desejável. A guarda deixou de ser de vazamento-de-andaime e virou guarda de DERIVA
      sobre o caminho que o board de fato serve. O baseline anterior ficou preservado nas cópias
      `baseline_*_pre91` do mesmo dataset.

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

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target prod \
        --select taskf_congela_baseline --vars '{freeze_git_sha: <sha da imagem em produção>}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_congela_baseline.sql

    O `freeze_git_sha` é o `PROCEDENCIA_SHA` do job — o commit que PRODUZIU a tabela —, nunca o
    `git rev-parse HEAD` local: de um worktree ele carimba um commit que nem está no master.

    Depois, a verificação que fecha o passo:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt test --target prod \
        --select assert_taskf_pit_default_igual_baseline

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)
*/

CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_int_futebol_team_form_pit` AS
SELECT * EXCEPT (dbt_loaded_at)
FROM {{ ref('int_futebol_team_form_pit') }};


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_fingerprint` AS
WITH {{ taskf_fingerprint_insumo_pit() }}
SELECT * FROM fp_insumo_pit;


CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.baseline_pit_meta` AS
SELECT
    CURRENT_TIMESTAMP()                          AS congelado_em,
    '{{ var("freeze_git_sha", "desconhecido") }}' AS git_sha,
    (SELECT COUNT(*) FROM {{ source('futebol_taskF', 'baseline_int_futebol_team_form_pit') }}) AS n_linhas,
    (SELECT COUNT(*) FROM {{ source('futebol_taskF', 'baseline_pit_fingerprint') }})           AS n_particoes;
