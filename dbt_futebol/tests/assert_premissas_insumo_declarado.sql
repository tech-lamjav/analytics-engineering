{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DO MAPA DE INSUMOS (#39): o declarado em futebol_insumos_premissa() tem que
-- corresponder às colunas booleanas que os modelos de premissas realmente produzem.
--
-- Cobre TRÊS pontos cegos. Os dois primeiros são simétricos; o terceiro é interno ao mapa:
--
-- 1. PREMISSA NÃO DECLARADA — coluna booleana nova num modelo, ausente do mapa. Sem esta
--    guarda ela nasceria MUDA: o contador de premissas_sem_dado a ignoraria, e "não contada"
--    é indistinguível de "não faltou". É o modo de falha que a ADR 0002 já pagou uma vez, no
--    mercado órfão.
-- 2. MAPA ENVELHECIDO — o mapa declara premissa que o modelo não produz mais (renomeada ou
--    removida). O contador passaria a somar sobre coluna inexistente, ou a errar o total em
--    silêncio.
-- 3. PREMISSA SEM INSUMO DECLARADO — está no mapa, com a lista de insumos vazia. É a podridão
--    por dentro: a premissa existe, a guarda das duas direções acima fica verde, e mesmo
--    assim o contador nunca a incrementa, porque não há nulidade nenhuma para ler. Vale só
--    para tipo='premissa' — penalidade e marcador legitimamente não têm insumo (pick_empate
--    depende do outcome, handicap_alto e linha_extrema da própria linha, e os dois marcadores
--    do sinal do handicap; todos sempre presentes).
--
-- Compara contra o CATÁLOGO (INFORMATION_SCHEMA), não contra os dados. Não há como uma
-- consulta a dados revelar uma coluna cujo nome não se conhece de antemão, e é exatamente
-- essa a direção 1. O LIKE cobre modelo de premissas NOVO sem precisar editar esta guarda —
-- mercado novo entra e as premissas dele já são exigidas no mapa.
--
-- A QUARTA direção — premissa declarada SEM condição de aplicabilidade (`aplicavel`) — não
-- está aqui de propósito: ela é cobrada mais cedo e mais forte, como erro de COMPILAÇÃO em
-- futebol_premissas_cegas(), que é antes de existir dado para consultar. Repeti-la como teste
-- de dados criaria uma guarda que nunca pode ficar vermelha (o modelo nem compila para ser
-- materializado), e guarda infalsificável ensina a ignorar as outras. Entrada com `modelo`
-- errado, que o gerador nunca vê, cai na direção 2 acima.
--
-- ⚠️ VERDE POR VACUIDADE hoje, igual à assert_devig_conjunto_declarado: o mapa nasce
-- casando com a realidade, e a guarda é infalsificável em produção até o dia em que alguém
-- mexer num modelo — que é exatamente o dia em que precisamos confiar nela. Por isso foi
-- dirigida ao vermelho NAS DUAS DIREÇÕES durante a implementação (#39): retirando uma
-- premissa do mapa (acusou as 36 restantes) e declarando uma inexistente (acusou a órfã).

WITH declarado AS (
    SELECT * FROM UNNEST([
        {%- for p in futebol_insumos_premissa() %}
        STRUCT('{{ p.modelo }}' AS modelo, '{{ p.nome }}' AS nome, '{{ p.tipo }}' AS tipo, {{ p.insumos | length }} AS n_insumos){{ "," if not loop.last }}
        {%- endfor %}
    ])
),

-- Colunas booleanas dos modelos de premissas, direto do catálogo do dataset.
--
-- O LIKE lê o catálogo, e o catálogo não é o DAG: sem as arestas abaixo esta guarda só
-- dependeria do 1X2, e num target novo poderia rodar antes de os outros quatro existirem —
-- acusando ~30 premissas como "o modelo não produz mais" quando o modelo apenas ainda não
-- foi construído. Guarda cujo primeiro disparo é falso positivo morre ignorada.
-- depends_on: {{ ref('int_futebol_premissas_ah') }}
-- depends_on: {{ ref('int_futebol_premissas_btts') }}
-- depends_on: {{ ref('int_futebol_premissas_dc') }}
-- depends_on: {{ ref('int_futebol_premissas_ou') }}
observado AS (
    SELECT
        table_name  AS modelo,
        column_name AS nome
    FROM `{{ ref('int_futebol_premissas_1x2').database }}.{{ ref('int_futebol_premissas_1x2').schema }}.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name LIKE 'int\\_futebol\\_premissas\\_%'
      AND data_type = 'BOOL'
)

SELECT
    COALESCE(o.modelo, d.modelo) AS modelo,
    COALESCE(o.nome, d.nome)     AS nome,
    d.tipo                       AS tipo_declarado,
    CASE
        WHEN d.nome IS NULL
            THEN 'coluna booleana no modelo e ausente do mapa — declarar em futebol_insumos_premissa() como premissa, penalidade ou marcador'
        WHEN o.nome IS NULL
            THEN 'o mapa declara o que o modelo não produz mais — remover do mapa ou restaurar no modelo'
        ELSE 'premissa declarada sem insumo — o contador nunca a incrementaria; declarar as colunas da CTE metrics de que ela depende'
    END AS diagnostico
FROM observado o
FULL OUTER JOIN declarado d
    ON  o.modelo = d.modelo
    AND o.nome   = d.nome
WHERE d.nome IS NULL
   OR o.nome IS NULL
   OR (d.tipo = 'premissa' AND d.n_insumos = 0)
ORDER BY modelo, nome
