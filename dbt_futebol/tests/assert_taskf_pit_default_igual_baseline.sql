{{ config(tags=['taskf']) }}
-- COSTURA A da task [F] (issue #49, ADR 0007) — o default do PIT não se move sozinho.
--
-- O QUE ELA AFIRMA: a saída de produção do int_futebol_team_form_pit não mudou desde o
-- congelamento, nas linhas cujo INSUMO não mudou. Falha = deriva: a saída se mexeu sem que o
-- insumo tivesse se mexido.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- ⚠️ O RECORTE DA COMPARAÇÃO MUDOU NA #123: DE PARTIÇÃO PARA LINHA.
--
-- Até 26/08/2026 a guarda comparava as PARTIÇÕES (competition_id, season) cuja impressão digital
-- do insumo estivesse intacta. Esse recorte era sólido enquanto o default fosse
-- `da_competicao`/`temporada`: a linha de uma âncora em (C,S) era função só de (C,S). A #91
-- tornou `todas` o DEFAULT, a linha passou a ler o histórico do time em TODA competição, e a
-- partição virou mais grossa que o fecho da conta.
--
-- Partição mais grossa que o fecho não fica frouxa: fica MENTIROSA — declara comparáveis linhas
-- cujo insumo mudou fora do recorte. Foi o que a guarda passou a acusar como se fosse regressão:
-- em 26/08 ela estava vermelha com 60 linhas, todas do Brasileirão 2026, cuja digital de insumo
-- casava BYTE A BYTE (380 fixtures, mesmo `fp_fixtures`). Os 20 times dele também jogam
-- Libertadores e Copa do Brasil, e foram essas duas que se mexeram. Recongelar não resolveria:
-- ficaria verde até a próxima partida em qualquer competição do portfólio, e voltaria. É a
-- "guarda permanentemente vermelha morre ignorada" na versão lenta.
--
-- Hoje o recorte é o FECHO da conta — por (fixture_id, team_id). O que compõe esse fecho, e por
-- que ele são CINCO insumos e não os dois que o corpo da spec da #123 enumerava, está no
-- cabeçalho de macros/taskf_fingerprint_insumo_pit.sql. Emenda à ADR 0007; verbete "Fecho de uma
-- linha" no glossário do CONTEXT.md.
--
-- ✅ O RECONGELAMENTO ACONTECEU NO MESMO COMMIT: sem ele nenhuma linha casaria — a guarda não
-- ficaria vermelha, ficaria VAZIA. 2026-08-28 14:25:03 UTC, de PRODUÇÃO, carimbo `687950f` (o
-- `PROCEDENCIA_SHA` do job `dbt-futebol`), 21.374 linhas. Receita e histórico dos três
-- congelamentos em analyses/taskf_congela_baseline.sql.
--
-- Rodada logo depois, `--target prod`: VERDE, com cobertura **1,0** — 21.374 de 21.374 linhas
-- comparadas. Cobertura cheia é o esperado no instante do congelamento, e é dela que a série de
-- erosão (ou de crescimento) vai partir.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- HISTÓRICO DE SENTIDO (a guarda já quis dizer três coisas, e as três estão registradas):
--
--   até 24/08 — "o default preserva o comportamento de antes das vars da ADR 0007". Essa premissa
--   morreu por DECISÃO na #91 (ADR 0010), que virou os defaults para `todas` + `ultimos_10` e pôs
--   produção a USAR o default.
--
--   25/08 — recongelada de PRODUÇÃO contra a célula `ambos` (21.078 linhas, 37 partições, carimbo
--   `887a1f9`), virando guarda de DERIVA sobre o caminho que o board de fato serve. O baseline
--   anterior (12/08, commit `a3b954e`, célula `base`) ficou nas cópias `baseline_*_pre91`.
--
--   28/08 (#123) — mesmo sentido, recorte novo: a comparação passa a ser por linha, porque a
--   partição parou de ser o fecho quando o default mudou.
--
-- QUEM RODA. Não é o agendado: a tag é `taskf` e não `guarda`, de propósito, pelo precedente da
-- #33 — guarda com baseline permanente não entra na tag, e o ticket que criou este teste (#50)
-- promete que nada do agendado mudou. Quem roda é a própria medição, que materializa a camada de
-- premissas com `dbt build` a cada célula (#51 a #54); a #52 exige por escrito que "a Costura A
-- segue verde". O teste é executado, portanto, exatamente quando a var pode ter vazado. Fora
-- disso: `dbt test --target prod --select assert_taskf_pit_default_igual_baseline`.
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
-- nenhuma linha casa.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- PISO DE COBERTURA (`taskf_cobertura_minima`, 0,5) — O NÚMERO É O MESMO, O SENTIDO MUDOU.
--
-- Sob o recorte por partição ele era guarda de EROSÃO: a cobertura encolhia sozinha conforme o
-- insumo andava, e uma guarda que compara 3 linhas continua verde dizendo o mesmo que uma que
-- compara 21 mil.
--
-- Sob o recorte por LINHA ele é guarda de VACUIDADE. O fecho de uma âncora de kickoff já passado
-- é feito só de fatos do passado: ele para de se mexer, e a cobertura CRESCE com o tempo em vez de
-- erodir. O que o piso pega agora é o passado sendo reescrito em massa — e, sobretudo, o caso
-- `cobertura = 0`, que é o que acontece quando a digital muda sem recongelamento. Sem o piso isso
-- passaria em branco; com ele, vira vermelho barulhento.
--
-- ⚠️ O 0,5 NÃO FOI RECALIBRADO, de propósito (#123 diz isso por escrito). Recalibrá-lo exigiria
-- medir uma trajetória de cobertura sob o recorte novo que ninguém mediu — a projeção da grelha de
-- 26/08 era 68,2% no instante da medição, e a afirmação de que ela cresce é dedução do fecho, não
-- série observada. Quando houver série, recalibrar é decisão explícita, no mesmo commit.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- AS DUAS FALSIFICAÇÕES, com comando e resultado.
--
-- 1) CÉLULA FORA DO DEFAULT DEIXA A GUARDA VERMELHA POR DESENHO. Esta guarda é default-only por
--    definição, então qualquer célula que não seja o default tem de excluí-la.
--
--      dbt build --target taskF --select int_futebol_team_form_pit \
--        --vars '{pit_escopo: da_competicao, pit_recorte: temporada}' \
--        --exclude assert_taskf_pit_default_igual_baseline
--      dbt test  --target taskF --select assert_taskf_pit_default_igual_baseline \
--        --vars '{pit_escopo: da_competicao, pit_recorte: temporada}'
--
--    EXECUTADA EM 2026-08-28 14:28 UTC, contra o dataset de medição: VERMELHA, **27.278**
--    divergências — 13.639 `so_no_baseline` + 13.639 `so_no_atual`, simétricas porque a célula
--    `base` reescreve o valor de toda linha comparável em vez de perder linhas. NENHUMA linha de
--    `cobertura_abaixo_do_piso`: casaram 13.639 das 21.374 do baseline (63,8%, acima do piso), e é
--    isso que torna a falsificação boa — ela é vermelha por CONTEÚDO, não por vacuidade, que é o
--    modo de falha distinto que a falsificação 2 cobre.
--
--    ⚠️ A cobertura não é 100% aqui porque a comparação corre com `--target taskF` e a digital sai
--    da CÓPIA de `fact_fixtures` daquele dataset, que é mais velha que a de produção. Isso é
--    esperado e não enfraquece a falsificação.
--
--    ⚠️ Este comando SOBRESCREVE `futebol_taskF.int_futebol_team_form_pit` com a célula `base` —
--    é o fluxo documentado no cabeçalho do modelo, uma tabela de trabalho por célula. Depois desta
--    execução ela foi reconstruída no default. Segue sendo a única exclusão que a medição precisa.
--    ⚠️ NÃO exclua também o `assert_pit_first_game_has_no_history` (#52): ele é verde nas quatro
--    células, e excluí-lo faz a célula rodar sem guarda de look-ahead — o defeito (Task 0) que a
--    [F] existe para refazer.
--
-- 2) RECORTE NOVO SEM RECONGELAR O BASELINE TEM DE DAR **VAZIA** — a falsificação que a #123
--    acrescentou, porque é a falha que o macro descreve e que produzir por acidente é fácil.
--    Perturbar a digital sem regravar o baseline (um campo a mais no STRUCT que produz o
--    `fp_insumo_linha`, em macros/taskf_fingerprint_insumo_pit.sql) e rodar:
--
--      dbt test --target prod --select assert_taskf_pit_default_igual_baseline
--
--    EXECUTADA EM 2026-08-28 14:26 UTC: VERMELHA com **uma** linha só, motivo
--    `cobertura_abaixo_do_piso`, com
--
--      {"linhas_comparadas":0, "linhas_no_baseline":21374, "cobertura":0, "piso":0.5,
--       "linhas_casadas_n":0, "linhas_na_digital_do_baseline":21374}
--
--    ZERO divergências de conteúdo — porque não há conteúdo comparado. É exatamente o modo "vazia"
--    ficando barulhento por causa do piso: sem ele a saída seria zero linhas e a guarda passaria
--    dizendo NADA sobre 21.374 linhas. Perturbação revertida em seguida e a guarda voltou a VERDE
--    (14:27 UTC), o que é a segunda metade da falsificação — uma falsificação que não volta ao
--    verde não provou o que dizia provar.

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

-- As LINHAS em que o insumo não se mexeu desde o congelamento. Uma igualdade só, sobre a digital
-- combinada: as colunas de componente existem no baseline para dizer QUAL insumo se mexeu quando
-- a cobertura cai, não para entrar no join.
linhas_casadas AS (
    SELECT b.fixture_id, b.team_id
    FROM {{ source('futebol_taskF', 'baseline_pit_fingerprint_linha') }} b
    JOIN fp_insumo_por_linha a
        ON  a.fixture_id = b.fixture_id
        AND a.team_id    = b.team_id
    WHERE a.fp_insumo_linha = b.fp_insumo_linha
),

atual AS (
    SELECT {{ colunas | join(', ') }}
    FROM {{ ref('int_futebol_team_form_pit') }}
    JOIN linhas_casadas USING (fixture_id, team_id)
),

baseline_completo AS (
    SELECT {{ colunas | join(', ') }}
    FROM {{ source('futebol_taskF', 'baseline_int_futebol_team_form_pit') }}
),

baseline AS (
    SELECT {{ colunas | join(', ') }}
    FROM baseline_completo
    JOIN linhas_casadas USING (fixture_id, team_id)
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
        linhas_casadas_n, linhas_na_digital_do_baseline
    )) AS linha
FROM (
    SELECT
        linhas_comparadas,
        linhas_no_baseline,
        linhas_casadas_n,
        linhas_na_digital_do_baseline,
        {{ var('taskf_cobertura_minima', 0.5) }} AS piso,
        SAFE_DIVIDE(linhas_comparadas, linhas_no_baseline) AS cobertura
    FROM (
        SELECT
            (SELECT COUNT(*) FROM atual)              AS linhas_comparadas,
            (SELECT COUNT(*) FROM baseline_completo)  AS linhas_no_baseline,
            (SELECT COUNT(*) FROM linhas_casadas)     AS linhas_casadas_n,
            (SELECT COUNT(*)
             FROM {{ source('futebol_taskF', 'baseline_pit_fingerprint_linha') }})
                                                      AS linhas_na_digital_do_baseline
    )
)
WHERE cobertura IS NULL OR cobertura < piso
