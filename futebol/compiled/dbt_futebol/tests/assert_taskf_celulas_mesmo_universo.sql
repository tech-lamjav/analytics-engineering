
-- COSTURA B da task [F] (issue #49, ticket #55), invariante 1 de 3 — AS QUATRO CÉLULAS SÃO O
-- MESMO UNIVERSO, MEDIDO NA MESMA EXECUÇÃO.
--
-- A [F] inteira é uma comparação ENTRE células: o efeito de cada eixo é a diferença entre duas
-- delas. Isso só significa alguma coisa se as duas mediram os mesmos jogos lendo a mesma
-- construção dos fatos — senão a diferença carrega dentro dela um jogo a mais, uma odd que mudou
-- de valor entre builds, e nada no número denuncia. Até a #54 isso era disciplina de execução
-- (a receita do analyses/taskf_teste2.sql); aqui vira cobrança.
--
-- ⚠️ O GRÃO DA COBRANÇA É (UNIVERSO × CÉLULA) DESDE A #58. A tabela ganhou uma coluna de
-- universo — quais JOGOS entram na conta —, ortogonal à célula, que diz qual HISTÓRICO cada jogo
-- carrega. A invariante não é "a tabela inteira tem o mesmo universo": os universos têm contagens
-- diferentes DE PROPÓSITO, e é justamente essa diferença que a #58 mede. O que continua valendo,
-- e é o que sustenta toda comparação entre células, é que DENTRO de cada universo as quatro
-- células meçam os mesmos jogos. Ver macros/taskf_universos.sql.
--
-- O QUE É COBRADO, em cinco blocos, e cada um tem um modo de falha próprio:
--
--   celulas_faltando     as quatro células existem EM CADA UNIVERSO, com os nomes que
--                        taskf_nomes_de_celula() define. É também a guarda de NÃO-VACUIDADE de
--                        tudo o que vem abaixo: uma comparação "todas iguais" sobre uma tabela
--                        com uma célula só passa em branco, e é exatamente esse o estado da
--                        tabela no meio de uma medição interrompida.
--   rotulo_nao_casa_...  e o nome de cada célula casa com o par de eixos gravado ao lado dele.
--   universo_divergente  jogos, linhas e as duas pontas do corte idênticos nas quatro células
--                        DAQUELE universo.
--   jogos_fora_do_gabarito  e os jogos são os que o universo declara, nos universos que declaram
--                        um número (macros/taskf_universos.sql: os dois congelados têm gabarito,
--                        os dois estendidos não — ver o bloco). Sem isto, quatro células medidas
--                        sobre o mesmo universo ERRADO passariam juntas.
--   execucao_divergente  todas as linhas da tabela leram a MESMA construção dos fatos, leram
--                        ANTES de medir, e saíram do MESMO commit (com procedência declarada).
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




-- Os jogos esperados e os quatro nomes de célula acima saem de macro (macros/taskf_universo.sql,
-- macros/taskf_universos.sql e macros/taskf_celula.sql): esta guarda não tem número nem rótulo
-- digitado.

WITH celulas AS (
    SELECT
        universo,
        celula,
        ANY_VALUE(jogos_no_universo)  AS jogos_no_universo,
        ANY_VALUE(linhas_no_universo) AS linhas_no_universo,
        ANY_VALUE(janela_ini)         AS janela_ini,
        ANY_VALUE(janela_fim)         AS janela_fim,
        ANY_VALUE(odds_loaded_at)     AS odds_loaded_at,
        ANY_VALUE(git_sha)            AS git_sha,
        MIN(medido_em)                AS medido_em,
        -- Dentro de UMA célula os seis campos acima são constantes por construção (saem de um
        -- CROSS JOIN de CTE de uma linha só). COUNT(DISTINCT) confere isso em vez de supor: se um
        -- INSERT parcial misturar duas execuções sob o mesmo rótulo, o ANY_VALUE acima escolheria
        -- uma delas em silêncio. TO_JSON_STRING e não FORMAT: FORMAT devolve NULL se QUALQUER
        -- argumento for NULL, e a linha NULL sai do COUNT(DISTINCT) — uma célula com metade das
        -- linhas sem carimbo contaria 1 e passaria.
        --
        -- ⚠️ `git_sha` PRECISA estar nesta lista, e o motivo é o pior caso dela: uma célula cujas
        -- linhas carreguem DOIS commits é achatada pelo ANY_VALUE antes de a terceira ponta da
        -- conferência de execução comparar coisa alguma — ou seja, a cobrança de "mesmo commit"
        -- passaria justamente no caso para o qual foi escrita.
        COUNT(DISTINCT TO_JSON_STRING(STRUCT(
            jogos_no_universo, linhas_no_universo,
            janela_ini, janela_fim, odds_loaded_at, git_sha))) AS versoes_na_celula
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    GROUP BY universo, celula
),

-- O produto (universo × célula) é o grão da cobrança desde a #58: cada universo tem de ter as
-- quatro células, e cada universo é conferido DENTRO de si. Cobrar sobre a tabela inteira daria
-- vermelho permanente pelo motivo errado — os universos têm contagens de jogos diferentes de
-- propósito, é exatamente essa diferença que a #58 mede.
esperadas AS (
    SELECT universo, nome
    FROM UNNEST(["completo", "sem_copa_mundo", "estendido", "estendido_sem_champions_classif"]) AS universo
    CROSS JOIN UNNEST(["base", "escopo", "recorte", "ambos"]) AS nome
),

-- 1. AS QUATRO EXISTEM, EM CADA UNIVERSO. Nos dois sentidos: par que falta e célula com nome que
--    o 2×2 não define (que só aparece se alguém escrever na tabela por fora do taskf_celula()).
--    Também pega universo que sumiu — um `--vars` que não passasse pela lista de macros/
--    taskf_universos.sql deixaria a tabela com três dos quatro, e "não medimos esse" se parece
--    demais com "esse deu igual".
presenca AS (
    SELECT
        'celulas_faltando' AS motivo,
        TO_JSON_STRING(STRUCT(
            e.universo                                          AS universo_esperado,
            c.universo                                          AS universo_encontrado,
            e.nome                                              AS celula_esperada,
            c.celula                                            AS celula_encontrada,
            (SELECT COUNT(*) FROM celulas)                      AS pares_na_tabela,
            16       AS pares_esperados
        )) AS linha
    FROM esperadas AS e
    FULL OUTER JOIN celulas AS c
      ON c.celula = e.nome AND c.universo = e.universo
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
        FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
        GROUP BY celula, pit_escopo, pit_recorte
    )
    WHERE celula IS DISTINCT FROM CASE
        WHEN pit_escopo = 'da_competicao' AND pit_recorte = 'temporada'
            THEN 'base'
        WHEN pit_escopo = 'todas' AND pit_recorte = 'temporada'
            THEN 'escopo'
        WHEN pit_escopo = 'da_competicao' AND pit_recorte = 'ultimos_10'
            THEN 'recorte'
        WHEN pit_escopo = 'todas' AND pit_recorte = 'ultimos_10'
            THEN 'ambos'
    END
),

-- 2. O MESMO UNIVERSO — DENTRO DE CADA UNIVERSO. Comparação contra a primeira célula em ordem
--    alfabética DAQUELE universo: um par por célula divergente, e não um produto cartesiano de
--    reclamações sobre a mesma diferença. Entre universos diferentes a contagem DEVE divergir, e
--    é por isso que a referência é por universo e não uma linha só da tabela.
referencia AS (
    SELECT * FROM celulas
    QUALIFY ROW_NUMBER() OVER (PARTITION BY universo ORDER BY celula) = 1
),

universo AS (
    SELECT
        'universo_divergente' AS motivo,
        TO_JSON_STRING(STRUCT(
            c.universo,
            c.celula, r.celula AS referencia,
            c.jogos_no_universo,  r.jogos_no_universo  AS jogos_ref,
            c.linhas_no_universo, r.linhas_no_universo AS linhas_ref,
            c.janela_ini, r.janela_ini AS janela_ini_ref,
            c.janela_fim, r.janela_fim AS janela_fim_ref,
            c.versoes_na_celula
        )) AS linha
    FROM celulas AS c
    JOIN referencia AS r ON r.universo = c.universo
    WHERE c.jogos_no_universo  IS DISTINCT FROM r.jogos_no_universo
       OR c.linhas_no_universo IS DISTINCT FROM r.linhas_no_universo
       OR c.janela_ini         IS DISTINCT FROM r.janela_ini
       OR c.janela_fim         IS DISTINCT FROM r.janela_fim
       OR c.versoes_na_celula  <> 1
),

-- 3. E É O UNIVERSO DECLARADO — onde há número a declarar. `jogos_esperados` mora em
--    macros/taskf_universos.sql, junto do predicado que produz cada recorte, e as duas pontas não
--    têm como divergir.
--
--    ⚠️ Só os DOIS UNIVERSOS CONGELADOS têm gabarito; os estendidos entram na lista com `none` e
--    ficam de fora deste bloco. Não é lacuna: eles crescem legitimamente a cada construção dos
--    fatos, e um número aqui viraria cobrança a atualizar toda execução — a espécie de guarda que
--    só ensina a ignorar guarda. O que vale para os quatro é o bloco 2 (as células concordarem
--    entre si dentro do universo), e ele não depende de gabarito nenhum.
gabarito AS (
    SELECT
        'jogos_fora_do_gabarito' AS motivo,
        TO_JSON_STRING(STRUCT(
            c.universo, c.celula, c.jogos_no_universo, g.jogos_esperados,
            '2026-06-16' AS universo_ini, '2026-08-04 12:00:00' AS universo_teto_utc
        )) AS linha
    FROM celulas AS c
    JOIN (
        SELECT 'completo' AS universo, 169 AS jogos_esperados
        UNION ALL
        SELECT 'sem_copa_mundo' AS universo, 90 AS jogos_esperados
        
    ) AS g ON g.universo = c.universo
    WHERE c.jogos_no_universo IS DISTINCT FROM g.jogos_esperados
),

-- 4. A MESMA EXECUÇÃO, em TRÊS pontas: mesma construção dos fatos nas quatro, fatos construídos
--    ANTES de a célula ser medida, e as quatro medidas do MESMO COMMIT.
--
--    A segunda ponta pega quem rebuilda a ancestria e esquece de re-medir — ali as quatro
--    continuariam com o mesmo `odds_loaded_at` entre si, mas ele seria posterior aos `medido_em`.
--
--    A terceira fecha o buraco que sobrava: dois fatos idênticos não impedem que o CÓDIGO que os
--    leu tenha mudado entre uma célula e outra. Medir a `base` num commit e a `ambos` noutro, sobre
--    os mesmos fatos, passaria pelas duas primeiras pontas e ainda assim compararia duas coisas
--    diferentes. `git_sha` é o único eixo de "mesma execução" que não precisa de régua arbitrária:
--    ou é o mesmo commit, ou não é. Um carimbo `desconhecido` (a var não foi passada) também cai —
--    célula sem procedência não sustenta afirmação nenhuma sobre execução, e é o mesmo argumento
--    do carimbo de procedência da imagem dbt (ADR 0001 do repo raiz).
--
--    ⚠️ O QUE ESTAS TRÊS PONTAS **NÃO** ALCANÇAM, e está medido: re-medir uma célula depois, sobre
--    fatos intocados e do mesmo commit, sai VERDE — e é o comportamento pretendido, porque a
--    definição de "mesma execução" que a #51 fixou é "as quatro leram a mesma construção dos
--    fatos". O que escapa aí é a deriva de reconstrução dos modelos: a própria #55 mediu 5 campos
--    em 7.200 mudando entre duas medições sobre os mesmos fatos, todos empates de arredondamento
--    do `AVG`. Nenhuma guarda distingue esse empate de um efeito real de 0,1 — quem quiser a
--    diferença mede com `analyses/taskf_remedicao.sql`, que é onde ela é visível.
-- A referência aqui é UMA linha da tabela inteira, e não uma por universo: os quatro universos de
-- uma célula saem do MESMO INSERT (compartilham `medido_em`, `git_sha` e `odds_loaded_at` por
-- construção), então "mesma execução" é uma afirmação sobre a tabela toda. Uma referência por
-- universo deixaria passar quatro medições feitas em quatro dias, cada uma internamente coerente.
referencia_global AS (
    SELECT * FROM celulas ORDER BY universo, celula LIMIT 1
),

execucao AS (
    SELECT
        'execucao_divergente' AS motivo,
        TO_JSON_STRING(STRUCT(
            c.universo,
            c.celula, r.celula AS referencia,
            c.odds_loaded_at, r.odds_loaded_at AS odds_loaded_at_ref,
            c.medido_em, c.git_sha, r.git_sha AS git_sha_ref,
            c.odds_loaded_at IS DISTINCT FROM r.odds_loaded_at AS leu_outra_construcao,
            NOT (c.odds_loaded_at < c.medido_em)                AS medida_antes_dos_fatos,
            c.git_sha IS DISTINCT FROM r.git_sha                AS outro_commit,
            c.git_sha = 'desconhecido'                          AS sem_procedencia
        )) AS linha
    FROM celulas AS c
    CROSS JOIN referencia_global AS r
    WHERE c.odds_loaded_at IS DISTINCT FROM r.odds_loaded_at
       OR c.odds_loaded_at IS NULL
       OR NOT (c.odds_loaded_at < c.medido_em)
       OR c.git_sha IS DISTINCT FROM r.git_sha
       OR c.git_sha = 'desconhecido'
       OR c.git_sha IS NULL
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