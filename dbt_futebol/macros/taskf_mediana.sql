{#
    MEDIANA EXATA E REPRODUTÍVEL, para agregado com GROUP BY.

    Por que existe. O caminho óbvio em BigQuery é `APPROX_QUANTILES(x, 2)[OFFSET(1)]`, e ele **não
    é reproduzível**: é um sketch, e o resultado depende de como a execução foi paralelizada.
    Medido durante a #57, sobre dado idêntico e query idêntica, em duas execuções seguidas: a
    mediana de `ppg` do histórico nativo do Brasileirão saiu 1,313 e depois 1,294, e a da Copa do
    Mundo saiu 1,333 e depois 1,0. `PERCENTILE_CONT` resolveria, mas é função analítica — não
    entra num SELECT com GROUP BY sem uma segunda passada.

    Isso importa mais aqui do que importaria em outro lugar: os números destas análises são
    PUBLICADOS em `docs/TASKF_RESULTADOS.md` e a task inteira se apoia em comparar execuções.
    Este repositório já gastou tempo caçando bug inexistente atrás de número que se mexia sozinho
    (a instabilidade do mercado de Gols, em `docs/TASK01_RESULTADOS.md`); uma segunda fonte de
    ruído, essa evitável, não vale a economia de uma linha.

    A forma abaixo ordena o grupo inteiro e indexa — exata por construção, determinística, e o
    custo é irrelevante nas dezenas de milhares de linhas que estas análises agregam. Para
    contagem par devolve o menor dos dois centrais (mediana inferior), o que é declarado e não
    descoberto. Grupo em que TODOS os valores são NULL devolve NULL: o array sai vazio, `DIV(-1,
    2)` dá 0 e o `SAFE_OFFSET` de um array vazio é NULL — a mesma degradação graciosa do resto do
    projeto, e está coberto pelo caso `c` do teste de mesa abaixo.

    ⚠️ O índice é calculado com `COUNTIF(... IS NOT NULL)`, e não com `ARRAY_LENGTH` do próprio
    agregado: o BigQuery recusa `ARRAY_AGG` dentro de `UNNEST` ("Aggregate function ARRAY_AGG not
    allowed in UNNEST"), que é a forma óbvia de dar nome ao array para medi-lo. As duas expressões
    são agregados do mesmo GROUP BY e contam o mesmo conjunto, porque as duas ignoram NULL.

    Teste de mesa (rodado): três grupos — 'a' com [1,2,3,NULL] devolve 2,0; 'b' com [10,20]
    devolve 10,0 (mediana inferior); 'c' com [NULL] devolve NULL.

    Uso (dentro de um SELECT com GROUP BY):

        SELECT competicao, {{ taskf_mediana('adv_ppg') }} AS ppg_mediana
        FROM ... GROUP BY competicao
#}

{% macro taskf_mediana(coluna, casas=3) %}
    ROUND(
        ARRAY_AGG({{ coluna }} IGNORE NULLS ORDER BY {{ coluna }})
            [SAFE_OFFSET(DIV(COUNTIF(({{ coluna }}) IS NOT NULL) - 1, 2))],
        {{ casas }})
{%- endmacro %}
