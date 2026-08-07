
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
-- ⚠️ VERDE POR VACUIDADE hoje, igual à assert_devig_conjunto_declarado: o mapa nasce
-- casando com a realidade, e a guarda é infalsificável em produção até o dia em que alguém
-- mexer num modelo — que é exatamente o dia em que precisamos confiar nela. Por isso foi
-- dirigida ao vermelho NAS DUAS DIREÇÕES durante a implementação (#39): retirando uma
-- premissa do mapa (acusou as 36 restantes) e declarando uma inexistente (acusou a órfã).

WITH declarado AS (
    SELECT * FROM UNNEST([
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'forca_mismatch' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'superioridade_xg' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'mando' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'desfalque_adversario' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'superioridade_tabela' AS nome, 'premissa' AS tipo, 4 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'forma' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'h2h_favoravel' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'pick_empate' AS nome, 'penalidade' AS tipo, 0 AS n_insumos),
        STRUCT('int_futebol_premissas_1x2' AS modelo, 'desfalque_proprio' AS nome, 'penalidade' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'is_favorito' AS nome, 'marcador' AS tipo, 0 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'is_azarao' AS nome, 'marcador' AS tipo, 0 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'supremacia' AS nome, 'premissa' AS tipo, 4 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'tende_golear' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'adversario_fragil_fora' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'mando_forte' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'sem_rodizio' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'raramente_perde_por_2' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'defesa_fora_solida' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'favorito_irregular' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ah' AS modelo, 'handicap_alto' AS nome, 'penalidade' AS tipo, 0 AS n_insumos),
        STRUCT('int_futebol_premissas_btts' AS modelo, 'ambos_marcam' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_btts' AS modelo, 'ataque_dos_dois' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_btts' AS modelo, 'defesas_vazaveis' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_btts' AS modelo, 'historico_btts' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_btts' AS modelo, 'defesa_forte' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_btts' AS modelo, 'ataque_trava' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_btts' AS modelo, 'historico_seco' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_dc' AS modelo, 'lado_coberto_forte' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_dc' AS modelo, 'equilibrio_defensivo' AS nome, 'premissa' AS tipo, 4 AS n_insumos),
        STRUCT('int_futebol_premissas_dc' AS modelo, 'adversario_limitado' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_dc' AS modelo, 'invicto_recente' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'ataque_combinado' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'defesas_vazaveis' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'xg_combinado_alto' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'ritmo_alto' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'ambos_vazam' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'historico_over' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'linha_subindo' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'defesas_firmes' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'clean_sheets_altos' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'xg_baixo_combinado' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'ataques_fracos' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'historico_under' AS nome, 'premissa' AS tipo, 2 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'linha_descendo' AS nome, 'premissa' AS tipo, 1 AS n_insumos),
        STRUCT('int_futebol_premissas_ou' AS modelo, 'linha_extrema' AS nome, 'penalidade' AS tipo, 0 AS n_insumos)
    ])
),

-- Colunas booleanas dos modelos de premissas, direto do catálogo do dataset.
--
-- O LIKE lê o catálogo, e o catálogo não é o DAG: sem as arestas abaixo esta guarda só
-- dependeria do 1X2, e num target novo poderia rodar antes de os outros quatro existirem —
-- acusando ~30 premissas como "o modelo não produz mais" quando o modelo apenas ainda não
-- foi construído. Guarda cujo primeiro disparo é falso positivo morre ignorada.
-- depends_on: `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
-- depends_on: `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts`
-- depends_on: `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc`
-- depends_on: `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou`
observado AS (
    SELECT
        table_name  AS modelo,
        column_name AS nome
    FROM `smartbetting-dados.futebol.INFORMATION_SCHEMA.COLUMNS`
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