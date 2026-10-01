{{ config(tags=['taskf']) }}
-- O DESTINO DA REMEDIÇÃO (AE#117, termo 5) — macros/taskf_destino.sql.
--
-- Falha (devolve linhas) se um destino da medição apontar para a tabela errada, ligar o gate de
-- preço onde não devia ou emitir a lista de universos de outro destino.
--
-- POR QUE ESTE TESTE EXISTE. O destino é o que impede a remedição de escrever na tabela
-- acumulativa do 2×2: `taskf_destino: medicao` faz `DELETE ... WHERE celula = 'ambos'` em
-- `taskf_teste2`, e uma medição de outro commit ali deixa a Costura B vermelha com razão — além
-- de destruir, sem histórico, o registro congelado que a ADR 0010 promete manter. O destino novo
-- (`remedicao`) é tabela irmã, e o que separa as duas é um sufixo num dicionário. Um sufixo errado
-- é silencioso, então o mapa inteiro é afirmado aqui.
--
-- É SINTÉTICO sobre o macro: não lê tabela. Cada linha traz o valor esperado escrito À MÃO, a
-- partir do contrato — nunca recomputado pelo próprio macro, que seria tautologia. Os destinos
-- `medicao` e `ancora` entram porque a #82/#117 dependem do contrato deles NÃO ter mudado: a âncora
-- re-rodada no mesmo PR só é comparável se o destino e a lista de universos dela forem os de antes.
--
-- A recusa de um destino desconhecido (fail-closed) é erro de COMPILAÇÃO e portanto não cabe num
-- teste que compila; ela é verificada à mão e registrada no PR.

WITH casos AS (
    SELECT * FROM UNNEST([
        STRUCT('medicao'            AS destino,
               'smartbetting-dados.futebol_taskF.t'                    AS tabela_esperada,
               FALSE                                                   AS gates_esperado,
               'completo,sem_copa_mundo,estendido,estendido_sem_champions_classif' AS universos_esperados,
               '{{ taskf_destino("t", "medicao") }}'                   AS tabela_obtida,
               {{ 'TRUE' if taskf_gates_board("medicao") else 'FALSE' }} AS gates_obtido,
               '{{ taskf_universos_do_destino("medicao") | map(attribute="nome") | join(",") }}' AS universos_obtidos),
        STRUCT('ancora',
               'smartbetting-dados.futebol_taskF.t_ancora',
               FALSE,
               'completo,sem_copa_mundo,estendido,estendido_sem_champions_classif',
               '{{ taskf_destino("t", "ancora") }}',
               {{ 'TRUE' if taskf_gates_board("ancora") else 'FALSE' }},
               '{{ taskf_universos_do_destino("ancora") | map(attribute="nome") | join(",") }}'),
        STRUCT('remedicao',
               'smartbetting-dados.futebol_taskF.t_remedicao',
               FALSE,
               'janela_nova,janela_nova_nations_league',
               '{{ taskf_destino("t", "remedicao") }}',
               {{ 'TRUE' if taskf_gates_board("remedicao") else 'FALSE' }},
               '{{ taskf_universos_do_destino("remedicao") | map(attribute="nome") | join(",") }}'),
        STRUCT('remedicao_com_gate',
               'smartbetting-dados.futebol_taskF.t_remedicao_com_gate',
               TRUE,
               'janela_nova,janela_nova_nations_league',
               '{{ taskf_destino("t", "remedicao_com_gate") }}',
               {{ 'TRUE' if taskf_gates_board("remedicao_com_gate") else 'FALSE' }},
               '{{ taskf_universos_do_destino("remedicao_com_gate") | map(attribute="nome") | join(",") }}')
    ])
),

divergente AS (
    SELECT
        'destino_diverge_do_contrato' AS motivo,
        TO_JSON_STRING(c) AS linha
    FROM casos AS c
    WHERE tabela_obtida     IS DISTINCT FROM tabela_esperada
       OR gates_obtido      IS DISTINCT FROM gates_esperado
       OR universos_obtidos IS DISTINCT FROM universos_esperados
),

vacuo AS (
    SELECT 'caso_sumiu' AS motivo, TO_JSON_STRING(STRUCT(COUNT(*) AS casos, 4 AS esperados)) AS linha
    FROM casos
    HAVING COUNT(*) <> 4
)

SELECT motivo, linha FROM divergente
UNION ALL
SELECT motivo, linha FROM vacuo
