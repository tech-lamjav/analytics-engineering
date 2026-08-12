{{ config(tags=['taskf', 'costura_b']) }}
-- COSTURA B da task [F] (issue #49, ticket #55), invariante 1 de 3 — AS QUATRO CÉLULAS SÃO O
-- MESMO UNIVERSO, MEDIDO NA MESMA EXECUÇÃO.
--
-- A [F] inteira é uma comparação ENTRE células: o efeito de cada eixo é a diferença entre duas
-- delas. Isso só significa alguma coisa se as duas mediram os mesmos jogos lendo a mesma
-- construção dos fatos — senão a diferença carrega dentro dela um jogo a mais, uma odd que mudou
-- de valor entre builds, e nada no número denuncia. Até a #54 isso era disciplina de execução
-- (a receita do analyses/taskf_teste2.sql); aqui vira cobrança.
--
-- O QUE É COBRADO, em quatro blocos, e cada um tem um modo de falha próprio:
--
--   celulas_faltando     as quatro células existem, com os nomes que taskf_nomes_de_celula()
--                        define. É também a guarda de NÃO-VACUIDADE de tudo o que vem abaixo:
--                        uma comparação "todas iguais" sobre uma tabela com uma célula só passa
--                        em branco, e é exatamente esse o estado da tabela no meio de uma
--                        medição interrompida.
--   rotulo_nao_casa_...  e o nome de cada célula casa com o par de eixos gravado ao lado dele.
--   universo_divergente  jogos, linhas e as duas pontas da janela idênticos nas quatro.
--   jogos_fora_do_gabarito  e os jogos são os 169 que o universo congelado declara
--                        (taskf_universo().jogos_esperados). Sem isto, quatro células medidas
--                        sobre o mesmo universo ERRADO passariam juntas.
--   execucao_divergente  as quatro leram a MESMA construção dos fatos, e leram ANTES de medir.
--
-- ⚠️ AS QUATRO CÉLULAS NÃO PRECISAM TER O MESMO NÚMERO DE LINHAS DE PREMISSA, e por isso isso não
-- é cobrado. Uma premissa entra na tabela quando acende pelo menos uma vez (`HAVING
-- COUNTIF(acesa) > 0` no Teste 2), e quais acendem depende do histórico que a célula enxerga.
-- Que hoje sejam 60 em todas as quatro é resultado medido, não invariante de construção — cobrar
-- isso seria congelar um dado como se fosse regra.
--
-- POR QUE `odds_loaded_at` É UMA COLUNA DA TABELA, E NÃO UMA LEITURA AO VIVO DO
-- `fact_odds_snapshot`. Duas razões, e a segunda é a que decide:
--
--   1. lida ao vivo, a resposta DECAI. Qualquer rebuild posterior no dataset de medição deixaria
--      a guarda vermelha sem que as quatro células tivessem deixado de ser comparáveis entre si —
--      e o que se quer afirmar é sobre elas, não sobre o estado atual do dataset;
--   2. um `ref()` aqui penduraria esta guarda no grafo do `fact_odds_snapshot`, e ela passaria a
--      ser arrastada por seleção indireta para dentro dos builds das fases 1 e 2 da medição —
--      onde ela é vermelha por construção, porque as células ainda não foram (re)medidas. Isso
--      obrigaria uma segunda `--exclude` na receita, e "a Costura A é a única exclusão que a
--      medição precisa" é promessa escrita em três lugares (#52). Lendo só `source()`, as três
--      guardas da Costura B ficam fora do grafo dos modelos e o problema não existe.
--
-- A forma verificável de "mesma execução" é a que a #51 definiu e a #54 usou: o `dbt_loaded_at`
-- do `fact_odds_snapshot` ANTERIOR aos `medido_em`. O que ela prova é que as quatro leram a mesma
-- construção dos fatos — mais forte do que os quatro carimbos serem próximos entre si, que é o
-- que uma régua de "rodou tudo na mesma meia hora" checaria.
--
-- QUEM RODA. Não é o agendado: as tags são `taskf`/`costura_b`, o pipeline horário executa
-- `dbt test --select tag:guarda`, e esta guarda fala de um dataset de medição que produção não
-- lê. Quem roda é a FASE 3 da receita do Teste 2, depois das quatro células:
--
--   dbt test --target taskF --select tag:costura_b
--
-- Falsificada de propósito trocando o `odds_loaded_at` de uma célula (e desfazendo em seguida);
-- os comandos e o resultado estão em `docs/TASKF_RESULTADOS.md`, seção do ticket #55.

{% set j = taskf_universo() %}
{% set nomes = taskf_nomes_de_celula().values() | list %}
-- Os 169 jogos e os quatro nomes de célula acima saem de macro (macros/taskf_universo.sql e
-- macros/taskf_celula.sql): esta guarda não tem número nem rótulo digitado.

WITH celulas AS (
    SELECT
        celula,
        ANY_VALUE(jogos_no_universo)  AS jogos_no_universo,
        ANY_VALUE(linhas_no_universo) AS linhas_no_universo,
        ANY_VALUE(janela_ini)         AS janela_ini,
        ANY_VALUE(janela_fim)         AS janela_fim,
        ANY_VALUE(odds_loaded_at)     AS odds_loaded_at,
        MIN(medido_em)                AS medido_em,
        -- Dentro de UMA célula os cinco campos acima são constantes por construção (saem de um
        -- CROSS JOIN de CTE de uma linha só). COUNT(DISTINCT) confere isso em vez de supor: se um
        -- INSERT parcial misturar duas execuções sob o mesmo rótulo, o ANY_VALUE acima escolheria
        -- uma delas em silêncio. TO_JSON_STRING e não FORMAT: FORMAT devolve NULL se QUALQUER
        -- argumento for NULL, e a linha NULL sai do COUNT(DISTINCT) — uma célula com metade das
        -- linhas sem carimbo contaria 1 e passaria.
        COUNT(DISTINCT TO_JSON_STRING(STRUCT(
            jogos_no_universo, linhas_no_universo,
            janela_ini, janela_fim, odds_loaded_at))) AS versoes_na_celula
    FROM {{ source('futebol_taskF', 'taskf_teste2') }}
    GROUP BY celula
),

esperadas AS (
    SELECT nome FROM UNNEST({{ nomes | tojson }}) AS nome
),

-- 1. AS QUATRO EXISTEM. Nos dois sentidos: célula que falta e célula com nome que o 2×2 não
--    define (que só aparece se alguém escrever na tabela por fora do taskf_celula()).
presenca AS (
    SELECT
        'celulas_faltando' AS motivo,
        TO_JSON_STRING(STRUCT(
            e.nome                                              AS celula_esperada,
            c.celula                                            AS celula_encontrada,
            (SELECT COUNT(*) FROM celulas)                      AS celulas_na_tabela,
            {{ nomes | length }}                                AS celulas_esperadas
        )) AS linha
    FROM esperadas AS e
    FULL OUTER JOIN celulas AS c ON c.celula = e.nome
    WHERE e.nome IS NULL OR c.celula IS NULL
),

-- 1b. E O RÓTULO CASA COM OS EIXOS. Quem escreve pelo taskf_teste2.sql não consegue errar isto —
--     o nome é DERIVADO dos eixos por taskf_celula(). Mas a tabela é DDL num dataset onde um
--     UPDATE à mão cabe (a própria falsificação desta Costura B usou um), e a partir daí o
--     dicionário do 2×2 deixa de ser garantia e vira afirmação. Custa uma linha conferir.
rotulos AS (
    SELECT
        'rotulo_nao_casa_com_os_eixos' AS motivo,
        TO_JSON_STRING(STRUCT(celula, pit_escopo, pit_recorte, linhas)) AS linha
    FROM (
        SELECT celula, pit_escopo, pit_recorte, COUNT(*) AS linhas
        FROM {{ source('futebol_taskF', 'taskf_teste2') }}
        GROUP BY celula, pit_escopo, pit_recorte
    )
    WHERE celula IS DISTINCT FROM CASE
        {%- for chave, nome in taskf_nomes_de_celula().items() %}
        WHEN pit_escopo = '{{ chave.split('|')[0] }}' AND pit_recorte = '{{ chave.split('|')[1] }}'
            THEN '{{ nome }}'
        {%- endfor %}
    END
),

-- 2. O MESMO UNIVERSO. Comparação contra a primeira célula em ordem alfabética — um par por
--    célula divergente, e não um produto cartesiano de reclamações sobre a mesma diferença.
referencia AS (
    SELECT * FROM celulas ORDER BY celula LIMIT 1
),

universo AS (
    SELECT
        'universo_divergente' AS motivo,
        TO_JSON_STRING(STRUCT(
            c.celula, r.celula AS referencia,
            c.jogos_no_universo,  r.jogos_no_universo  AS jogos_ref,
            c.linhas_no_universo, r.linhas_no_universo AS linhas_ref,
            c.janela_ini, r.janela_ini AS janela_ini_ref,
            c.janela_fim, r.janela_fim AS janela_fim_ref,
            c.versoes_na_celula
        )) AS linha
    FROM celulas AS c
    CROSS JOIN referencia AS r
    WHERE c.jogos_no_universo  IS DISTINCT FROM r.jogos_no_universo
       OR c.linhas_no_universo IS DISTINCT FROM r.linhas_no_universo
       OR c.janela_ini         IS DISTINCT FROM r.janela_ini
       OR c.janela_fim         IS DISTINCT FROM r.janela_fim
       OR c.versoes_na_celula  <> 1
),

-- 3. E É O UNIVERSO DECLARADO. `jogos_esperados` mora em macros/taskf_universo.sql, junto do
--    predicado que produz o recorte — as duas pontas não têm como divergir.
gabarito AS (
    SELECT
        'jogos_fora_do_gabarito' AS motivo,
        TO_JSON_STRING(STRUCT(
            celula, jogos_no_universo, {{ j.jogos_esperados }} AS jogos_esperados,
            '{{ j.ini }}' AS universo_ini, '{{ j.teto_utc }}' AS universo_teto_utc
        )) AS linha
    FROM celulas
    WHERE jogos_no_universo IS DISTINCT FROM {{ j.jogos_esperados }}
),

-- 4. A MESMA EXECUÇÃO, nas duas pontas: mesma construção dos fatos nas quatro, e os fatos
--    construídos ANTES de a célula ser medida. A segunda ponta é o que pega o caso em que alguém
--    rebuilda a ancestria e esquece de re-medir — ali as quatro continuariam com o mesmo
--    `odds_loaded_at` entre si, mas ele seria posterior aos `medido_em`.
execucao AS (
    SELECT
        'execucao_divergente' AS motivo,
        TO_JSON_STRING(STRUCT(
            c.celula, r.celula AS referencia,
            c.odds_loaded_at, r.odds_loaded_at AS odds_loaded_at_ref,
            c.medido_em,
            c.odds_loaded_at IS DISTINCT FROM r.odds_loaded_at AS leu_outra_construcao,
            NOT (c.odds_loaded_at < c.medido_em)                AS medida_antes_dos_fatos
        )) AS linha
    FROM celulas AS c
    CROSS JOIN referencia AS r
    WHERE c.odds_loaded_at IS DISTINCT FROM r.odds_loaded_at
       OR c.odds_loaded_at IS NULL
       OR NOT (c.odds_loaded_at < c.medido_em)
)

SELECT motivo, linha FROM presenca
UNION ALL
SELECT motivo, linha FROM rotulos
UNION ALL
SELECT motivo, linha FROM universo
UNION ALL
SELECT motivo, linha FROM gabarito
UNION ALL
SELECT motivo, linha FROM execucao
