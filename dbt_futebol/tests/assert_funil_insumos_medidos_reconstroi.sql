{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DE RECONSTRUÇÃO DO VALOR MEDIDO (AE#153, Entrega 2 da #147/#148, ADR 0014): as três
-- colunas GRAVADAS no funil (`insumos_medidos`, `insumo_escopo`, `insumo_recorte`) batem com o
-- que os modelos de premissas e `taskf_eixos()` dizem HOJE.
--
-- Os mercados cobertos são os de `futebol_mercados_com_insumos_medidos()` (AE#208): 1X2
-- (AE#153), Handicap (AE#202) e Ambos marcam (AE#208). Os outros publicam array VAZIO (`[]`,
-- não NULL — ver ⚠️ mais abaixo), fora de escopo por decisão, não por defeito. Mercado com
-- linha (o Handicap) casa pela LINHA também (line_key): o conjunto de premissas muda com ela,
-- porque é a linha que diz se o lado é favorito ou azarão.
--
-- É ESTA guarda que amarra a lista da macro aos ramos do funil, que continuam escritos à mão:
-- mercado acrescentado à macro sem trocar o `[]` do ramo dele no funil acende aqui, na
-- primeira linha gravável.
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
-- ⚠️ A SEGUNDA DIREÇÃO — o que a comparação sozinha não pega, porque [] contra [] fecha:
--   * coluna que nunca chegou ao esquema (`append_new_columns` que não rodou) seria lida como
--     "reconstrói perfeitamente" — é o `insumo_escopo IS NULL`, mesmo motivo da guarda irmã;
--   * linha gravável que casou com o modelo e está vazia, nos mercados em que toda linha tem
--     valor medido (`toda_linha_tem_valor` na macro): Handicap desde a AE#202 (toda linha é
--     favorito ou azarão) e Ambos marcam desde a AE#208 (toda saída é Yes ou No, e as duas
--     têm premissa). Isso é defeito mesmo se o modelo também regrediu para [] — caso em que a
--     comparação fecha [] contra [] e não acende. No 1X2 não vale: o Draw é vazio por
--     construção.
{%- set eixos = taskf_eixos() %}
{%- set mercados = futebol_mercados_com_insumos_medidos() %}
{%- set slugs = [] %}
{%- set nunca_vazios = [] %}
{%- for m in mercados %}
    {%- do slugs.append("'" ~ futebol_mercados_pontuados()[m.market_id] ~ "'") %}
    {%- if m.toda_linha_tem_valor %}{%- do nunca_vazios.append('p' ~ m.market_id ~ '.fixture_id IS NOT NULL') %}{%- endif %}
{%- endfor %}
{%- set mercados_com_array = slugs | join(', ') %}
{#- A linha casou com um modelo em que nenhuma linha é vazia por construção. -#}
{%- set casou_nunca_vazio = '(' ~ (nunca_vazios | join(' OR ') if nunca_vazios else 'FALSE') ~ ')' %}
WITH fixtures AS (
    SELECT
        fixture_id,
        kickoff_utc AS _fx_kickoff_utc
    FROM {{ ref('fact_fixtures') }}
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
    FROM {{ ref('fact_value_funnel') }} f
    LEFT JOIN fixtures fx USING (fixture_id)
    -- só o que o funil ainda escreveria hoje — ver o cabeçalho.
    WHERE {{ futebol_funil_e_gravavel('fx._fx_kickoff_utc') }}
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
        CASE f.market
        {%- for m in mercados %}
            WHEN '{{ futebol_mercados_pontuados()[m.market_id] }}' THEN p{{ m.market_id }}.insumos_medidos
        {%- endfor %}
        END AS insumos_medidos_fresco,
        {{ casou_nunca_vazio }} AS casou_nunca_vazio
    FROM funil f
    -- LEFT: mercado sem modelo com a coluna não casa (insumos_medidos_fresco fica NULL) e a
    -- checagem abaixo só cobra os mercados cobertos. Fixture fail-open (ausente em
    -- fact_fixtures) TAMBÉM produz NULL aqui mesmo dentro de um mercado coberto — é o caso
    -- que o COALESCE(..., []) mais abaixo neutraliza. Mercado com linha casa por ela, com o
    -- mesmo predicado do ramo dele em fact_value_funnel.sql.
    {%- for m in mercados %}
    LEFT JOIN {{ ref(m.modelo) }} p{{ m.market_id }}
      ON  f.market = '{{ futebol_mercados_pontuados()[m.market_id] }}'
      AND p{{ m.market_id }}.fixture_id = f.fixture_id
      AND p{{ m.market_id }}.outcome    = f.outcome
      {%- if m.tem_linha %}
      AND COALESCE(CAST(p{{ m.market_id }}.line_value AS STRING), 'NONE') = f.line_key
      {%- endif %}
    {%- endfor %}
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
        WHEN market IN ({{ mercados_com_array }})
             AND TO_JSON_STRING(COALESCE(insumos_medidos, []))
                 IS DISTINCT FROM TO_JSON_STRING(COALESCE(insumos_medidos_fresco, []))
            THEN 'insumos_medidos gravado não bate com o que o modelo de premissas diz hoje'
        WHEN casou_nunca_vazio AND ARRAY_LENGTH(COALESCE(insumos_medidos, [])) = 0
            THEN 'linha gravável sem valor medido num mercado em que toda linha tem — o ramo do funil ainda grava []?'
        WHEN insumo_escopo != '{{ eixos.escopo }}' OR insumo_recorte != '{{ eixos.recorte }}'
            THEN 'insumo_escopo/insumo_recorte gravados não batem com taskf_eixos() de agora'
        ELSE NULL
    END AS diagnostico
FROM comparacao
WHERE insumo_escopo IS NULL
   OR (market IN ({{ mercados_com_array }})
       AND TO_JSON_STRING(COALESCE(insumos_medidos, []))
           IS DISTINCT FROM TO_JSON_STRING(COALESCE(insumos_medidos_fresco, [])))
   OR (casou_nunca_vazio AND ARRAY_LENGTH(COALESCE(insumos_medidos, [])) = 0)
   OR insumo_escopo != '{{ eixos.escopo }}'
   OR insumo_recorte != '{{ eixos.recorte }}'
ORDER BY fixture_id, market, outcome, line_key, janela
