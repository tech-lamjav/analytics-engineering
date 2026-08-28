/*
    [F-4] A INVARIANTE DA CÉLULA `escopo`: soltar a competição do join só pode ACRESCENTAR
    partidas anteriores. Para todo par (jogo, time), `escopo` >= `base`.

    O critério de aceite da #53 diz por que ela importa: "se alguma for menor, há fan-out ou perda
    de linha". Juntar competições é remover uma condição de um LEFT JOIN — o conjunto de partidas
    anteriores de `escopo` é um SUPERCONJUNTO do de `base` por construção, e nenhum dado pode
    fazer a contagem cair. Se cair, o que mudou não foi o escopo: foi o grão.

    ⚠️ AS GUARDAS DE GRÃO NÃO COBREM ISTO. O `unique_combination_of_columns` dos seis modelos pega
    fan-out (linha a mais) e não pega perda de linha (linha a menos) — um par que sumiu deixa a
    tabela mais única, não menos. Aqui as duas pontas são conferidas, nos dois sentidos
    (`so_no_base` e `so_no_escopo`), e o eixo de escopo não deveria mexer em nenhuma das duas: ele
    toca a condição do LEFT JOIN, nunca o produto âncora × time que define as linhas de saída.

    ────────────────────────────────────────────────────────────────────────────────
    TRÊS MODOS DE FALHA, TRÊS VEREDITOS — e o segundo é o que esta análise tem de mais importante:

      CHAVES_DIVERGENTES            algum par existe numa célula e não na outra.
      VIOLACAO_DE_MONOTONICIDADE    algum par tem `escopo` < `base`.
      MESMO_CONTEUDO_NAS_DUAS       NENHUM par ganhou partida. Isto não é "efeito nulo": sob
                                    `pit_escopo: todas` sabe-se de antemão que o primeiro jogo de
                                    Copa do Brasil de um time passa a carregar o Brasileirão — a
                                    falsificação do #50 contou 224 primeiros jogos com passado.
                                    Zero ganho, portanto, quer dizer que as duas linhas da tabela
                                    de carimbos contêm o MESMO dado: o carimbo rodou fora de ordem
                                    e uma célula foi gravada com o rótulo da outra. É a guarda de
                                    não-vacuidade — sem ela, a ordem errada de execução sairia
                                    daqui como `OK`, que é o pior resultado possível.

    O LADO `base` AINDA É CONFERIDO CONTRA O BASELINE CONGELADO, e por isso o rótulo `base` não
    depende só da disciplina de quem rodou: `baseline_int_futebol_team_form_pit` foi gravado ANTES
    de as vars existirem (analyses/taskf_congela_baseline.sql), então ele é a definição de "sem
    medição dentro". A comparação usa a mesma restrição de partições da Costura A — a impressão
    digital do insumo, via taskf_fingerprint_insumo_pit() —, porque fixture novo e resultado que
    entrou mudam a saída legitimamente e não são regressão.

    ⚠️ ESTA ANÁLISE NÃO CHAMA taskf_celula(). Ela lê os literais 'base' e 'escopo' da tabela de
    carimbos de propósito: é uma comparação ENTRE células e não pertence a nenhuma delas. Chamar a
    macro a faria depender das vars da linha de comando, que é exatamente o acoplamento que ela
    existe para auditar.

    ⚠️ O MESMO PAR É MEDIDO TAMBÉM PELA analyses/taskf_saturacao_recorte.sql (#54), que fecha as
    quatro arestas do 2x2 sobre a contagem DISPONÍVEL. Este arquivo continua existindo porque faz
    duas coisas que aquele não faz: compara `played_total` (a contagem usada) e confere o lado
    `base` contra o baseline congelado antes das vars, nas partições de insumo casado. Nas células
    de `temporada` as duas contagens são o mesmo número, então os dois têm de concordar — e
    concordam exatamente. Se um dia divergirem, é sinal.

    POR QUE ANÁLISE E NÃO TESTE SINGULAR. Um teste dbt roda dentro da execução de UMA célula, e a
    outra ainda não existe: no build da `base` ele passaria em branco (vacuidade) e no da `escopo`
    ele afirmaria algo sobre um carimbo gravado antes. As invariantes que se assere sobre a saída
    das quatro células juntas são a Costura B (#55), por decisão da spec. Prior art de formato:
    analyses/taskf_reconciliacao_01.sql, que também é comparação e também emite veredito.

    COMO RODAR (do dbt_futebol/), depois de as DUAS células terem sido carimbadas:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_monotonicidade_escopo
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_monotonicidade_escopo.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{#- O carimbo é lido por `source()`, como todo o resto do dataset de medição — o schema é fixo em
    futebol_taskF na declaração, então ele não segue o `--target` (que é o motivo de a ESCRITA, em
    analyses/taskf_pit_por_celula.sql, ser literal). CODING_STANDARDS.md: "Relations only via
    ref() / source() — never hardcoded table names". -#}
{%- set carimbos = source('futebol_taskF', 'taskf_pit_por_celula') -%}

WITH {{ taskf_fingerprint_insumo_pit() }},

-- As LINHAS cujo insumo não se mexeu desde o congelamento. Mesma restrição da Costura A, pelo
-- mesmo motivo, e emitida pela mesma macro.
--
-- ⚠️ #123: era por (competition_id, season) e passou a ser por (fixture_id, team_id), porque a
-- partição deixou de ser o fecho da conta quando a #91 virou o default para `pit_escopo: todas`.
-- Aqui a mudança é mecânica — o veredito desta análise não muda de sentido, só fica restrito ao
-- recorte honesto.
linhas_casadas AS (
    SELECT b.fixture_id, b.team_id
    FROM {{ source('futebol_taskF', 'baseline_pit_fingerprint_linha') }} b
    JOIN fp_insumo_por_linha a
        ON  a.fixture_id = b.fixture_id
        AND a.team_id    = b.team_id
    WHERE a.fp_insumo_linha = b.fp_insumo_linha
),

cel_base AS (
    SELECT fixture_id, team_id, competition, competition_id, season, kickoff_utc, played_total
    FROM {{ carimbos }} WHERE celula = 'base'
),

cel_escopo AS (
    SELECT fixture_id, team_id, competition, competition_id, season, kickoff_utc, played_total
    FROM {{ carimbos }} WHERE celula = 'escopo'
),

-- FULL OUTER para que par que existe de um lado só apareça, em vez de sumir no join.
emparelhado AS (
    SELECT
        fixture_id,
        team_id,
        COALESCE(b.competition, e.competition)     AS competition,
        COALESCE(b.kickoff_utc, e.kickoff_utc)     AS kickoff_utc,
        b.played_total                             AS played_base,
        e.played_total                             AS played_escopo
    FROM cel_base AS b
    FULL OUTER JOIN cel_escopo AS e USING (fixture_id, team_id)
),

-- O lado `base` do carimbo contra o baseline gravado antes de as vars existirem.
base_casada AS (
    SELECT fixture_id, team_id, played_total
    FROM cel_base JOIN linhas_casadas USING (fixture_id, team_id)
),
baseline_casado AS (
    SELECT fixture_id, team_id, played_total
    FROM {{ source('futebol_taskF', 'baseline_int_futebol_team_form_pit') }}
    JOIN linhas_casadas USING (fixture_id, team_id)
),
contra_baseline AS (
    SELECT
        (SELECT COUNT(*) FROM base_casada)      AS pares_conferidos_vs_baseline,
        (SELECT COUNT(*) FROM baseline_casado)  AS pares_no_baseline_casado,
        (SELECT COUNT(*) FROM (
            SELECT * FROM base_casada EXCEPT DISTINCT SELECT * FROM baseline_casado
        ))                                      AS divergencias_vs_baseline
),

carimbos_das_celulas AS (
    SELECT
        COUNTIF(celula = 'base')   > 0 AS tem_base,
        COUNTIF(celula = 'escopo') > 0 AS tem_escopo,
        MIN(IF(celula = 'base',   medido_em, NULL)) AS base_medido_em,
        MIN(IF(celula = 'escopo', medido_em, NULL)) AS escopo_medido_em,
        MIN(IF(celula = 'base',   git_sha,   NULL)) AS base_git_sha,
        MIN(IF(celula = 'escopo', git_sha,   NULL)) AS escopo_git_sha
    FROM {{ carimbos }}
    WHERE celula IN ('base', 'escopo')
),

resumo AS (
    SELECT
        COUNTIF(played_base   IS NOT NULL)                                 AS pares_base,
        COUNTIF(played_escopo IS NOT NULL)                                 AS pares_escopo,
        COUNTIF(played_escopo IS NULL)                                     AS so_no_base,
        COUNTIF(played_base   IS NULL)                                     AS so_no_escopo,
        COUNTIF(played_escopo >  played_base)                              AS pares_com_ganho,
        COUNTIF(played_escopo =  played_base)                              AS pares_iguais,
        COUNTIF(played_escopo <  played_base)                              AS violacoes,
        ROUND(AVG(IF(played_escopo > played_base,
                     played_escopo - played_base, NULL)), 2)               AS ganho_medio_quando_ganha,
        MAX(played_escopo - played_base)                                   AS ganho_max,
        ROUND(AVG(played_base),   2)                                       AS played_medio_base,
        ROUND(AVG(played_escopo), 2)                                       AS played_medio_escopo,
        ARRAY_AGG(
            IF(played_escopo < played_base,
               TO_JSON_STRING(STRUCT(fixture_id, team_id, competition, kickoff_utc,
                                     played_base, played_escopo)),
               NULL)
            IGNORE NULLS LIMIT 5
        )                                                                  AS exemplos_de_violacao,
        ARRAY_AGG(
            IF(played_base IS NULL OR played_escopo IS NULL,
               TO_JSON_STRING(STRUCT(fixture_id, team_id, competition, kickoff_utc,
                                     played_base, played_escopo)),
               NULL)
            IGNORE NULLS LIMIT 5
        )                                                                  AS exemplos_de_chave_faltando
    FROM emparelhado
)

SELECT
    CASE
        WHEN NOT c.tem_base OR NOT c.tem_escopo       THEN 'FALTA_UMA_DAS_CELULAS'
        WHEN r.so_no_base > 0 OR r.so_no_escopo > 0   THEN 'CHAVES_DIVERGENTES'
        WHEN r.violacoes > 0                          THEN 'VIOLACAO_DE_MONOTONICIDADE'
        WHEN r.pares_com_ganho = 0                    THEN 'MESMO_CONTEUDO_NAS_DUAS'
        WHEN b.divergencias_vs_baseline > 0
             OR b.pares_conferidos_vs_baseline
                != b.pares_no_baseline_casado         THEN 'BASE_NAO_BATE_O_BASELINE'
        ELSE                                               'OK'
    END                                    AS veredito,
    r.pares_base,
    r.pares_escopo,
    r.so_no_base,
    r.so_no_escopo,
    r.violacoes,
    r.pares_com_ganho,
    r.pares_iguais,
    ROUND(SAFE_DIVIDE(r.pares_com_ganho, r.pares_base) * 100, 1) AS pct_pares_com_ganho,
    r.ganho_medio_quando_ganha,
    r.ganho_max,
    r.played_medio_base,
    r.played_medio_escopo,
    b.pares_conferidos_vs_baseline,
    b.pares_no_baseline_casado,
    b.divergencias_vs_baseline,
    c.base_medido_em,
    c.escopo_medido_em,
    c.base_git_sha,
    c.escopo_git_sha,
    r.exemplos_de_violacao,
    r.exemplos_de_chave_faltando
FROM resumo AS r
CROSS JOIN contra_baseline AS b
CROSS JOIN carimbos_das_celulas AS c
