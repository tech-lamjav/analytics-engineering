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
*/WITH 

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

,

-- As LINHAS cujo insumo não se mexeu desde o congelamento. Mesma restrição da Costura A, pelo
-- mesmo motivo, e emitida pela mesma macro.
--
-- ⚠️ #123: era por (competition_id, season) e passou a ser por (fixture_id, team_id), porque a
-- partição deixou de ser o fecho da conta quando a #91 virou o default para `pit_escopo: todas`.
-- Aqui a mudança é mecânica — o veredito desta análise não muda de sentido, só fica restrito ao
-- recorte honesto.
linhas_casadas AS (
    SELECT b.fixture_id, b.team_id
    FROM `smartbetting-dados`.`futebol_taskF`.`baseline_pit_fingerprint_linha` b
    JOIN fp_insumo_por_linha a
        ON  a.fixture_id = b.fixture_id
        AND a.team_id    = b.team_id
    WHERE a.fp_insumo_linha = b.fp_insumo_linha
),

cel_base AS (
    SELECT fixture_id, team_id, competition, competition_id, season, kickoff_utc, played_total
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula` WHERE celula = 'base'
),

cel_escopo AS (
    SELECT fixture_id, team_id, competition, competition_id, season, kickoff_utc, played_total
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula` WHERE celula = 'escopo'
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
    FROM `smartbetting-dados`.`futebol_taskF`.`baseline_int_futebol_team_form_pit`
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
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_pit_por_celula`
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