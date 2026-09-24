{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DO LADO NO VALOR MEDIDO DO HANDICAP (AE#202). Toda linha de int_futebol_premissas_ah
-- publica em `insumos_medidos` SÓ premissas do lado dela (favorito OU azarão), e nunca publica
-- vazio — toda linha é um dos dois desde o B3 (#109), que acabou com o pick.
--
-- É isto que decidiu o grão do fact_insumos_medidos no Handicap (uma linha por linha de
-- handicap, #202): o mesmo lado é favorito numa linha e azarão na outra, e o que muda entre
-- elas é o conjunto de premissas medidas. O unit test do fact recebe esse conjunto pronto no
-- mock; esta guarda confere o conjunto que o modelo de verdade produz.
--
-- Os conjuntos por lado saem do catálogo futebol_insumos_premissa() pelo `aplicavel` de cada
-- premissa — nunca escritos aqui à mão. Premissa nova de favorito/azarão entra sozinha.
{%- set favorito = [] -%}
{%- set azarao = [] -%}
{%- for p in futebol_insumos_premissa() if p.modelo == 'int_futebol_premissas_ah' and p.tipo == 'premissa' -%}
    {%- if p.aplicavel.startswith('is_favorito') -%}{%- do favorito.append(p.nome) -%}
    {%- elif p.aplicavel.startswith('is_azarao') -%}{%- do azarao.append(p.nome) -%}
    {%- else -%}
        {{ exceptions.raise_compiler_error(
            "assert_ah_insumos_medidos_do_lado: premissa '" ~ p.nome ~ "' do Handicap com aplicavel '"
            ~ p.aplicavel ~ "' — nem favorito nem azarão. Esta guarda precisa aprender o lado novo.") }}
    {%- endif -%}
{%- endfor -%}
{%- if favorito | length == 0 or azarao | length == 0 -%}
    {{ exceptions.raise_compiler_error(
        "assert_ah_insumos_medidos_do_lado: catálogo sem premissa de favorito ou de azarão no Handicap.") }}
{%- endif %}

WITH linhas AS (
    SELECT
        fixture_id,
        outcome,
        line_value,
        is_favorito,
        is_azarao,
        insumos_medidos
    FROM {{ ref('int_futebol_premissas_ah') }}
)

SELECT
    fixture_id,
    outcome,
    line_value,
    is_favorito,
    is_azarao,
    CASE
        WHEN ARRAY_LENGTH(insumos_medidos) = 0
            THEN 'linha do Handicap sem valor medido — toda linha é favorito ou azarão'
        ELSE 'premissa medida fora do lado desta linha'
    END AS diagnostico
FROM linhas
WHERE ARRAY_LENGTH(insumos_medidos) = 0
   OR EXISTS (
        SELECT 1
        FROM UNNEST(insumos_medidos) AS im
        WHERE (is_favorito AND im.premissa NOT IN ('{{ favorito | join("', '") }}'))
           OR (is_azarao   AND im.premissa NOT IN ('{{ azarao | join("', '") }}'))
   )
