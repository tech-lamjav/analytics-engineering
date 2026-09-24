{#- Gera o valor MEDIDO de cada insumo, por premissa (e penalidade) — AE#153, Entrega 2 da
    #147/#148 (ADR 0014). Derivada do mesmo mapa `futebol_insumos_premissa()`, no mesmo
    espírito de `futebol_premissas_cegas` (macros/premissas_sem_dado.sql): gerado, nunca
    escrito à mão, porque uma premissa nova ou um insumo renomeado só precisa ser declarado
    no catálogo — aqui e em `futebol_premissas_cegas` herdam a mudança juntos.

    Diferença de propósito: `futebol_premissas_cegas` responde "isto acendeu por falta de
    insumo?" (booleano, resumido). Este macro responde "qual foi o número que existia?" —
    ARRAY<STRUCT<premissa, insumo, valor FLOAT64>>, uma entrada por (premissa-ou-penalidade,
    insumo) que SE APLICA à linha. Chamado de dentro do modelo, onde as colunas da CTE ainda
    existem como identificador bruto (mesmo lugar de onde `futebol_premissas_cegas` já lê).

    O NOME do insumo no STRUCT é literalmente o mesmo que `futebol_insumos_premissa()` já usa
    — é o que permite cruzar "sob qual regime" (a Entrega 1, ADR 0014) com "que valor teve"
    (esta entrega) pela mesma chave, sem tabela de tradução.

    TRÊS REGRAS, e nenhuma é decorativa:

      aplicável        — a premissa não se aplica à linha (ex.: outcome 'Draw' no 1X2, ou o
                         lado que não é o apostado num mercado com favorito/azarão) não gera
                         entrada nenhuma. Zero entradas ali é o comportamento certo, não uma
                         falha do gerador.
      insumo condicional — `{'col', 'quando'}` só entra quando a condição `quando` vale (ex.:
                         `mando` publica `pct_pts_home` OU `aprov_fora`, nunca os dois na
                         mesma linha — só o que de fato foi comparado).
      valor pode ser NULL — insumo sem dado (o mesmo NULL que `futebol_premissas_cegas` conta
                         como cegueira) ainda gera entrada, com `valor` NULL. É informação:
                         diz que o insumo existe e não tinha número, não que ele não existe.

    Inclui `tipo = 'premissa'` E `tipo = 'penalidade'` (ex.: `desfalque_proprio`) — a
    penalidade também mediu algo, mesmo não somando ao contador de cegueira. Ignora
    `tipo = 'marcador'` (ex.: `is_favorito` no Handicap): não tem insumo declarado, e
    marcador não é medição.

    Mesmo padrão de sentinela NULL + filtro final que `futebol_premissas_cegas` usa: cada
    STRUCT nasce com `premissa = NULL` quando a condição não vale, e o `WHERE premissa IS NOT
    NULL` de fora descarta essas entradas — não um `IF` por fora do UNNEST, porque BigQuery
    não permite `WHERE` dependente de posição dentro do literal do array.

    ⚠️ ARRAY NULL NÃO SOBREVIVE À ESCRITA (achado do code-review, medido contra o BigQuery
    real: `CAST(NULL AS ARRAY<...>)` escrito numa tabela volta como `[]`, nunca como NULL —
    `ARRAY_LENGTH` dá 0, não NULL). Por isso os mercados que ainda não publicam o array (todos
    menos 1X2 e, desde a AE#202, Handicap) usam
    `futebol_insumos_medidos_vazio()` (array VAZIO explícito) em vez de `CAST(NULL AS ...)`
    em `fact_value_funnel.sql` — escrever o que a coluna vai realmente guardar, em vez de um
    NULL que o BigQuery reescreveria em silêncio. Quem comparar `insumos_medidos` contra
    outra leitura (a guarda de reconstrução, por exemplo) tem de normalizar os dois lados
    com o MESMO `COALESCE(..., [])` — comparar direto um NULL de query viva com um `[]`
    gravado os trata como diferentes quando são a mesma ausência. -#}
{% macro futebol_insumos_medidos_tipo() -%}
ARRAY<STRUCT<premissa STRING, insumo STRING, valor FLOAT64>>
{%- endmacro %}

{% macro futebol_insumos_medidos_vazio() -%}
CAST([] AS {{ futebol_insumos_medidos_tipo() }})
{%- endmacro %}

{% macro futebol_insumos_medidos(modelo) %}
    {%- set itens = [] -%}
    {%- for p in futebol_insumos_premissa() if p.modelo == modelo and p.tipo in ['premissa', 'penalidade'] -%}
        {%- do itens.append(p) -%}
    {%- endfor -%}

    {%- if itens | length == 0 -%}
        {{ exceptions.raise_compiler_error(
            "futebol_insumos_medidos: nenhuma premissa/penalidade declarada para o modelo '" ~
            modelo ~ "' em futebol_insumos_premissa(). Nome do modelo errado ou mapa incompleto.") }}
    {%- endif -%}

    {%- set pares = [] -%}
    {%- for p in itens -%}
        {%- if not p.get('aplicavel') -%}
            {{ exceptions.raise_compiler_error(
                "futebol_insumos_medidos: '" ~ p.nome ~ "' (" ~ modelo ~
                ") não declara 'aplicavel' em futebol_insumos_premissa().") }}
        {%- endif -%}
        {%- for i in p.get('insumos', []) -%}
            {%- do pares.append((p, i)) -%}
        {%- endfor -%}
    {%- endfor -%}

    {%- if pares | length == 0 -%}
        {{ exceptions.raise_compiler_error(
            "futebol_insumos_medidos: nenhum insumo declarado para nenhuma premissa/penalidade "
            "de '" ~ modelo ~ "' — o array sairia sempre vazio.") }}
    {%- endif -%}

    ARRAY(
        SELECT AS STRUCT premissa, insumo, valor
        FROM UNNEST([
        {%- for p, i in pares %}
            STRUCT(
                IF(COALESCE(({{ p.aplicavel }})
                   {%- if i is mapping %} AND ({{ i.quando }}){% endif -%}
                   , FALSE), '{{ p.nome }}', CAST(NULL AS STRING)) AS premissa,
                '{{ futebol_insumo_nome(i) }}' AS insumo,
                CAST({{ futebol_insumo_nome(i) }} AS FLOAT64) AS valor
            ){{ "," if not loop.last }}
        {%- endfor %}
        ])
        WHERE premissa IS NOT NULL
    )
{%- endmacro %}
