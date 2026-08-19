/*
    [F-9] EXCLUIR UM CONJUNTO DE JOGOS DA BASE DE MEDIÇÃO MUDA A ORDENAÇÃO DAS PREMISSAS? —
    medido COM e SEM, sobre a mesma materialização das quatro células.

    A spec #49 pede duas recomendações do mesmo tipo (user stories 7 e 24): a Copa do Mundo deve
    sair da base de medição, já que ali o deserto de histórico é real e ela pesa 47% da amostra? E
    a mesma pergunta para a fase classificatória da Champions. O critério de aceite da #58 é
    explícito sobre COMO responder: "a recomendação sai do efeito na ordenação das premissas, não
    do bom senso — o argumento de princípio fica declarado como reserva".

    Esta análise é esse efeito. Ela não decide nada sozinha: emite as três métricas declaradas
    abaixo, o veredito mecânico delas, e o contraste de referência que dá escala ao veredito.

    ────────────────────────────────────────────────────────────────────────────────
    A RÉGUA, DECLARADA ANTES DE MEDIR

    Mesmo padrão da tolerância da #51: o número existe antes do resultado, para não ser escolhido
    depois de ver qual lado ele favorece.

    ⚠️ O paralelo vale para o MÉTODO, não para o número: aquela tolerância era 0,5 pp e a #92 a
    remediu para 0,25 pp — ou seja, "declarado antes de medir" foi o começo dela, e não onde ela
    ficou. Declarar antes protege da escolha conveniente; não dispensa remedir quando o fenômeno
    que justificava o número muda.

    O que é ORDENAR. As 39 premissas do benchmark preferido (`usado_para_peso`), ordenadas por
    `diferenca_p<piso>` — o sinal medido, decrescente. É a ordenação que a [B] leria para decidir
    em quem mexer.

    TRÊS MÉTRICAS, por (célula, piso):

      rho             correlação de Spearman entre as duas ordenações (Pearson sobre os postos).
                      1,0 = a exclusão não mexeu em nada; 0 = a ordenação virou outra.
      trocas_no_topo  quantas premissas entram ou saem do TOP 5 por `peso_p<piso>`. O peso é o que
                      a [B] usaria como peso, e o topo é onde uma decisão de fato acontece.
      trocas_de_sinal quantas das 39 trocam o SINAL da diferença. Trocar de sinal é mudar a
                      resposta ("essa premissa tem ganho" ↔ "não tem"), não a posição.

    VEREDITO. A exclusão é MATERIAL naquele (célula, piso) quando QUALQUER uma valer:

        rho < 0,90     OU     trocas_no_topo >= 2     OU     trocas_de_sinal >= 4

    Fora disso, IMATERIAL. Os três cortes são grosseiros de propósito: eles separam "a ordenação
    é outra" de "a ordenação é a mesma com ruído", e não pretendem medir significância.

    ⚠️ E POR ISSO O CONTRASTE DE REFERÊNCIA VEM JUNTO. Um `rho` de 0,93 não diz nada sozinho —
    0,93 é muito ou pouco? A referência responde: as MESMAS três métricas para o par de células
    `base` → `escopo` DENTRO do universo COM. Esse é o efeito que a [F] existe para medir e que a
    #53 chamou de grande (30,6% dos pares ganham histórico, o piso 5 vai de 69 para 92 jogos). Se
    a exclusão mexer na ordenação MENOS do que o eixo que a task mede, ela é ruído perto do que se
    está medindo; se mexer mais, a base de medição está sendo decidida por ela.

    ⚠️ O QUE FAZER SE O VEREDITO SAIR AMBÍGUO — declarado agora, para não ser escolhido depois. Se
    as métricas caírem perto dos cortes (rho entre 0,88 e 0,92, ou trocas_no_topo = 1 com
    trocas_de_sinal = 3), a resposta NÃO é arredondar para o lado conveniente: é acrescentar um
    universo de placebo — remover N jogos sorteados por hash, do mesmo tamanho do conjunto
    excluído — e comparar a exclusão real contra a distribuição do placebo. Isso é uma medição a
    mais (um universo novo em macros/taskf_universos.sql e a re-medição das quatro células), e não
    foi feita de partida porque a exclusão da Copa do Mundo se sobrepõe ao piso de amostra (bloco
    `excluido` abaixo): no piso 5 quase todos os jogos que ela remove JÁ estavam fora.

    ────────────────────────────────────────────────────────────────────────────────
    OS SETE BLOCOS

      universo    quantos jogos e linhas cada universo tem, por célula, e quantos a exclusão
                  remove. É a conferência de que o par pedido é encaixado (SEM ⊂ COM) e não-vazio
                  — duas coisas que, se falharem, fazem o resto da saída parecer resultado.
      excluido    QUEM são os jogos removidos: quanto histórico eles têm e quantos deles já
                  estavam abaixo do piso de amostra. É aqui que se vê a sobreposição entre excluir
                  e usar piso — e ela é o mecanismo por trás do veredito, não um detalhe.
      composicao  o universo COM por competição. No par da Copa do Mundo ele reproduz a
                  composição dos 169 que a #51 publicou; no par da Champions ele é a composição do
                  universo ESTENDIDO, que é o que a user story 5 da #58 pede reportado à parte.
      fases       os jogos removidos por (competição, fase), contra o total daquela competição no
                  universo COM. É o que transforma "excluir a fase classificatória ≡ excluir a
                  Champions **nesta janela**" de afirmação em número.
      fora_do_universo  as partidas ENCERRADAS das competições que a exclusão toca e que mesmo
                  assim não entram no universo, por fase e por status. É o que separa "não
                  medimos" de "não aconteceu" — e responde de uma vez as duas perguntas que
                  costumam vir depois de uma contagem baixa: a partida sem preço coletado e a que
                  terminou fora do tempo normal (`status_short <> 'FT'`, o filtro do
                  task01_base(); ver a issue #71).
      ordenacao   as três métricas e o veredito, por (contraste, piso) — as quatro células mais o
                  contraste de referência.
      topo        as premissas que ENTRARAM ou SAÍRAM do top {{ n_topo }}, com posição e peso dos
                  dois lados. Sem ele, `trocas_no_topo = 2` é um número sem conteúdo: não dá para
                  saber se foi uma permuta adjacente na fronteira ou duas premissas atravessando a
                  tabela inteira, e as duas coisas pedem leituras opostas.

    ────────────────────────────────────────────────────────────────────────────────
    AS COLUNAS `a`, `b`, `c` MUDAM DE SENTIDO POR BLOCO — é o preço de sete blocos num UNION, e a
    legenda é esta (o `detalhe` traz o resto sempre):

      universo          a = jogos no COM      b = jogos no SEM     c = jogos removidos
      excluido          a = jogos excluídos   b = min_jogos médio  c = excluídos acima do piso 5
      composicao        a = jogos             b = % do universo    c = jogos removidos
      fases             a = jogos na fase     b = jogos removidos  c = —
      fora_do_universo  a = partidas de fora  b = com preço        c = —
      ordenacao         a = rho               b = trocas no topo   c = trocas de sinal
      topo              a = posição no COM    b = posição no SEM   c = peso no COM

    ────────────────────────────────────────────────────────────────────────────────
    COMO RODAR (do dbt_futebol/), depois das quatro células medidas:

      # Copa do Mundo (default)
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_exclusao
      bq query --use_legacy_sql=false --project_id=smartbetting-dados --max_rows=500 \
        < target/compiled/dbt_futebol/analyses/taskf_exclusao.sql

      # Champions, fase classificatória
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_exclusao \
        --vars '{taskf_universo_com: estendido,
                 taskf_universo_sem: estendido_sem_champions_classif}'

    ⚠️ `--max_rows` não é enfeite: o `bq query` trunca a saída em 100 linhas SEM AVISAR, e esta
    análise emite mais do que isso. Foi assim que a #57 quase publicou uma conta pela metade.

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set u_com = taskf_universo_valido(var('taskf_universo_com', 'completo')) -%}
{%- set u_sem = taskf_universo_valido(var('taskf_universo_sem', 'sem_copa_mundo')) -%}
{%- if u_com == u_sem -%}
    {{ exceptions.raise_compiler_error(
        "taskf_universo_com e taskf_universo_sem são o mesmo universo ('" ~ u_com ~ "') — nada a excluir.") }}
{%- endif -%}

{%- set celulas = taskf_nomes_de_celula().values() | list -%}
{%- set pisos   = taskf_pisos() -%}
{%- set carimbos = source('futebol_taskF', 'taskf_pit_por_celula') -%}
{%- set teste2   = source('futebol_taskF', 'taskf_teste2') -%}

{# A régua, num lugar só: os três cortes do veredito e o tamanho do topo. Estão aqui e não
    embutidos no SELECT porque são a régua declarada no cabeçalho, e uma régua que mora em três
    linhas de SQL diferentes deixa de ser uma régua. #}
{%- set n_topo               = 5    -%}
{%- set rho_minimo           = 0.90 -%}
{%- set trocas_topo_material = 2    -%}
{%- set trocas_sinal_material = 4   -%}

{# O contraste de referência: o par de células que dá escala ao veredito. `base` → `escopo` é o
    eixo de escopo isolado, o que a spec #49 chama de "juntar os campeonatos". #}
{%- set ref_a = 'base' -%}
{%- set ref_b = 'escopo' -%}


WITH {{ task01_base() }},

{# OS JOGOS, com o `round` que os predicados de universo precisam. `apostas` não o carrega — ele
    entra por join com o fact_fixtures, mesmo seam do `pit_disponivel` do analyses/taskf_teste2.sql
    e pelo mesmo motivo: o task01_base() é o artefato que produziu os números publicados da [0.1] e
    não é tocado por esta medição. O COALESCE evita que um `round` nulo faça o NOT(...) do universo
    de exclusão devolver NULL e sumir com a linha em silêncio. #}
jogos_marcados AS (
    SELECT DISTINCT
        a.fixture_id,
        a.competition,
        a.kickoff_utc,
        COALESCE(f.round, '') AS round
    FROM apostas AS a
    LEFT JOIN {{ ref('fact_fixtures') }} AS f
           ON f.fixture_id = a.fixture_id
),

{# Os dois predicados aplicados ao MESMO conjunto de jogos, lado a lado. Escrito assim — e não
    como dois SELECT filtrados — porque o que interessa é a DIFERENÇA entre eles, e uma diferença
    calculada por anti-join de duas listas esconde o caso em que o par não é encaixado. #}
classificado AS (
    SELECT
        j.*,
        {{ taskf_universo_predicado(u_com) }} AS no_com,
        {{ taskf_universo_predicado(u_sem) }} AS no_sem
    FROM jogos_marcados AS j
),

excluidos AS (
    SELECT * FROM classificado WHERE no_com AND NOT no_sem
),

{# O piso é propriedade do JOGO: o menor entre os dois times. Mesma construção do
    analyses/taskf_saturacao_recorte.sql, sobre o carimbo do PIT — que guarda o modelo inteiro, e
    por isso alcança também os jogos que só existem no universo estendido. #}
pit_por_jogo AS (
    SELECT
        celula,
        fixture_id,
        MIN(played_total_disponivel) AS min_disp
    FROM {{ carimbos }}
    GROUP BY celula, fixture_id
),

-- ── bloco `universo` ────────────────────────────────────────────────────────────────────────
{# Da tabela do Teste 2, e não recontado daqui: o que interessa é o universo que a MEDIÇÃO usou.
    Se esta análise contasse por conta própria, ela poderia discordar da tabela sem que ninguém
    notasse — e a discordância seria justamente sobre o que se está medindo. #}
universo_medido AS (
    SELECT
        celula,
        universo,
        ANY_VALUE(jogos_no_universo)  AS jogos,
        ANY_VALUE(linhas_no_universo) AS linhas,
        ANY_VALUE(janela_ini)         AS janela_ini,
        ANY_VALUE(janela_fim)         AS janela_fim,
        COUNT(*)                      AS linhas_de_premissa
    FROM {{ teste2 }}
    WHERE universo IN ('{{ u_com }}', '{{ u_sem }}')
    GROUP BY celula, universo
),

bloco_universo AS (
    SELECT
        c.celula,
        c.jogos                       AS jogos_com,
        s.jogos                       AS jogos_sem,
        c.jogos - s.jogos             AS jogos_removidos,
        c.linhas                      AS linhas_com,
        s.linhas                      AS linhas_sem,
        c.linhas_de_premissa          AS premissas_com,
        s.linhas_de_premissa          AS premissas_sem,
        c.janela_ini, c.janela_fim,
        s.janela_ini AS janela_ini_sem, s.janela_fim AS janela_fim_sem,
        (SELECT COUNT(*) FROM excluidos)                     AS jogos_excluidos_pelo_predicado,
        (SELECT COUNTIF(NOT no_com AND no_sem) FROM classificado) AS jogos_so_no_sem
    FROM universo_medido AS c
    JOIN universo_medido AS s
      ON s.celula = c.celula AND s.universo = '{{ u_sem }}'
    WHERE c.universo = '{{ u_com }}'
),

-- ── bloco `excluido` ────────────────────────────────────────────────────────────────────────
{# A sobreposição entre EXCLUIR e usar PISO, que é o mecanismo por trás do veredito. Um conjunto
    excluído que já estava quase todo abaixo do piso não tem como mudar a ordenação naquele piso —
    e é isso que separa "a exclusão não importa" de "a exclusão não importa AQUI". #}
bloco_excluido AS (
    SELECT
        p.celula,
        COUNT(*)                                   AS jogos_excluidos,
        ROUND(AVG(p.min_disp), 2)                  AS min_jogos_medio,
        MAX(p.min_disp)                            AS min_jogos_max
        {%- for piso in pisos %},
        COUNTIF(p.min_disp >= {{ piso }})          AS excluidos_acima_p{{ piso }}
        {%- endfor %}
    FROM excluidos AS e
    JOIN pit_por_jogo AS p USING (fixture_id)
    GROUP BY p.celula
),

{# O denominador: quantos jogos do universo COM passam cada piso. Sem ele, "3 excluídos acima do
    piso 5" não diz se isso é 3 de 92 ou 3 de 4. #}
bloco_denominador AS (
    SELECT
        p.celula,
        COUNT(*)                                   AS jogos_no_com
        {%- for piso in pisos %},
        COUNTIF(p.min_disp >= {{ piso }})          AS com_acima_p{{ piso }}
        {%- endfor %}
    FROM classificado AS c
    JOIN pit_por_jogo AS p USING (fixture_id)
    WHERE c.no_com
    GROUP BY p.celula
),

-- ── bloco `composicao` ──────────────────────────────────────────────────────────────────────
{# O universo COM inteiro, competição a competição. Sai daqui e não de uma contagem à parte porque
   é do MESMO `classificado` que os outros blocos leem — duas contagens do mesmo universo em
   lugares diferentes divergem uma hora, e a divergência seria muda. #}
bloco_composicao AS (
    SELECT
        c.competition,
        COUNT(*)                 AS jogos,
        COUNTIF(NOT c.no_sem)    AS jogos_removidos,
        MIN(DATE(c.kickoff_utc)) AS primeiro,
        MAX(DATE(c.kickoff_utc)) AS ultimo
    FROM classificado AS c
    WHERE c.no_com
    GROUP BY c.competition
),

-- ── bloco `fases` ───────────────────────────────────────────────────────────────────────────
{# Por (competição, fase), SÓ nas competições que a exclusão toca. A lista inteira teria uma
    linha por rodada de cada liga e afogaria o achado — e o achado aqui é de uma competição só:
    quanto da presença dela no universo a exclusão de FASE de fato remove. É este bloco que mede
    se "excluir a fase classificatória" e "excluir a competição" são a mesma coisa nesta janela,
    em vez de supor que sejam. #}
bloco_fases AS (
    SELECT
        c.competition,
        c.round,
        COUNT(*)                    AS jogos_no_com,
        COUNTIF(NOT c.no_sem)       AS jogos_removidos,
        MIN(DATE(c.kickoff_utc))    AS primeiro,
        MAX(DATE(c.kickoff_utc))    AS ultimo
    FROM classificado AS c
    WHERE c.no_com
      AND c.competition IN (SELECT DISTINCT competition FROM excluidos)
    GROUP BY c.competition, c.round
),

-- ── bloco `fora_do_universo` ────────────────────────────────────────────────────────────────
{# As encerradas que o universo NÃO alcança, nas competições que a exclusão toca. Duas causas
   possíveis e as duas importam: a partida não teve preço coletado (a coleta é forward-only e
   entra no ar quando a liga é lançada) ou ela terminou fora do tempo normal — o
   `jogos_encerrados` do task01_base() filtra `status_short = 'FT'`, então AET e PEN ficam de fora
   (achado da #56, issue #71).

   `com_preco` distingue as duas sem precisar de terceira consulta: partida encerrada, com preço
   coletado e ainda assim fora do universo só pode ter saído pelo status. #}
fora_do_universo AS (
    SELECT
        f.competition,
        f.round,
        f.status_short,
        COUNT(*) AS partidas,
        COUNTIF(o.fixture_id IS NOT NULL) AS com_preco,
        MIN(DATE(f.kickoff_utc)) AS primeiro,
        MAX(DATE(f.kickoff_utc)) AS ultimo
    FROM {{ ref('fact_fixtures') }} AS f
    LEFT JOIN (SELECT DISTINCT fixture_id FROM {{ ref('fact_odds_snapshot') }}) AS o
           ON o.fixture_id = f.fixture_id
    WHERE f.kickoff_utc >= TIMESTAMP('{{ taskf_universo().ini }}')
      AND f.status_short IN ('FT', 'AET', 'PEN')
      AND f.competition IN (SELECT DISTINCT competition FROM excluidos)
      AND f.fixture_id NOT IN (SELECT fixture_id FROM jogos_marcados)
    GROUP BY f.competition, f.round, f.status_short
),

-- ── bloco `ordenacao` ───────────────────────────────────────────────────────────────────────
{# Os lados de cada contraste. Quatro contrastes de EXCLUSÃO (a mesma célula, dois universos) e
    um de EIXO (o mesmo universo, duas células) — construídos pela mesma máquina de propósito: as
    métricas do contraste de referência têm de ser calculadas exatamente como as das exclusões,
    senão comparar uma com a outra não significa nada. #}
lados AS (
    {%- for cel in celulas %}
    SELECT 'exclusao__{{ cel }}' AS contraste, 'A' AS lado, mercado, premissa, benchmark,
           {% for piso in pisos %}diferenca_p{{ piso }}, peso_p{{ piso }}, n_p{{ piso }}{{ ', ' if not loop.last }}{% endfor %}
    FROM {{ teste2 }} WHERE usado_para_peso AND celula = '{{ cel }}' AND universo = '{{ u_com }}'
    UNION ALL
    SELECT 'exclusao__{{ cel }}', 'B', mercado, premissa, benchmark,
           {% for piso in pisos %}diferenca_p{{ piso }}, peso_p{{ piso }}, n_p{{ piso }}{{ ', ' if not loop.last }}{% endfor %}
    FROM {{ teste2 }} WHERE usado_para_peso AND celula = '{{ cel }}' AND universo = '{{ u_sem }}'
    UNION ALL
    {%- endfor %}
    SELECT 'eixo__{{ ref_a }}_{{ ref_b }}', 'A', mercado, premissa, benchmark,
           {% for piso in pisos %}diferenca_p{{ piso }}, peso_p{{ piso }}, n_p{{ piso }}{{ ', ' if not loop.last }}{% endfor %}
    FROM {{ teste2 }} WHERE usado_para_peso AND celula = '{{ ref_a }}' AND universo = '{{ u_com }}'
    UNION ALL
    SELECT 'eixo__{{ ref_a }}_{{ ref_b }}', 'B', mercado, premissa, benchmark,
           {% for piso in pisos %}diferenca_p{{ piso }}, peso_p{{ piso }}, n_p{{ piso }}{{ ', ' if not loop.last }}{% endfor %}
    FROM {{ teste2 }} WHERE usado_para_peso AND celula = '{{ ref_b }}' AND universo = '{{ u_com }}'
),

{# Os pisos viram LINHAS aqui. Mantidos como colunas, cada métrica teria de ser escrita quatro
    vezes — e quatro escritas do mesmo cálculo não ficam iguais para sempre. #}
longo AS (
    SELECT
        l.contraste, l.lado, l.mercado, l.premissa, l.benchmark,
        p.piso, p.diferenca, p.peso, p.n
    FROM lados AS l,
    UNNEST([
        {%- for piso in pisos %}
        STRUCT({{ piso }} AS piso, l.diferenca_p{{ piso }} AS diferenca,
               l.peso_p{{ piso }} AS peso, l.n_p{{ piso }} AS n){{ ',' if not loop.last }}
        {%- endfor %}
    ]) AS p
),

pareado AS (
    SELECT
        contraste, piso, mercado, premissa, benchmark,
        MAX(IF(lado = 'A', diferenca, NULL)) AS dif_a,
        MAX(IF(lado = 'B', diferenca, NULL)) AS dif_b,
        MAX(IF(lado = 'A', peso, NULL))      AS peso_a,
        MAX(IF(lado = 'B', peso, NULL))      AS peso_b,
        MAX(IF(lado = 'A', n, NULL))         AS n_a,
        MAX(IF(lado = 'B', n, NULL))         AS n_b,
        COUNTIF(lado = 'A') AS tem_a,
        COUNTIF(lado = 'B') AS tem_b
    FROM longo
    GROUP BY contraste, piso, mercado, premissa, benchmark
),

{# ⚠️ QUEM ENTRA NA CORRELAÇÃO, e por que a saída conta os dois grupos que ficam de fora.

    `sem_contraparte`  a premissa existe de um lado e não do outro. Acontece quando ela não acende
                       nenhuma vez naquele universo (o `HAVING COUNTIF(acesa) > 0` do Teste 2). É
                       ACHADO — uma premissa que some da base é o efeito mais forte que uma
                       exclusão pode ter —, e por isso é contada e reportada, não descartada em
                       silêncio.
    `sem_medida`       a premissa existe dos dois lados mas não tem diferença naquele piso
                       (n = 0: acende, mas nunca em jogo com histórico suficiente). Correlacionar
                       postos de NULL seria inventar ordem onde não há medida.

    A correlação sai do que sobra. Se sobrar pouco, o `n_premissas` na saída denuncia. #}
ranqueado AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY contraste, piso ORDER BY dif_a DESC) AS rank_a,
        RANK() OVER (PARTITION BY contraste, piso ORDER BY dif_b DESC) AS rank_b
    FROM pareado
    WHERE tem_a = 1 AND tem_b = 1
      AND dif_a IS NOT NULL AND dif_b IS NOT NULL
),

{# O TOPO por peso, com desempate DECLARADO. `ROW_NUMBER` e não `RANK` porque o topo tem de ter
    exatamente {{ n_topo }} elementos: com `RANK`, um empate de peso devolveria seis premissas num
    "top 5" e a contagem de trocas viraria outra coisa. O desempate por (mercado, premissa) é
    arbitrário e estável — ele só decide entre pesos IGUAIS, e nesse caso qualquer critério é
    arbitrário; o que não pode é ser instável entre os dois lados. #}
topo AS (
    SELECT
        contraste, piso, mercado, premissa, benchmark,
        ROW_NUMBER() OVER (PARTITION BY contraste, piso
                           ORDER BY peso_a DESC, mercado, premissa) AS pos_a,
        ROW_NUMBER() OVER (PARTITION BY contraste, piso
                           ORDER BY peso_b DESC, mercado, premissa) AS pos_b
    FROM pareado
    WHERE tem_a = 1 AND tem_b = 1
),

trocas_topo AS (
    SELECT
        contraste, piso,
        COUNTIF((pos_a <= {{ n_topo }}) != (pos_b <= {{ n_topo }})) AS entradas_e_saidas,
        STRING_AGG(IF(pos_a <= {{ n_topo }} AND pos_b > {{ n_topo }}, premissa, NULL),
                   ', ' ORDER BY pos_a) AS saiu_do_topo,
        STRING_AGG(IF(pos_b <= {{ n_topo }} AND pos_a > {{ n_topo }}, premissa, NULL),
                   ', ' ORDER BY pos_b) AS entrou_no_topo
    FROM topo
    GROUP BY contraste, piso
),

metricas AS (
    SELECT
        r.contraste,
        r.piso,
        COUNT(*)                                                   AS n_premissas,
        ROUND(CORR(r.rank_a, r.rank_b), 4)                         AS rho,
        COUNTIF(SIGN(r.dif_a) != SIGN(r.dif_b))                    AS trocas_de_sinal,
        ROUND(AVG(ABS(r.dif_a - r.dif_b)), 2)                      AS delta_dif_medio,
        MAX(ABS(r.rank_a - r.rank_b))                              AS max_delta_posto,
        ROUND(AVG(r.n_a), 1)                                       AS n_medio_a,
        ROUND(AVG(r.n_b), 1)                                       AS n_medio_b
    FROM ranqueado AS r
    GROUP BY r.contraste, r.piso
),

descartes AS (
    SELECT
        contraste, piso,
        COUNTIF(tem_a = 0 OR tem_b = 0)                                     AS sem_contraparte,
        COUNTIF(tem_a = 1 AND tem_b = 1
                AND (dif_a IS NULL OR dif_b IS NULL))                       AS sem_medida,
        STRING_AGG(IF(tem_a = 0 OR tem_b = 0, premissa, NULL), ', ')        AS quais_sem_contraparte
    FROM pareado
    GROUP BY contraste, piso
),

bloco_ordenacao AS (
    SELECT
        m.contraste,
        m.piso,
        m.rho,
        t.entradas_e_saidas AS trocas_no_topo,
        m.trocas_de_sinal,
        m.n_premissas,
        d.sem_contraparte,
        d.sem_medida,
        d.quais_sem_contraparte,
        t.saiu_do_topo,
        t.entrou_no_topo,
        m.delta_dif_medio,
        m.max_delta_posto,
        m.n_medio_a,
        m.n_medio_b,
        IF(m.rho < {{ rho_minimo }}
           OR t.entradas_e_saidas >= {{ trocas_topo_material }}
           OR m.trocas_de_sinal   >= {{ trocas_sinal_material }},
           'MATERIAL', 'IMATERIAL')                                          AS veredito
    FROM metricas AS m
    JOIN trocas_topo AS t USING (contraste, piso)
    JOIN descartes   AS d USING (contraste, piso)
),

{# QUEM entrou e quem saiu do topo, com posição e peso dos dois lados. Só os que se mexeram: o
   topo inteiro de cada (contraste, piso) seriam centenas de linhas, e o que a leitura precisa é
   do movimento. Sem este bloco, a caracterização de uma troca vira consulta ad-hoc — e número de
   documento que não sai de query commitada é número que ninguém confere depois. #}
bloco_topo AS (
    SELECT
        t.contraste,
        t.piso,
        t.premissa,
        t.mercado,
        t.pos_a,
        t.pos_b,
        p.peso_a,
        p.peso_b,
        IF(t.pos_a <= {{ n_topo }}, 'saiu', 'entrou') AS direcao
    FROM topo AS t
    JOIN pareado AS p USING (contraste, piso, mercado, premissa, benchmark)
    WHERE (t.pos_a <= {{ n_topo }}) != (t.pos_b <= {{ n_topo }})
)

-- ── saída ───────────────────────────────────────────────────────────────────────────────────
SELECT 1 AS ordem, 'universo' AS bloco,
    celula AS chave,
    IF(jogos_removidos > 0 AND jogos_so_no_sem = 0, 'OK', 'PAR_NAO_ENCAIXADO') AS veredito,
    CAST(jogos_com AS FLOAT64)       AS a,
    CAST(jogos_sem AS FLOAT64)       AS b,
    CAST(jogos_removidos AS FLOAT64) AS c,
    TO_JSON_STRING(STRUCT(
        '{{ u_com }}' AS universo_com, '{{ u_sem }}' AS universo_sem,
        linhas_com, linhas_sem, premissas_com, premissas_sem,
        janela_ini, janela_fim, janela_ini_sem, janela_fim_sem,
        jogos_excluidos_pelo_predicado, jogos_so_no_sem
    )) AS detalhe
FROM bloco_universo

UNION ALL
SELECT 2, 'excluido',
    e.celula,
    -- Quanto do conjunto excluído o piso 5 já removia por conta própria. É a leitura que decide
    -- se a exclusão tem como mudar alguma coisa naquele piso.
    FORMAT('%d de %d acima do piso 5', e.excluidos_acima_p5, e.jogos_excluidos),
    CAST(e.jogos_excluidos AS FLOAT64),
    e.min_jogos_medio,
    CAST(e.excluidos_acima_p5 AS FLOAT64),
    TO_JSON_STRING(STRUCT(
        e.min_jogos_max,
        {%- for piso in pisos %}
        e.excluidos_acima_p{{ piso }}, d.com_acima_p{{ piso }},
        {%- endfor %}
        d.jogos_no_com
    ))
FROM bloco_excluido AS e
JOIN bloco_denominador AS d USING (celula)

UNION ALL
SELECT 3, 'composicao',
    competition,
    IF(jogos_removidos = 0, 'INTACTA',
       IF(jogos_removidos = jogos, 'REMOVIDA_INTEIRA', 'PARCIAL')),
    CAST(jogos AS FLOAT64),
    ROUND(100 * jogos / SUM(jogos) OVER (), 1),
    CAST(jogos_removidos AS FLOAT64),
    TO_JSON_STRING(STRUCT(competition, jogos, jogos_removidos, primeiro, ultimo,
                          SUM(jogos) OVER () AS jogos_no_universo))
FROM bloco_composicao

UNION ALL
SELECT 4, 'fases',
    FORMAT('%s · %s', competition, round),
    IF(jogos_removidos = jogos_no_com, 'FASE_INTEIRA',
       IF(jogos_removidos = 0, 'INTACTA', 'PARCIAL')),
    CAST(jogos_no_com AS FLOAT64),
    CAST(jogos_removidos AS FLOAT64),
    NULL,
    TO_JSON_STRING(STRUCT(competition, round, jogos_no_com, jogos_removidos, primeiro, ultimo))
FROM bloco_fases

UNION ALL
SELECT 5, 'fora_do_universo',
    FORMAT('%s · %s · %s', competition, round, status_short),
    IF(com_preco = partidas, 'SO_O_STATUS',
       IF(com_preco = 0, 'SEM_PRECO_COLETADO', 'MISTO')),
    CAST(partidas AS FLOAT64),
    CAST(com_preco AS FLOAT64),
    NULL,
    TO_JSON_STRING(STRUCT(competition, round, status_short, partidas, com_preco,
                          primeiro, ultimo))
FROM fora_do_universo

UNION ALL
SELECT 6, 'ordenacao',
    FORMAT('%s · piso %d', contraste, piso),
    veredito,
    rho,
    CAST(trocas_no_topo AS FLOAT64),
    CAST(trocas_de_sinal AS FLOAT64),
    TO_JSON_STRING(STRUCT(
        contraste, piso, n_premissas, sem_contraparte, sem_medida, quais_sem_contraparte,
        saiu_do_topo, entrou_no_topo, delta_dif_medio, max_delta_posto, n_medio_a, n_medio_b,
        {{ rho_minimo }} AS regua_rho, {{ trocas_topo_material }} AS regua_topo,
        {{ trocas_sinal_material }} AS regua_sinal
    ))
FROM bloco_ordenacao

UNION ALL
SELECT 7, 'topo',
    FORMAT('%s · piso %d · %s', contraste, piso, premissa),
    direcao,
    CAST(pos_a AS FLOAT64),
    CAST(pos_b AS FLOAT64),
    peso_a,
    TO_JSON_STRING(STRUCT(contraste, piso, premissa, mercado, direcao,
                          pos_a, pos_b, peso_a, peso_b))
FROM bloco_topo

ORDER BY ordem, chave
