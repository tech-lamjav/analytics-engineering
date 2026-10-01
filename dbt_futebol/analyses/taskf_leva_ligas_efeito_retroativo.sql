{#
    O PORTÃO DA LEVA DE LIGAS (Argentina 128, Colômbia 239, Peru 281, Liga MX 262) — antes do primeiro
    backfill, no molde da DE#95 (analyses/taskf_amistosos_efeito_retroativo_95.sql).

    Mede o deslocamento RETROATIVO que cadastrar as 4 ligas causaria no histórico PIT
    (`int_futebol_team_form_pit`, célula de produção `pit_escopo=todas`, `pit_recorte=ultimos_10`)
    de clubes JÁ medidos no mart: 44 clubes de AR/CO/PE jogam Libertadores (13) e Sudamericana (11)
    (medido sobre o raw em 29/09 — 22 da 128, 11 da 239, 11 da 281), e a forma PIT atravessa
    competição desde a #91/ADR 0010, então os jogos de liga doméstica passariam a entrar nos
    "últimos 10" de âncoras de Lib/Sud já medidas. Nenhum clube mexicano joga Lib/Sud: a Liga MX
    (262) tem efeito ZERO por construção sobre âncoras de Lib/Sud, e sai na matriz como linha de
    n_ancoras = 0 — está lá para o zero ficar registrado, não presumido.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE ESTE ARQUIVO NÃO RODA SOZINHO

    A comparação é ANTES × DEPOIS do mesmo modelo, e as versões vivem no MESMO dataset (`taskF`),
    uma de cada vez — o modelo só existe uma vez lá. Então cada versão é MATERIALIZADA e copiada
    para uma tabela `leva8_pit_*` antes de esta query rodar. Três tabelas:

        leva8_pit_antes       build default (sem as ligas)              — a referência
        leva8_pit_2026        --vars "{taskf_incluir_ligas_leva: '2026'}"        — cenário "só a temporada corrente"
        leva8_pit_2025_2026   --vars "{taskf_incluir_ligas_leva: '2025_2026'}"   — cenário "backfill 25 + corrente"

    Os fixtures das 4 ligas NÃO estão no landing e NUNCA podem ir para lá (gs://…/futebol/fixtures/
    é uma tabela externa wildcard: o próximo diário publicaria as ligas em produção com
    competition='unknown'). A única fonte é a tabela nativa `futebol_taskF.leva8_raw_fixtures`,
    carregada de JSONs em cache da API, e é ela que a var `taskf_incluir_ligas_leva` do
    stg_futebol_fixtures.sql une à fonte (UNION ALL). Aspas no valor são obrigatórias:
    `2025_2026` sem aspas vira o inteiro 20252026 no YAML de --vars e o build FALHA de propósito.

    ⚠️ `--full-refresh` NÃO É OPCIONAL em nenhum dos quatro builds abaixo. `fact_fixtures` é
    incremental por MERGE com anti-join em `extracted_at` (fact_fixtures.sql:186-191) e um MERGE
    nunca apaga: construir um cenário e depois "restaurar o default" SEM --full-refresh deixa as
    linhas da leva dentro de `futebol_taskF.fact_fixtures`, e elas vazam para a medição seguinte
    (a sua, a de outra célula, a do próximo). `--exclude-resource-type test unit_test`: os testes
    genéricos de fact_fixtures têm `accepted_values` em `competition` e as linhas novas saem com
    'unknown' (o CASE de fact_fixtures.sql não tem as 4 ligas — de propósito, ver abaixo); os unit
    tests não medem nada aqui.

    ANTES de cada build, confira em INFORMATION_SCHEMA.JOBS_BY_PROJECT (região us-east1) que
    ninguém escreveu em `futebol_taskF` nos últimos 60 minutos — o taskF é compartilhado.
    (Só `dbt run` ESCREVE; nunca sem `--target taskF`: dev e prod apontam para o dataset de
    produção `futebol`.)

        cd dbt_futebol

        # 1. ANTES — default
        DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
          --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit \
          --full-refresh --exclude-resource-type test unit_test
        bq query --use_legacy_sql=false < leva8_ctas_antes.sql

        # 2. DEPOIS_2026
        DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
          --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit \
          --full-refresh --exclude-resource-type test unit_test \
          --vars "{taskf_incluir_ligas_leva: '2026'}"
        bq query --use_legacy_sql=false < leva8_ctas_2026.sql

        # 3. DEPOIS_2526
        DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
          --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit \
          --full-refresh --exclude-resource-type test unit_test \
          --vars "{taskf_incluir_ligas_leva: '2025_2026'}"
        bq query --use_legacy_sql=false < leva8_ctas_2025_2026.sql

        # 4. RESTAURAR o taskF ao default (mesmo comando do passo 1, sem var, COM --full-refresh)
        DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
          --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit \
          --full-refresh --exclude-resource-type test unit_test

    Os três arquivos .sql dos `bq query` têm uma linha cada (o nome da tabela muda):

        CREATE OR REPLACE TABLE `smartbetting-dados.futebol_taskF.leva8_pit_antes`
        AS SELECT * FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`;
        -- leva8_pit_2026        e        leva8_pit_2025_2026    nos outros dois

    (Os `bq query` usam SQL de arquivo por stdin — `bq query < arquivo.sql` —, não como argumento.)
    Conferência do restauro: `SELECT COUNT(*) FROM futebol_taskF.fact_fixtures WHERE competition_id
    IN (128, 239, 281, 262)` tem de dar 0.

    ────────────────────────────────────────────────────────────────────────────────
    A MÉTRICA — E POR QUE ELA NÃO É A UNIDADE DA RÉGUA

    A régua herdada é 0,25 pp (#92). O nível mecânico medido aqui é a taxa de vitória PIT —
    `wins_total / played_total`, em pontos percentuais — comparada linha a linha por
    (fixture_id, team_id). NÃO é a unidade da régua: a régua de 0,25 pp calibra `aconteceu_p*` de
    premissa (Teste 2), e rodar as 5 famílias de premissas nos três cenários para produzir o
    número exato na mesma unidade fica fora deste portão por custo (mesma decisão da DE#95).
    Quando `played_total` vai de 0 (ou de poucos jogos) para vários, a premissa sai de "não avalia"
    (piso de amostra não bate) para "avalia" — isso É o deslocamento, não uma aproximação dele.

    Convenções (as do molde): o módulo do delta de taxa trata "sem histórico" (played_total = 0,
    taxa NULL) como 0 pp dos dois lados; `mediana_pp_winrate` é a mediana desse MÓDULO (APPROX_QUANTILES
    de 2 buckets, como na DE#95), não a mediana do delta com sinal.

    Colunas de cada célula:

        n_ancoras                  linhas (fixture, time) da célula COM par nas duas tabelas
        n_sem_par                  linhas da célula presentes no "antes" e ausentes no "depois" — o
                                   raw andou entre os builds (ver o controle); fora de TODAS as outras métricas
        n_sem_historico_antes      played_total = 0 antes
        n_ganhou_historico_do_zero played_total = 0 antes e > 0 depois
        n_last10_mudou             QUALQUER destes difere: played_total_disponivel, played_total, wins_total,
                                   draws_total, goals_for_avg_total, goals_against_avg_total, clean_sheet_total,
                                   failed_to_score_total, form_last5. A tabela não expõe a lista dos 10 jogos,
                                   então "os 10 mudaram" é inferido desses agregados — pode SUBcontar (10 jogos
                                   diferentes com o mesmo resumo), nunca sobrecontar.
        delta_medio_played_total   média de (played_total depois − antes); satura em 10 pelo recorte
        delta_medio_pp_winrate     média do MÓDULO do delta da taxa de vitória, em pp
        mediana_pp_winrate         mediana desse módulo
        max_pp_winrate             máximo desse módulo
        n_cruzou_piso_5            played_total_disponivel < 5 antes e >= 5 depois. A coluna do piso é
                                   `played_total_disponivel` (a contagem SEM o teto do recorte), NÃO `played_total`
                                   (satura em 10): macros/task01_base.sql:217 escolhe `played_total_disponivel`
                                   quando o recorte é `ultimos_10`, o default de produção.

    Eixos da matriz:

      cenario      2026 | 2025_2026
      janela       congelada [2026-06-16, 2026-08-04 12:00 UTC)   — o universo congelado da [F]/âncora
                   nova      [2026-08-04 12:00, 2026-10-01 00:00 UTC)
                   toda      sem limite de data (toda a Lib/Sud; no controle 'controle_outras', todo o período)
                   sobre o kickoff_utc da ÂNCORA.
      liga_origem  a liga da leva de onde o clube afetado vem — 128 | 239 | 281 | 262 — pelo conjunto de times
                   que aparece nos fixtures da leva NAQUELE cenário (só a season 2026 no cenário 2026; 2025 e
                   2026 no 2025_2026). Só âncoras de Lib/Sud (competition_id 13 e 11) entram nessas linhas.
                   Nenhum clube está em duas ligas da leva (medido: 0). O crosswalk de team_id (seed
                   team_id_aliases, só 22722→132, Chapecoense) não toca time algum da leva (medido: 0 ids
                   22722/132 nos fixtures da leva), então o id do raw da leva é o do PIT.
                   afetado_fora_lib_sud  clube da leva com âncora em OUTRA competição (deveria ser 0 linhas).
      universo     todos      todo jogo de Lib/Sud (13 e 11)
                   precificados  o fixture tem alguma linha em futebol.fact_odds_snapshot

    GRUPO DE CONTROLE (obrigatório). Pares (fixture, time) cujo time NÃO pertence a nenhuma das 4 ligas
    no cenário só podem ter delta EXATAMENTE 0: as ligas novas não lhes acrescentam jogo nenhum. Qualquer
    coisa diferente de 0 ali é DRIFT DE RAW ENTRE BUILDS — o fixtures-live roda a cada 15 minutos e o
    raw é append-only, então entre o build do "antes" e o dos "depois" placares e jogos novos entram —,
    NÃO efeito das ligas. Saem duas linhas de controle por célula (`controle_lib_sud`: as mesmas âncoras
    de Lib/Sud dos clubes de fora da leva; `controle_outras`: todas as âncoras de outras competições,
    onde `toda` = todo o histórico) e a coluna `observacao` acende AVISO quando o controle não dá 0 (ou
    quando qualquer linha tem n_sem_par > 0). Célula com AVISO: os números das linhas `128|239|281`
    da mesma célula NÃO são confiáveis até o build ser refeito.

    O que este arquivo NÃO faz: não decide nada. Devolve o deslocamento medido contra a régua herdada.
#}

WITH janelas AS (
    SELECT * FROM UNNEST([
        STRUCT('congelada' AS janela, TIMESTAMP('2026-06-16 00:00:00+00') AS ini, TIMESTAMP('2026-08-04 12:00:00+00') AS fim),
        STRUCT('nova',                TIMESTAMP('2026-08-04 12:00:00+00'),         TIMESTAMP('2026-10-01 00:00:00+00')),
        STRUCT('toda',                CAST(NULL AS TIMESTAMP),                     CAST(NULL AS TIMESTAMP))
    ])
),

-- Universo "precificados": o fixture tem ALGUMA linha no snapshot de odds.
precificados AS (
    SELECT DISTINCT fixture_id FROM `smartbetting-dados.futebol.fact_odds_snapshot`
),

antes AS (
    SELECT * FROM `smartbetting-dados.futebol_taskF.leva8_pit_antes`
),

depois AS (
    SELECT '2026'      AS cenario, p.* FROM `smartbetting-dados.futebol_taskF.leva8_pit_2026`      p
    UNION ALL
    SELECT '2025_2026' AS cenario, p.* FROM `smartbetting-dados.futebol_taskF.leva8_pit_2025_2026` p
),

-- Os times de cada liga da leva, POR CENÁRIO, tirados dos fixtures que o cenário carrega.
lados_leva AS (
    SELECT requested_league_id AS liga, requested_season AS season, teams.home.id AS team_id
    FROM `smartbetting-dados.futebol_taskF.leva8_raw_fixtures`
    UNION ALL
    SELECT requested_league_id, requested_season, teams.away.id
    FROM `smartbetting-dados.futebol_taskF.leva8_raw_fixtures`
),

mapa AS (
    SELECT '2026' AS cenario, team_id, MIN(liga) AS liga_origem
    FROM lados_leva WHERE season = 2026 GROUP BY team_id
    UNION ALL
    SELECT '2025_2026', team_id, MIN(liga)
    FROM lados_leva WHERE season IN (2025, 2026) GROUP BY team_id
),

-- Uma linha por (cenário, âncora, time) do "antes". As âncoras das próprias ligas novas não existem
-- no "antes" (raw sem elas) — o filtro de competition_id é cinto e suspensório.
comparado AS (
    SELECT
        cen                                                           AS cenario,
        a.fixture_id,
        a.team_id,
        a.kickoff_utc,
        CASE
            WHEN m.liga_origem IS NOT NULL AND a.competition_id IN (13, 11) THEN CAST(m.liga_origem AS STRING)
            WHEN m.liga_origem IS NOT NULL                                  THEN 'afetado_fora_lib_sud'
            WHEN a.competition_id IN (13, 11)                               THEN 'controle_lib_sud'
            ELSE                                                                 'controle_outras'
        END                                                           AS grupo,
        d.fixture_id IS NOT NULL                                      AS tem_par,
        a.played_total                                                AS pt_antes,
        d.played_total                                                AS pt_depois,
        a.played_total_disponivel                                     AS pd_antes,
        d.played_total_disponivel                                     AS pd_depois,
        SAFE_DIVIDE(a.wins_total, a.played_total) * 100               AS winrate_antes,
        SAFE_DIVIDE(d.wins_total, d.played_total) * 100               AS winrate_depois,
        (   a.played_total_disponivel  IS DISTINCT FROM d.played_total_disponivel
         OR a.played_total             IS DISTINCT FROM d.played_total
         OR a.wins_total               IS DISTINCT FROM d.wins_total
         OR a.draws_total              IS DISTINCT FROM d.draws_total
         OR a.goals_for_avg_total      IS DISTINCT FROM d.goals_for_avg_total
         OR a.goals_against_avg_total  IS DISTINCT FROM d.goals_against_avg_total
         OR a.clean_sheet_total        IS DISTINCT FROM d.clean_sheet_total
         OR a.failed_to_score_total    IS DISTINCT FROM d.failed_to_score_total
         OR a.form_last5               IS DISTINCT FROM d.form_last5
        )                                                             AS mudou,
        a.fixture_id IN (SELECT fixture_id FROM precificados)         AS precificado
    FROM antes a
    CROSS JOIN UNNEST(['2026', '2025_2026']) AS cen
    LEFT JOIN depois d
        ON  d.cenario    = cen
        AND d.fixture_id = a.fixture_id
        AND d.team_id    = a.team_id
    LEFT JOIN mapa m
        ON  m.cenario = cen
        AND m.team_id = a.team_id
    WHERE a.competition_id NOT IN (128, 239, 281, 262)
),

celulas AS (
    SELECT
        x.cenario,
        j.janela,
        x.grupo,
        u AS universo,
        COUNTIF(x.tem_par)                                                          AS n_ancoras,
        COUNTIF(NOT x.tem_par)                                                      AS n_sem_par,
        COUNTIF(x.tem_par AND x.pt_antes = 0)                                       AS n_sem_historico_antes,
        COUNTIF(x.tem_par AND x.pt_antes = 0 AND x.pt_depois > 0)                   AS n_ganhou_historico_do_zero,
        COUNTIF(x.tem_par AND x.mudou)                                              AS n_last10_mudou,
        ROUND(AVG(IF(x.tem_par, x.pt_depois - x.pt_antes, NULL)), 2)                AS delta_medio_played_total,
        ROUND(AVG(IF(x.tem_par, ABS(COALESCE(x.winrate_depois, 0) - COALESCE(x.winrate_antes, 0)), NULL)), 2)
                                                                                    AS delta_medio_pp_winrate,
        ROUND(APPROX_QUANTILES(IF(x.tem_par, ABS(COALESCE(x.winrate_depois, 0) - COALESCE(x.winrate_antes, 0)), NULL), 2 IGNORE NULLS)[OFFSET(1)], 2)
                                                                                    AS mediana_pp_winrate,
        ROUND(MAX(IF(x.tem_par, ABS(COALESCE(x.winrate_depois, 0) - COALESCE(x.winrate_antes, 0)), NULL)), 2)
                                                                                    AS max_pp_winrate,
        COUNTIF(x.tem_par AND x.pd_antes < 5 AND x.pd_depois >= 5)                  AS n_cruzou_piso_5
    FROM comparado x
    JOIN janelas j
        ON  (j.ini IS NULL OR x.kickoff_utc >= j.ini)
        AND (j.fim IS NULL OR x.kickoff_utc <  j.fim)
    CROSS JOIN UNNEST(IF(x.precificado, ['todos', 'precificados'], ['todos'])) AS u
    GROUP BY x.cenario, j.janela, x.grupo, u
),

-- A grade completa: a Liga MX (e qualquer célula sem âncora) sai como linha de zeros, não como ausência.
grade AS (
    SELECT cenario, janela, grupo, universo
    FROM UNNEST(['2026', '2025_2026'])                                                                             AS cenario
    CROSS JOIN UNNEST(['congelada', 'nova', 'toda'])                                                               AS janela
    CROSS JOIN UNNEST(['128', '239', '281', '262', 'afetado_fora_lib_sud', 'controle_lib_sud', 'controle_outras']) AS grupo
    CROSS JOIN UNNEST(['todos', 'precificados'])                                                                   AS universo
)

SELECT
    g.cenario,
    g.janela,
    g.grupo                                            AS liga_origem,
    g.universo,
    COALESCE(c.n_ancoras, 0)                           AS n_ancoras,
    COALESCE(c.n_sem_par, 0)                           AS n_sem_par,
    COALESCE(c.n_sem_historico_antes, 0)               AS n_sem_historico_antes,
    COALESCE(c.n_ganhou_historico_do_zero, 0)          AS n_ganhou_historico_do_zero,
    COALESCE(c.n_last10_mudou, 0)                      AS n_last10_mudou,
    c.delta_medio_played_total,
    c.delta_medio_pp_winrate,
    c.mediana_pp_winrate,
    c.max_pp_winrate,
    COALESCE(c.n_cruzou_piso_5, 0)                     AS n_cruzou_piso_5,
    CASE
        WHEN STARTS_WITH(g.grupo, 'controle')
             AND (COALESCE(c.n_last10_mudou, 0) > 0 OR COALESCE(c.n_sem_par, 0) > 0
                  OR COALESCE(c.delta_medio_played_total, 0) != 0 OR COALESCE(c.delta_medio_pp_winrate, 0) != 0)
            THEN 'AVISO: o controle deveria ser 0 exato — DRIFT DE RAW ENTRE BUILDS (fixtures-live), não efeito das ligas; números desta célula não confiáveis'
        WHEN COALESCE(c.n_sem_par, 0) > 0
            THEN 'AVISO: âncoras do antes sem par no depois — o raw andou entre os builds'
        WHEN g.grupo = '262'
            THEN 'Liga MX: nenhum clube joga Lib/Sud — efeito zero por construção'
        WHEN g.grupo = 'afetado_fora_lib_sud' AND COALESCE(c.n_ancoras, 0) > 0
            THEN 'clube da leva com âncora fora de Lib/Sud — inesperado, investigar'
    END                                                AS observacao
FROM grade g
LEFT JOIN celulas c USING (cenario, janela, grupo, universo)
ORDER BY
    g.cenario DESC,
    CASE g.janela WHEN 'congelada' THEN 1 WHEN 'nova' THEN 2 ELSE 3 END,
    g.universo,
    CASE g.grupo WHEN '128' THEN 1 WHEN '239' THEN 2 WHEN '281' THEN 3 WHEN '262' THEN 4
                 WHEN 'afetado_fora_lib_sud' THEN 5 WHEN 'controle_lib_sud' THEN 6 ELSE 7 END
