{#
    O PORTÃO DA CADEIA DE AMISTOSOS (DE#95, ADR 0004 no data-engineering, decisão 16).

    Mede o deslocamento retroativo que ligar os amistosos de seleção (league_id 10) causaria no
    histórico PIT (`int_futebol_team_form_pit`, célula de produção `todas|ultimos_10`) das
    seleções que JÁ têm jogos medidos no mart — Copa do Mundo (competition_id 1) e Nations League
    (competition_id 5) — e confronta com a régua de 0,25 pp herdada da #92.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE ESTE ARQUIVO NÃO COMPILA SOZINHO

    A comparação é ANTES × DEPOIS do mesmo modelo (`int_futebol_team_form_pit`), e as duas
    versões vivem em datasets diferentes — não dá pra pedir duas coisas de um `ref()` só. O
    "antes" é a produção tal como está (`futebol`, que já exclui league_id 10 por construção,
    via o corte em stg_futebol_fixtures.sql). O "depois" precisa ser MATERIALIZADO antes de
    rodar esta query, contra o target `taskF`, com a var que liga o corte de volta:

        cd dbt_futebol
        DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
          --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit \
          --full-refresh --vars '{taskf_incluir_amistosos: true}' --exclude-resource-type test

    Depois de ler o resultado, RESTAURE o target `taskF` ao estado default (sem a var) — ele é
    compartilhado, e outra pessoa medindo outra célula não espera achar amistosos lá dentro:

        DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
          --select stg_futebol_fixtures fact_fixtures int_futebol_team_form_pit \
          --full-refresh --exclude-resource-type test

    Nunca contra `dev`/`prod` — os dois apontam para o dataset de produção (`futebol`), e rodar
    o build acima sem `--target taskF` publicaria o cenário "com amistosos" no board. Ver ADR
    0007 e o comentário em macros/taskf_destino.sql.

    ────────────────────────────────────────────────────────────────────────────────
    A MÉTRICA

    O nível mecânico (quantas linhas mudam, e como) é a taxa de vitória PIT — `wins_total /
    played_total`, em pontos percentuais — comparada linha a linha por (fixture_id, team_id).
    Não é a mesma métrica que a régua de 0,25 pp calibra (que é sobre `aconteceu_p*` de
    premissa, Teste 2) — rodar as 5 famílias de premissas nos dois cenários para produzir o
    número exato na mesma unidade ficou fora deste ticket por custo, e a decisão foi validada
    porque o resultado abaixo não deixa margem: o deslocamento medido aqui é ~90x a régua, e
    qualquer métrica de taxa (incluindo `aconteceu_p*`) se move na mesma ordem de grandeza —
    quando `played_total` vai de 0 para vários jogos, a premissa sai de "não avalia" (piso de
    amostra não bate) para "avalia", o que É o deslocamento, não uma aproximação dele.

    Ver a leitura completa em docs/TASKF_RESULTADOS.md, seção "Ticket DE#95".

    ────────────────────────────────────────────────────────────────────────────────
    ⚠️ DEPOIS DA DE#96 (slug `amistosos` ligado com corte por kickoff)

    A produção deixou de excluir a liga 10 inteira: agora exclui só o que tem kickoff antes da
    data de entrada (macros/futebol_competicoes_insumo.sql). O "antes" desta query passa a conter
    os amistosos FUTUROS, então rodar de novo depois do deploy não devolve o mesmo número nas
    âncoras de Nations League que caem depois de algum amistoso. O que a #95 mediu — o efeito do
    PASSADO — segue legível restringindo as duas CTEs a âncoras com kickoff anterior à data de
    entrada: ali os dois cenários só diferem pelos 115 FT de jan–jun, como no dia da medição.
#}

WITH antes AS (
    SELECT * FROM `smartbetting-dados.futebol.int_futebol_team_form_pit`
    WHERE competition_id IN (1, 5)
),

depois AS (
    -- Exige o build toggled acima já ter rodado. Se `taskF` estiver no estado default (sem
    -- amistosos), esta CTE fica idêntica a `antes` e todo delta sai zero — não é ausência de
    -- efeito, é o experimento não ter sido montado.
    SELECT * FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`
    WHERE competition_id IN (1, 5)
),

comparado AS (
    SELECT
        a.competition,
        a.fixture_id,
        a.team_id,
        a.played_total                                          AS pt_antes,
        d.played_total                                          AS pt_depois,
        SAFE_DIVIDE(a.wins_total, a.played_total) * 100          AS winrate_antes,
        SAFE_DIVIDE(d.wins_total, d.played_total) * 100          AS winrate_depois
    FROM antes a
    JOIN depois d USING (fixture_id, team_id)
)

SELECT
    competition,
    COUNT(*)                                                              AS n_ancoras,
    COUNTIF(pt_antes = 0)                                                 AS n_sem_historico_antes,
    COUNTIF(pt_antes = 0 AND pt_depois > 0)                               AS n_ganhou_historico_do_zero,
    ROUND(AVG(pt_depois - pt_antes), 2)                                   AS delta_medio_played_total,
    ROUND(AVG(ABS(COALESCE(winrate_depois, 0) - COALESCE(winrate_antes, 0))), 2) AS delta_medio_pp_winrate,
    ROUND(APPROX_QUANTILES(ABS(COALESCE(winrate_depois, 0) - COALESCE(winrate_antes, 0)), 2)[OFFSET(1)], 2)
                                                                           AS mediana_pp_winrate
FROM comparado
GROUP BY competition
ORDER BY competition
