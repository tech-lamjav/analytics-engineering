{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DO CONTADOR DE PREMISSAS SEM DADO (#41, ADR 0003): o contador tem de estar VIVO em
-- cada modelo de premissas — pelo menos uma linha com cegueira, onde o modelo tem linhas.
--
-- O modo de falha que ela existe para pegar é o de sempre neste ticket: o contador zerado que
-- se parece com "não faltou nada". Basta alguém reintroduzir um COALESCE numa `metrics`, ou
-- uma fonte a montante passar a preencher com zero em vez de não preencher, e o contador cai
-- para zero em silêncio — sem teste vermelho, sem linha a menos no board, sem nada que
-- distinga "o Motor sabe tudo" de "o Motor perdeu a capacidade de dizer o que não sabe".
--
-- É a única direção que pode ser cobrada dos DADOS. As outras três já estão asseguradas mais
-- cedo e mais forte, e cobrá-las aqui seria guarda vacuosa:
--
--   · premissa cega nunca está acesa — garantido por construção no futebol_premissas_cegas()
--     (a condição `NOT <premissa>` faz parte da expressão gerada);
--   · premissa nova não declarada, e mapa envelhecido — assert_premissas_insumo_declarado;
--   · premissa sem `aplicavel` ou sem insumo — erro de COMPILAÇÃO no gerador, que é antes de
--     existir dado para consultar.
--
-- NÃO É VACUOSA HOJE: a cegueira de xG sozinha atinge a maior parte das linhas de Copa do
-- Brasil (sem xG na fonte) e metade das de Série B. Se esta guarda ficar verde por vacuidade
-- algum dia, é porque o portfólio inteiro passou a ter todos os insumos — e aí ela vira o
-- aviso de que o contador pode ser aposentado, o que também é informação.
--
-- O `HAVING COUNT(*) > 0` existe para não acusar target recém-criado, em que o modelo ainda
-- não tem linha nenhuma: guarda cujo primeiro disparo é falso positivo morre ignorada.

{%- set modelos = [] %}
{%- for p in futebol_insumos_premissa() if p.modelo not in modelos %}
{%- do modelos.append(p.modelo) %}
{%- endfor %}

WITH por_modelo AS (
    {%- for modelo in modelos %}
    SELECT
        '{{ modelo }}'                       AS modelo,
        COUNT(*)                             AS n_linhas,
        COUNTIF(premissas_sem_dado > 0)      AS n_linhas_com_cegueira
    FROM {{ ref(modelo) }}
    HAVING COUNT(*) > 0
    {%- if not loop.last %}
    UNION ALL
    {%- endif %}
    {%- endfor %}
)

SELECT
    modelo,
    n_linhas,
    n_linhas_com_cegueira,
    'contador zerado no modelo inteiro — algum insumo voltou a chegar preenchido (COALESCE novo a montante?) e a cegueira deixou de ser detectável' AS diagnostico
FROM por_modelo
WHERE n_linhas_com_cegueira = 0
ORDER BY modelo
