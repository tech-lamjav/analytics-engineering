{{ config(tags=['taskf']) }}
-- COSTURA A da task [F] (issue #49, ADR 0007) — o default do PIT não se move sozinho.
--
-- ⚠️ ESTA GUARDA MUDOU DE SENTIDO NA #91, E O BASELINE FOI RECONGELADO COM ELA.
--
-- O que ela afirmava até 24/08/2026: a ADR 0007 deixou no código de produção duas vars que
-- produção nunca passava, e prometeu que o DEFAULT delas preservava o comportamento anterior.
-- A guarda transformava a promessa em fato verificado, e falha significava "o andaime da
-- medição vazou para o caminho que o board serve".
--
-- Essa premissa morreu por decisão, não por acidente: a #91 (ADR 0010, Recomendação 1 da [F])
-- virou os defaults para `todas` + `ultimos_10` — a célula `ambos` —, e produção passou a USAR
-- o default. "O default reproduz o comportamento de antes das vars" deixou de ser verdade no
-- mesmo commit em que deixou de ser desejável.
--
-- O que ela afirma AGORA: o default não se move sozinho. O baseline foi regravado (pelo
-- analyses/taskf_congela_baseline.sql) a partir da célula `ambos` com AET/PEN no histórico
-- (#71), e a guarda segue comparando linha a linha contra ele. Deixou de ser guarda de
-- vazamento-de-andaime e virou guarda de DERIVA: falha = a saída de produção mudou sem que o
-- insumo tenha mudado, que é o mesmo modo de falha que ela sempre pegou, só que agora sobre o
-- caminho que o board de fato serve.
--
-- É o cabeçalho da própria guarda que autorizava esta saída: "as duas saídas honestas são
-- recongelar o baseline de propósito (no mesmo commit da mudança que o justifica) ou baixar o
-- piso de propósito — as duas explícitas, nenhuma silenciosa".
--
-- QUEM RODA. Não é o agendado: a tag é `taskf` e não `guarda`, de propósito — o pipeline horário
-- executa `dbt test --select tag:guarda` e o ticket que criou este teste (#50) promete que nada
-- do agendado mudou. Quem roda é a própria medição, que materializa a camada de premissas com
-- `dbt build` a cada célula (#51 a #54); a #52 chega a exigir por escrito que "a Costura A segue
-- verde". O teste é executado, portanto, exatamente quando a var pode ter vazado — que é quando
-- a pergunta dele importa. Fora disso: `dbt build --target taskF --select
-- int_futebol_team_form_pit`.
--
-- Igualdade EXATA, sem tolerância: o modelo lê só fact_fixtures e fact_standings_snapshot — é
-- determinístico, não encosta em odds, e por isso não há deriva legítima para acomodar. A
-- comparação é linha a linha, nos dois sentidos (EXCEPT DISTINCT dos dois lados), sobre lista
-- EXPLÍCITA de colunas: coluna nova acrescentada por um ticket seguinte não invalida o baseline
-- silenciosamente, e dbt_loaded_at fica de fora porque muda a cada build por construção.
--
-- ⚠️ O que é restringido é QUAIS LINHAS são comparáveis, nunca QUANTO elas podem diferir. O
-- porquê, e o contrato congelado da impressão digital, estão na macro
-- taskf_fingerprint_insumo_pit — a MESMA que gravou o baseline. Se as duas pontas divergirem,
-- nenhuma partição casa.
--
-- PISO DE COBERTURA. Restringir linhas comparáveis tem um modo de falha próprio: a cobertura
-- encolhe sozinha conforme o insumo anda, e uma guarda que compara 3 linhas continua verde
-- dizendo o mesmo que uma que compara 21 mil. Por isso a cobertura é medida e tem piso declarado
-- (`taskf_cobertura_minima`, hoje 0,5 das linhas do baseline): abaixo dele o teste FALHA, com os
-- números na saída. O piso não é alto de propósito — durante a [F] as competições da temporada
-- corrente saem da comparação legitimamente, uma a uma, conforme os jogos acontecem. Ele pega a
-- erosão estrutural, não a natural. Quando ele disparar, as duas saídas honestas são recongelar
-- o baseline de propósito (no mesmo commit da mudança que o justifica) ou baixar o piso de
-- propósito — as duas explícitas, nenhuma silenciosa.
--
-- ⚠️ A FALSIFICAÇÃO INVERTEU DE LADO NA #91. Ela foi falsificada uma vez com
-- `--vars '{pit_escopo: todas}'`, que a deixava vermelha (12.868 divergências) — porque `todas`
-- era a célula juntada e o baseline era o da célula `base`. Hoje `todas` + `ultimos_10` É o
-- default e o baseline, então quem a deixa vermelha agora é o caminho ANTIGO:
--
--   dbt build --target taskF --select int_futebol_team_form_pit \
--     --vars '{pit_escopo: da_competicao, pit_recorte: temporada}' \
--     --exclude assert_taskf_pit_default_igual_baseline
--
-- A regra por trás não mudou: esta guarda é default-only por definição, então QUALQUER célula
-- que não seja o default a deixa vermelha por desenho e tem de excluí-la. O que mudou é qual
-- célula é o default. Ela segue sendo a única exclusão que a medição precisa.
--
-- ⚠️ Esta receita já mandou excluir também o `assert_pit_first_game_has_no_history`. NÃO EXCLUA
-- MAIS (#52): a partição dele passou a seguir os eixos da célula, ele é verde nas quatro, e
-- excluí-lo faz a célula rodar sem guarda de look-ahead — o defeito (Task 0) que contaminou a
-- medição que a [F] existe para refazer.

{% set colunas = [
    'fixture_id', 'team_id', 'competition', 'competition_id', 'season', 'kickoff_utc',
    'played_home', 'played_away', 'played_total',
    'wins_home', 'draws_home', 'wins_away', 'draws_away', 'wins_total', 'draws_total',
    'goals_for_avg_home', 'goals_for_avg_away', 'goals_for_avg_total',
    'goals_against_avg_home', 'goals_against_avg_away', 'goals_against_avg_total',
    'clean_sheet_total', 'failed_to_score_total',
    'rank', 'points', 'goal_diff', 'ppg', 'n_teams', 'group_name',
    'n_wins_last5', 'n_games_last5', 'form_last5'
] %}

WITH {{ taskf_fingerprint_insumo_pit() }},

-- As partições em que o insumo não se mexeu desde o congelamento. IS NOT DISTINCT FROM porque
-- fp_standings é NULL em competição sem tabela (Copa do Brasil) — NULL = NULL tem de casar.
particoes_casadas AS (
    SELECT b.competition_id, b.season
    FROM {{ source('futebol_taskF', 'baseline_pit_fingerprint') }} b
    JOIN fp_insumo_pit a
        ON  a.competition_id = b.competition_id
        AND a.season         = b.season
    WHERE a.n_fixtures    = b.n_fixtures
      AND a.fp_fixtures   = b.fp_fixtures
      AND a.n_grupos      = b.n_grupos
      AND a.fp_standings IS NOT DISTINCT FROM b.fp_standings
),

atual AS (
    SELECT {{ colunas | join(', ') }}
    FROM {{ ref('int_futebol_team_form_pit') }}
    JOIN particoes_casadas USING (competition_id, season)
),

baseline_completo AS (
    SELECT {{ colunas | join(', ') }}
    FROM {{ source('futebol_taskF', 'baseline_int_futebol_team_form_pit') }}
),

baseline AS (
    SELECT {{ colunas | join(', ') }}
    FROM baseline_completo
    JOIN particoes_casadas USING (competition_id, season)
),

divergencias AS (
    SELECT 'so_no_baseline' AS motivo, TO_JSON_STRING(d) AS linha
    FROM (SELECT * FROM baseline EXCEPT DISTINCT SELECT * FROM atual) d

    UNION ALL

    SELECT 'so_no_atual' AS motivo, TO_JSON_STRING(d) AS linha
    FROM (SELECT * FROM atual EXCEPT DISTINCT SELECT * FROM baseline) d
)

SELECT motivo, linha FROM divergencias

UNION ALL

-- Piso de cobertura, que também é a guarda de vacuidade: zero linhas comparadas está abaixo de
-- qualquer piso positivo, então passar em branco deixa de ser possível.
SELECT
    'cobertura_abaixo_do_piso' AS motivo,
    TO_JSON_STRING(STRUCT(
        linhas_comparadas, linhas_no_baseline, cobertura, piso,
        particoes_casadas_n, particoes_no_baseline
    )) AS linha
FROM (
    SELECT
        linhas_comparadas,
        linhas_no_baseline,
        particoes_casadas_n,
        particoes_no_baseline,
        {{ var('taskf_cobertura_minima', 0.5) }} AS piso,
        SAFE_DIVIDE(linhas_comparadas, linhas_no_baseline) AS cobertura
    FROM (
        SELECT
            (SELECT COUNT(*) FROM atual)               AS linhas_comparadas,
            (SELECT COUNT(*) FROM baseline_completo)   AS linhas_no_baseline,
            (SELECT COUNT(*) FROM particoes_casadas)   AS particoes_casadas_n,
            (SELECT COUNT(*) FROM {{ source('futebol_taskF', 'baseline_pit_fingerprint') }})
                                                       AS particoes_no_baseline
    )
)
WHERE cobertura IS NULL OR cobertura < piso
