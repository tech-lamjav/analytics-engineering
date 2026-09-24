{#
    CONGELA UMA CÉLULA DO EIXO `pit_mando` (AE#200) — a metade de escrita da medição do campo
    neutro. A leitura é analyses/ae200_campo_neutro.sql.

    A pergunta: quanto classificar campo neutro no histórico (a regra da Copa: anfitrião no
    próprio país é casa, todo outro jogo de Copa é neutro) mexe no acendimento das 11 premissas
    de corte por mando e na faixa do Score. As duas células — `ambos` (produção) e
    `ambos_neutro_copa` — precisam vir da MESMA cadeia de upstream no `taskF`: se o
    fact_odds_snapshot ou o fact_fixtures fossem reconstruídos entre uma e outra, a diferença
    carregaria o rebuild dentro dela (a invariante que a Costura B da [F] guarda). Por isso o
    upstream é atualizado UMA vez, antes da primeira célula, e nunca entre as duas.

    ────────────────────────────────────────────────────────────────────────────────
    REPRODUÇÃO (target `taskF` SEMPRE — dev/prod apontam para o dataset do board, ADR 0007)

        cd dbt_futebol
        export DBT_PROFILES_DIR=..
        PREM="int_futebol_premissas_1x2 int_futebol_premissas_ah int_futebol_premissas_ou int_futebol_premissas_btts int_futebol_premissas_dc"

        # 0. upstream + célula de produção, UMA vez
        ../.venv/bin/dbt seed  --target taskF --select futebol_copa_mundo_sedes
        ../.venv/bin/dbt run   --target taskF --select +int_futebol_premissas_1x2 +int_futebol_premissas_ah \
            +int_futebol_premissas_ou +int_futebol_premissas_btts +int_futebol_premissas_dc
        ../.venv/bin/dbt compile --target taskF --select ae200_campo_neutro_celula
        bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae200_campo_neutro_celula.sql

        # 1. célula neutra: só o PIT e as premissas mudam
        ../.venv/bin/dbt run --target taskF --select int_futebol_team_form_pit $PREM --vars '{pit_mando: neutro_copa}'
        ../.venv/bin/dbt test --target taskF --select assert_copa_mundo_cidade_no_seed_de_sedes
        ../.venv/bin/dbt compile --target taskF --select ae200_campo_neutro_celula --vars '{pit_mando: neutro_copa}'
        bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/ae200_campo_neutro_celula.sql

        # 2. RESTAURA o taskF ao default — ele é compartilhado — e prova que o default não mexeu
        ../.venv/bin/dbt run  --target taskF --select int_futebol_team_form_pit $PREM
        ../.venv/bin/dbt test --target taskF --select assert_taskf_pit_default_igual_baseline

    ⚠️ `bq query < arquivo`, nunca com o SQL como argumento (trava).

    ────────────────────────────────────────────────────────────────────────────────
    O QUE É GRAVADO

    `ae200_celulas` — uma linha por (célula, mercado, fixture, outcome, linha) dos cinco modelos
    de premissa, com is_favorito (só no Handicap — é o que decide o lado na linha 0), pts_premissas, a penalidade de contexto do mercado, premissas_sem_dado e o
    array das premissas de corte por mando daquele mercado com o booleano de cada uma. Não é
    filtrada por preço: o acendimento mede-se sobre toda linha; a faixa, sobre as que tiveram
    preço, é a leitura que filtra (junta o funil).

    `ae200_pit` — played_neutro por (célula, fixture, time), de onde sai quem está EXPOSTO.

    A célula é rotulada por taskf_celula(), nunca à mão: o rótulo não tem como discordar do que
    rodou. Reescrever a mesma célula apaga a anterior (DELETE + INSERT), para a tabela nunca ter
    duas versões de uma célula.
#}
{#- Só na compilação de verdade: no parse (`execute` falso) o projeto inteiro é lido sob o
    target default, e a trava derrubaria o `dbt parse` de todo mundo. -#}
{%- if execute and target.name != 'taskF' -%}
    {{ exceptions.raise_compiler_error("ae200_campo_neutro_celula grava em futebol_taskF: compile com --target taskF.") }}
{%- endif -%}
{%- set c = taskf_celula() -%}
{%- set destino = 'smartbetting-dados.futebol_taskF' -%}

CREATE TABLE IF NOT EXISTS `{{ destino }}.ae200_celulas` (
    celula                       STRING,
    pit_mando                    STRING,
    market                       STRING,
    fixture_id                   INT64,
    competition                  STRING,
    outcome                      STRING,
    line_value                   FLOAT64,
    is_favorito                  BOOL,
    pts_premissas                INT64,
    penalidades_especificas_pts  INT64,
    premissas_sem_dado           INT64,
    premissas                    ARRAY<STRUCT<premissa STRING, acendeu BOOL>>,
    gravado_em                   TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `{{ destino }}.ae200_pit` (
    celula         STRING,
    fixture_id     INT64,
    team_id        INT64,
    played_neutro  INT64,
    gravado_em     TIMESTAMP
);

DELETE FROM `{{ destino }}.ae200_celulas` WHERE celula = '{{ c.nome }}';
DELETE FROM `{{ destino }}.ae200_pit`     WHERE celula = '{{ c.nome }}';

INSERT INTO `{{ destino }}.ae200_celulas`
-- As 11 premissas de corte por mando, por mercado (levantamento da AE#200, conferido no código
-- em 24/09: a `lado_coberto_forte` da Dupla Chance herda o `forca_mismatch` do 1X2 e entra).
-- ⚠️ `defesas_vazaveis` é a de GOLS — a homônima do BTTS usa clean sheet total e não passa
-- pelo corte por mando.
SELECT '{{ c.nome }}', '{{ c.mando }}', 'match_winner', fixture_id, competition, outcome,
       CAST(NULL AS FLOAT64), CAST(NULL AS BOOL), pts_premissas, penalidades_1x2_pts, premissas_sem_dado,
       [STRUCT('forca_mismatch' AS premissa, forca_mismatch AS acendeu),
        STRUCT('mando', mando)],
       CURRENT_TIMESTAMP()
FROM {{ ref('int_futebol_premissas_1x2') }}
UNION ALL
SELECT '{{ c.nome }}', '{{ c.mando }}', 'asian_handicap', fixture_id, competition, outcome,
       CAST(line_value AS FLOAT64), is_favorito, pts_premissas, penalidades_ah_pts, premissas_sem_dado,
       [STRUCT('tende_golear' AS premissa, tende_golear AS acendeu),
        STRUCT('adversario_fragil_fora', adversario_fragil_fora),
        STRUCT('mando_forte', mando_forte),
        STRUCT('defesa_fora_solida', defesa_fora_solida)],
       CURRENT_TIMESTAMP()
FROM {{ ref('int_futebol_premissas_ah') }}
UNION ALL
SELECT '{{ c.nome }}', '{{ c.mando }}', 'goals_over_under', fixture_id, competition, outcome,
       CAST(line_value AS FLOAT64), CAST(NULL AS BOOL), pts_premissas, penalidades_ou_pts, premissas_sem_dado,
       [STRUCT('ataque_combinado' AS premissa, ataque_combinado AS acendeu),
        STRUCT('defesas_vazaveis', defesas_vazaveis),
        STRUCT('defesas_firmes', defesas_firmes)],
       CURRENT_TIMESTAMP()
FROM {{ ref('int_futebol_premissas_ou') }}
UNION ALL
SELECT '{{ c.nome }}', '{{ c.mando }}', 'btts', fixture_id, competition, outcome,
       CAST(NULL AS FLOAT64), CAST(NULL AS BOOL), pts_premissas, penalidades_btts_pts, premissas_sem_dado,
       [STRUCT('ataque_dos_dois' AS premissa, ataque_dos_dois AS acendeu)],
       CURRENT_TIMESTAMP()
FROM {{ ref('int_futebol_premissas_btts') }}
UNION ALL
SELECT '{{ c.nome }}', '{{ c.mando }}', 'double_chance', fixture_id, competition, outcome,
       CAST(NULL AS FLOAT64), CAST(NULL AS BOOL), pts_premissas, penalidades_dc_pts, premissas_sem_dado,
       [STRUCT('lado_coberto_forte' AS premissa, lado_coberto_forte AS acendeu)],
       CURRENT_TIMESTAMP()
FROM {{ ref('int_futebol_premissas_dc') }};

INSERT INTO `{{ destino }}.ae200_pit`
SELECT '{{ c.nome }}', fixture_id, team_id, played_neutro, CURRENT_TIMESTAMP()
FROM {{ ref('int_futebol_team_form_pit') }};
