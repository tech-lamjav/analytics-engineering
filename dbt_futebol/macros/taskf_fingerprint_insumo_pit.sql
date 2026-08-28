{#
    Impressão digital do INSUMO do int_futebol_team_form_pit, POR LINHA (fixture_id, team_id).

    Existe para que a Costura A (task [F], issue #49, ADR 0007) possa ser exata sem ser frágil.
    O insumo do modelo é vivo — fixture novo, resultado que entra, jogo remarcado —, e nada disso
    é regressão, mas tudo isso muda a saída. A guarda então compara só as LINHAS cujo insumo é
    idêntico ao do congelamento, e nelas exige igualdade sem folga.

    ⚠️ O RECORTE MUDOU NA #123, E O BASELINE FOI RECONGELADO NO MESMO COMMIT.

    Até 26/08/2026 o recorte era por (competition_id, season), e a justificativa escrita aqui era:
    "no caminho DEFAULT a linha de uma âncora em (C,S) é função só dos fixtures de (C,S) e das
    standings de (C,S)". A #91 tornou `pit_escopo: todas` o DEFAULT e essa premissa morreu — sob
    `todas` a linha lê o histórico do time em TODA competição. A partição ficou mais grossa que o
    fecho da conta, e partição mais grossa que o fecho não fica frouxa: fica MENTIROSA. Ela declara
    comparáveis linhas cujo insumo mudou fora do recorte. Medido em 26/08: o Brasileirão 2026 casou
    byte a byte na digital antiga (380 fixtures, `fp_fixtures` idêntico) e ainda assim divergiu em
    60 linhas, porque os 20 times dele também jogam Libertadores e Copa do Brasil.

    Emenda à ADR 0007, e o verbete "Fecho de uma linha" no glossário do CONTEXT.md.

    ─────────────────────────────────────────────────────────────────────────────────────────────
    O FECHO DA CONTA, lido do SQL do modelo e não da intuição. A linha (âncora F em C/S, time T) é
    função de CINCO coisas — e não das duas que o corpo da spec da #123 enumerou. A enumeração da
    spec ("(a) os fixtures de T em toda competição e (b) as standings de (C,S)") é aproximação da
    grelha; o que vale é o critério de aceite dela, "o fecho da conta". As três que faltavam estão
    marcadas ⚠ FALTAVA NA SPEC.

      1. a própria âncora F — `fixture_id, competition, competition_id, season, kickoff_utc` e os
         dois `team_id`. ⚠️ SEM status/placar de F: a linha de F não lê o resultado de F (o
         `team_log` do modelo exige `kickoff < kickoff(F)`, estrito). Digitalizar o placar de F
         faria toda linha quebrar quando o próprio jogo acontecesse — e aí o recorte por linha
         erodiria como o antigo, que é o defeito que ele existe para não ter.

      2. os 10 jogos encerrados ANTERIORES de T, em QUALQUER competição — o `pares` do modelo
         trunca em `tamanho_do_recorte` (QUALIFY ROW_NUMBER <= 10), então só a identidade desses 10
         entra nos agregados de forma. Correção num 11º jogo anterior não muda saída nenhuma, e
         digitalizar o histórico inteiro derrubaria linha por insumo que ela não lê.

      3. QUANTOS jogos anteriores existem, SEM o teto — é o `played_total_disponivel`, que sai de
         `COUNT(...) OVER (PARTITION BY fixture_id, team_id)` avaliado ANTES do QUALIFY. É coluna
         de saída, e o piso de amostra do task01_base() lê ELA, não o played_total (que satura).

      4. ⚠ FALTAVA NA SPEC — os jogos encerrados anteriores de (C,S) INTEIRO, de TODOS os times e
         não só de T. É o CTE `tabela` do modelo (competição-scoped por decisão, ADR 0008) que
         alimenta `points`, `goal_diff` e `ppg`, e é sobre ele que o `rank` faz `ROW_NUMBER() OVER
         (PARTITION BY fixture_id, group_name ORDER BY tb.points DESC, tb.wins_total DESC, ...)`.
         **Um adversário de grupo ter o placar corrigido muda o `rank` de T sem tocar em nenhum
         jogo de T.** Uma digital que só olhasse o histórico de T seria mentirosa exatamente aqui —
         o mesmo defeito da partição antiga, um grão abaixo.

      5. ⚠ FALTAVA NA SPEC (o elenco) — o ELENCO de (C,S) e a tabela de grupos:
         - `league_teams`/`league_size` saem de `targets`, ou seja, do conjunto DISTINTO de
           `team_id` de (C,S) — inclusive dos jogos FUTUROS. É de onde vem `n_teams`, coluna de
           saída, e é também o conjunto de adversários sobre o qual o `rank` ranqueia.
           ⚠️ É o único insumo do fecho que lê o futuro, e por isso ele entra como CONJUNTO DE
           TIMES e jamais como conjunto de fixtures: time novo em (C,S) muda `n_teams` de verdade e
           TEM de quebrar a linha; jogo novo de um time que já estava lá, não. Digitalizar fixtures
           aqui reproduziria a armadilha do recorte "por time" que a spec proíbe — aquela em que o
           Palmeiras jogar amanhã invalida a linha dele de 2024.
         - `team_group`, do `fact_standings_snapshot` com o MESMO QUALIFY do modelo: o insumo que
           ele de fato lê, e não a tabela crua (o snapshot ganha uma linha por dia por time, e
           digitalizar o cru mudaria todo dia — a guarda passaria em branco).

    ─────────────────────────────────────────────────────────────────────────────────────────────
    POR QUE ELE NÃO ERODE, que é a propriedade que o recorte por (C,S) não tinha: para âncora de
    kickoff JÁ PASSADO os cinco insumos são fatos do passado e param de se mexer. Jogo novo na
    competição entra no fecho das âncoras FUTURAS, não no das passadas. A cobertura cresce com o
    tempo em vez de erodir — e o piso deixa de ser guarda de erosão para ser guarda de VACUIDADE
    (ver o cabeçalho do teste). Os dois eroderes legítimos que sobram são raros e reais: correção de
    placar de jogo antigo, e time novo entrando em (C,S) — este esperado nas copas de mata-mata,
    onde a cobertura é função da FASE (ver `docs/TASKF_RESULTADOS.md`, Copa do Brasil).

    ⚠️ ELA É DEFAULT-ONLY, como a guarda que a lê. O fecho acima é o do caminho `todas` +
    `ultimos_10`, que desde a #91 É o default e É produção. Sob outra célula (`da_competicao` /
    `temporada`) o modelo lê outro conjunto e esta digital não o descreve — o que está certo: a
    guarda é vermelha por desenho fora do default, e é essa a primeira falsificação registrada no
    cabeçalho do teste.

    ⚠️ ESTA DEFINIÇÃO É CONTRATO CONGELADO. Ela é usada nos dois lados da comparação: uma vez em
    analyses/taskf_congela_baseline.sql, que grava futebol_taskF.baseline_pit_fingerprint_linha, e
    a cada execução em tests/assert_taskf_pit_default_igual_baseline.sql. Mudar o que entra no
    FARM_FINGERPRINT muda os valores e faz NENHUMA linha casar contra o baseline já gravado — e a
    guarda não fica vermelha, fica VAZIA. É o piso de cobertura que transforma essa vacuidade em
    vermelho barulhento, e é essa a segunda falsificação registrada no cabeçalho do teste. Por isso
    as duas pontas leem daqui e não de cópias: cópia que precisa ficar idêntica para sempre não
    fica. Se um dia for mesmo preciso mudar, o baseline tem de ser recongelado NO MESMO COMMIT —
    decisão de quem revisa, não passo de rotina.

    Emite UMA CTE no escopo do chamador, `fp_insumo_por_linha`, com uma linha por (fixture_id,
    team_id). Uma CTE do chamador com esse nome a sombreia em silêncio.

    ⚠️ A CTE se chama `fp_insumo_por_linha` e a coluna, `fp_insumo_linha` — de propósito, e não
    por descuido. No BigQuery um nome de tabela usado como expressão é o STRUCT da linha inteira,
    então CTE e coluna homônimas fazem `SELECT fp_insumo_linha FROM fp_insumo_linha` devolver o
    struct em vez do inteiro, e o erro só aparece quando alguém tenta agregar
    ("Aggregate functions with DISTINCT cannot be used with arguments of type STRUCT").

    Uso:

        WITH {{ taskf_fingerprint_insumo_pit() }},
        linhas_casadas AS (
            SELECT a.fixture_id, a.team_id
            FROM fp_insumo_por_linha a
            JOIN {{ source('futebol_taskF', 'baseline_pit_fingerprint_linha') }} b
                USING (fixture_id, team_id)
            WHERE a.fp_insumo_linha = b.fp_insumo_linha
        )
#}

{% macro taskf_fingerprint_insumo_pit() %}

fp_fixtures_base AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc,
        status_short, score_fulltime_home, score_fulltime_away
    FROM {{ ref('fact_fixtures') }}
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
    WHERE {{ futebol_jogo_encerrado() }}
    UNION ALL
    SELECT fixture_id, competition_id, season, kickoff_utc,
           away_team_id, FALSE,
           score_fulltime_away, score_fulltime_home
    FROM fp_fixtures_base
    WHERE {{ futebol_jogo_encerrado() }}
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
    ) <= {{ taskf_eixos().tamanho_do_recorte }}
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
    FROM {{ ref('fact_standings_snapshot') }}
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

{% endmacro %}
