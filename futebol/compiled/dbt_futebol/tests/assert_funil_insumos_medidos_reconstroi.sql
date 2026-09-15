
-- GUARDA DE RECONSTRUÇÃO DO VALOR MEDIDO (AE#153, Entrega 2 da #147/#148, ADR 0014): as três
-- colunas GRAVADAS no funil (`insumos_medidos`, `insumo_escopo`, `insumo_recorte`) batem com o
-- que `int_futebol_premissas_1x2` e `taskf_eixos()` dizem HOJE.
--
-- Só o 1X2 tem `insumos_medidos` nesta entrega — os outros quatro mercados publicam array
-- VAZIO (`[]`, não NULL — ver ⚠️ mais abaixo), fora de escopo por decisão, não por defeito.
--
-- ⚠️ `insumo_escopo`/`insumo_recorte` são escalares do BUILD INTEIRO — a mesma var vale pra
-- toda linha de toda execução — então a comparação é contra o LITERAL de `taskf_eixos()`
-- lido agora, não contra um join. Se `pit_escopo`/`pit_recorte` mudarem de default entre a
-- gravação e esta checagem, é EXATAMENTE isso que a guarda tem de acender: o carimbo por
-- linha existe para essa mudança não passar em silêncio.
--
-- `insumos_medidos` compara via TO_JSON_STRING: BigQuery não tem `=`/`IS DISTINCT FROM` para
-- ARRAY. As duas pontas vêm do MESMO gerador (`futebol_insumos_medidos()`, lido pelo modelo
-- de premissas), então a ordem dos campos dentro do STRUCT é estável — não é comparação
-- textual arbitrária, é a mesma serialização dos dois lados.
--
-- ⚠️ COALESCE(..., []) NOS DOIS LADOS antes de serializar (achado do code-review, medido
-- contra o BigQuery real): array NULL não sobrevive à escrita — a coluna gravada em
-- `fact_value_funnel` já chega como `[]`, nunca NULL (ver macro). Mas o LEFT JOIN abaixo
-- é de QUERY VIVA, e fixture ausente em `fact_fixtures` (fail-open, ADR 0011/0003) faz
-- `int_futebol_premissas_1x2` não ter linha nenhuma pra esse fixture — `insumos_medidos_
-- fresco` sai NULL de verdade nesse caso, não `[]`. Sem o COALESCE, `"[]" IS DISTINCT
-- FROM NULL` dá TRUE e a guarda acende sobre uma linha que não tem defeito nenhum — é
-- exatamente o mesmo fail-open que a guarda irmã (`assert_funil_reconcilia_com_devig`)
-- já trata com LEFT + fail-open, só que aqui a armadilha é do TIPO array, não do JOIN.
--
-- ⚠️ ESCOPADA AO QUE AINDA É GRAVÁVEL (mesmo motivo da guarda irmã de `nota_contexto`): a
-- coluna chega por `append_new_columns`, e o funil só escreve linha cujo kickoff está no
-- futuro (ADR 0011). Linha já congelada antes deste deploy fica com as três colunas NULL
-- para sempre — não é defeito, é o append-only funcionando, e o Victor aceitou esse custo
-- explicitamente (comentário de 09/09 na ClickUp `wdx6zevnj0`).
--
-- ⚠️ A SEGUNDA DIREÇÃO — linha gravável do 1X2 com `insumos_medidos` vazio — está aqui pelo
-- mesmo motivo da guarda irmã: sem ela, uma coluna que nunca chegou ao esquema (`
-- append_new_columns` que não rodou) seria lida como "reconstrói perfeitamente" (NULL contra
-- NULL fecha).
WITH fixtures AS (
    SELECT
        fixture_id,
        kickoff_utc AS _fx_kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

funil AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        f.line_key,
        f.janela,
        f.insumos_medidos,
        f.insumo_escopo,
        f.insumo_recorte
    FROM `smartbetting-dados`.`futebol`.`fact_value_funnel` f
    LEFT JOIN fixtures fx USING (fixture_id)
    -- só o que o funil ainda escreveria hoje — ver o cabeçalho.
    WHERE COALESCE(fx._fx_kickoff_utc > CURRENT_TIMESTAMP(), TRUE)
),

comparacao AS (
    SELECT
        f.fixture_id,
        f.market,
        f.outcome,
        f.line_key,
        f.janela,
        f.insumos_medidos,
        f.insumo_escopo,
        f.insumo_recorte,
        p.insumos_medidos AS insumos_medidos_fresco
    FROM funil f
    -- LEFT: mercado fora do 1X2 não tem modelo com a coluna (insumos_medidos_fresco fica
    -- NULL) e a checagem abaixo só cobra 1X2 (WHEN market = ...). Fixture fail-open
    -- (ausente em fact_fixtures) TAMBÉM produz NULL aqui mesmo dentro do 1X2 — é o caso
    -- que o COALESCE(..., []) mais abaixo neutraliza.
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2` p
      ON  p.fixture_id = f.fixture_id
      AND p.outcome    = f.outcome
)

SELECT
    fixture_id,
    market,
    outcome,
    line_key,
    janela,
    insumo_escopo,
    insumo_recorte,
    CASE
        WHEN insumo_escopo IS NULL AND market IS NOT NULL
            THEN 'linha ainda gravável com insumo_escopo/insumo_recorte vazios — append_new_columns não rodou?'
        WHEN market = 'match_winner'
             AND TO_JSON_STRING(COALESCE(insumos_medidos, []))
                 IS DISTINCT FROM TO_JSON_STRING(COALESCE(insumos_medidos_fresco, []))
            THEN 'insumos_medidos gravado não bate com o que int_futebol_premissas_1x2 diz hoje'
        WHEN insumo_escopo != 'todas' OR insumo_recorte != 'ultimos_10'
            THEN 'insumo_escopo/insumo_recorte gravados não batem com taskf_eixos() de agora'
        ELSE NULL
    END AS diagnostico
FROM comparacao
WHERE insumo_escopo IS NULL
   OR (market = 'match_winner'
       AND TO_JSON_STRING(COALESCE(insumos_medidos, []))
           IS DISTINCT FROM TO_JSON_STRING(COALESCE(insumos_medidos_fresco, [])))
   OR insumo_escopo != 'todas'
   OR insumo_recorte != 'ultimos_10'
ORDER BY fixture_id, market, outcome, line_key, janela