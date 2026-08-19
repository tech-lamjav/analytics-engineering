{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DA DECOMPOSIÇÃO DA PENALIDADE GLOBAL (#87): a soma publicada e as quatro parcelas
-- publicadas ao lado dela contam a MESMA história, em toda linha do mart.
--
--   30*pen_odd_outlier + 12*pen_poucas_casas + 15*pen_odd_longshot + 10*pen_odd_juice
--   = penalidades_globais_pts
--
-- Por que ela existe. Até a #87 o mart calculava as quatro flags em todos os cinco ramos, as
-- usava para montar o `avisos[]` e as descartava na projeção final — só o agregado saía. Quem
-- precisava das parcelas (a RPC `get_futebol_fixture_value`, que remonta o aviso do lado do
-- app) as readivinhava do `int_futebol_odds_devig` por uma chave SEM `market_id` e SEM
-- `janela_usada`, e sem desempate nenhum no `order by`. Medido no prd em 18/08: em 59% das
-- linhas do board a janela readivinhada não era a publicada, e em 27% as flags contradiziam o
-- `penalidades_globais_pts` da própria linha. Essa contradição não era falsificável em lugar
-- nenhum — as parcelas não existiam no mart para serem comparadas com a soma. Agora existem,
-- e esta guarda é a comparação.
--
-- O que ela pega, que a construção não garante sozinha:
--
--   · ramo em que a flag e a soma passem a vir de `d` DIFERENTES (janelas ou mercados
--     distintos) — a soma seguiria plausível e as parcelas descreveriam outra linha;
--   · mudança de peso em `int_futebol_odds_devig` (30/12/15/10) que não seja refletida aqui,
--     ou vice-versa — os números vivem em dois lugares e nada além disto os amarra;
--   · o ramo da Dupla Chance, que monta a soma à mão (sem juice, pois o gate de odd >= 1,25 já
--     cobre o retorno mínimo) e carimba `pen_odd_juice = FALSE`. A identidade vale lá porque o
--     termo do juice zera; se alguém trouxer a flag verdadeira do `d` sem somar os 10 pontos,
--     ou somar os 10 sem trazer a flag, a linha aparece aqui.
--
-- ⚠️ O braço do NULL é separado de propósito. As quatro flags saem COALESCE(..., FALSE) do
-- de-vig hoje, então o `CAST(... AS INT64)` nunca vê NULL — mas se um refactor as deixar
-- passar nulas, a aritmética devolveria NULL, a comparação `!=` devolveria NULL, e a linha
-- sairia CALADA por esta guarda. É a mesma degradação graciosa que o CODING_STANDARDS exige do
-- Motor: insumo ausente vira FALSE, nunca NULL propagado — e aqui, nunca guarda cega.

SELECT
    fixture_id,
    market,
    outcome,
    line_value,
    janela_usada,
    penalidades_globais_pts,
    pen_odd_outlier,
    pen_poucas_casas,
    pen_odd_longshot,
    pen_odd_juice,
    ( 30 * CAST(pen_odd_outlier  AS INT64)
    + 12 * CAST(pen_poucas_casas AS INT64)
    + 15 * CAST(pen_odd_longshot AS INT64)
    + 10 * CAST(pen_odd_juice    AS INT64) ) AS soma_das_parcelas,
    CASE
        WHEN pen_odd_outlier IS NULL OR pen_poucas_casas IS NULL
          OR pen_odd_longshot IS NULL OR pen_odd_juice IS NULL
            THEN 'flag de penalidade nula — o de-vig parou de resolver ausência para FALSE e a soma virou NULL, não zero'
        ELSE 'a soma publicada não é a das quatro parcelas publicadas ao lado dela — flags e agregado vieram de janelas/mercados diferentes, ou os pesos 30/12/15/10 mudaram de um lado só'
    END AS diagnostico
FROM {{ ref('fact_value_opportunities') }}
WHERE pen_odd_outlier IS NULL
   OR pen_poucas_casas IS NULL
   OR pen_odd_longshot IS NULL
   OR pen_odd_juice IS NULL
   OR ( 30 * CAST(pen_odd_outlier  AS INT64)
      + 12 * CAST(pen_poucas_casas AS INT64)
      + 15 * CAST(pen_odd_longshot AS INT64)
      + 10 * CAST(pen_odd_juice    AS INT64) ) != penalidades_globais_pts
ORDER BY fixture_id, market, outcome, line_value
