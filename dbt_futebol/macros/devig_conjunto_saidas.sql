{#- FONTE ÚNICA do tamanho esperado do CONJUNTO DE SAÍDAS por mercado.

    O de-vig normaliza probabilidades sobre o conjunto de saídas de um (fixture, mercado,
    linha): prob_justa = (1/odd) / Σ(1/odd). Se o conjunto estiver INCOMPLETO, a soma é
    menor que 1 e a normalização INFLA as probabilidades — no limite de 1 saída, devolve
    prob = 1,0 (certeza absoluta) e edge = odd − 1. Foi assim que 404 linhas anunciaram
    valor máximo com 1,2% de acerto real (spec #22).

    Por isso o conjunto incompleto NÃO produz uma estimativa pior — produz NENHUMA. Este
    macro declara quantas saídas cada mercado precisa ter para que o de-vig possa emitir.

    Comparação é EXATA, não "pelo menos". "Pelo menos duas" resolveria as mesmas 404 linhas
    de hoje, mas deixaria passar o 1X2 com duas das três saídas: booksum ~0,66,
    probabilidades infladas em ~1,5× e edge falso — o MESMO bug, sem a prob 1,0 que o
    denuncia. Ver docs/adr/0002-conjunto-de-saidas-declarado-por-mercado.md.

    Mercado NÃO declarado resolve para NULL e portanto NÃO EMITE (fail-closed). O ponto
    cego disso — mercado novo nascer mudo em silêncio — é coberto pela guarda
    assert_devig_conjunto_declarado, que compara o declarado com o MÁXIMO observado.

    Valores derivados de inventário sobre a base de odds inteira. Só os mercados abaixo
    chegam ao modelo: HT/FT (7) e Exact Score (10) são coletados mas têm lado 100% nulo e
    são descartados no WHERE do CTE de odds. -#}
{% macro futebol_conjunto_saidas() %}
    {{ return({
        1:  3,
        4:  2,
        5:  2,
        6:  2,
        8:  2,
        12: 3,
        45: 2,
        56: 2,
        57: 2,
        58: 2
    }) }}
{% endmacro %}


{#- Mercados que ficam MUDOS de propósito — decisão registrada, não esquecimento. Existem
    só pra guarda assert_devig_conjunto_declarado saber diferenciar "órfão" (bug: mercado
    novo na base, ninguém declarou) de "decisão tomada" (o mercado É conhecido e a escolha
    foi não declarar). Mesma separação de perguntas do comentário sobre o mercado 6 em
    futebol_funil.sql: "qual conjunto de saídas" (aqui) é diferente de "por que ficou mudo"
    (lá embaixo) — só que aqui a resposta pra "qual conjunto" é "nenhum, de propósito". -#}
{% macro futebol_mercados_mudos_confirmados() %}
    {{ return({
        77: 'Total de escanteios do 1º tempo (AE#164): fica mudo por decisão, não por mercado novo não-declarado. Causa técnica verificada em models/staging/stg_futebol_fixture_statistics.sql: corner_kicks vem de ANY_VALUE(statistics.value) sobre o type "Corner Kicks" da API-Football, que só traz o total do jogo inteiro — não há granularidade por tempo na fonte, então não dá pra modelar corners de 1º tempo com o insumo que a base tem hoje.'
    }) }}
{% endmacro %}


{#- Documentação dos valores acima (mantida fora do dict p/ o return ser um literal puro):

    1  — 1X2: Home / Draw / Away.
    4  — Handicap Asiático: par complementar na MESMA linha. A API-Football traz line_value
         na ótica do MANDANTE, igual p/ Home e Away, então "Home -1.5"/"Away -1.5" caem na
         mesma partição (fixture, market, line_key) e o conjunto é 2, não 4.
    5  — Gols O/U: Over / Under na mesma linha.
    6  — Gols O/U 1ºT: idem. Declarado porque ESTÁ na tabela e carregava 136 das 404 linhas
         podres; declarar limpa essas linhas e preserva as ~2,1 mil válidas. NÃO é mercado
         apostável: fora do escopo do Motor, sem premissas, não vai ao board.
    8  — BTTS: Yes / No.
    12 — Dupla Chance: ⚠️ COINCIDÊNCIA NUMÉRICA PERIGOSA. O 3 aqui NÃO são as 3 saídas da DC
         (1X / 12 / X2) — são as 3 saídas do conjunto 1X2 DE ORIGEM, do qual a prob da DC é
         derivada (P(1X)=P(Home)+P(Draw) etc., ver dc_devig no modelo). As saídas da própria
         DC não são exaustivas (somam ~2) e por isso ela nunca cai no consenso. São duas
         coisas diferentes que calham de ser iguais: não "consertar" para outro número.
    45 — Total de escanteios: Over / Under na mesma linha, mesma regra do 5. Coletado desde
         11/09 (commit 2a2540c) mas só declarado aqui em AE#164 — ficou órfão 3 dias, achado
         como efeito colateral do AE#158 (#164). Tem spec irmã própria (ClickUp wdx6zf1v4m),
         ainda não iniciada; declarar aqui só destrava o de-vig, não publica nada em mart.
    56 — Handicap de escanteios (AE#158): mesma regra do 4 (Handicap Asiático de gols) e
         pelo mesmo motivo — a API-Football traz line_value na ótica do MANDANTE, igual p/
         Home e Away, então "Home -4.5"/"Away -4.5" caem na mesma partição (fixture, market,
         line_key) e o conjunto exaustivo é o par complementar, 2. Fora do escopo do Motor de
         Score (não está em futebol_mercados_pontuados_ids()): alimenta só
         dbt_futebol/analyses/ da spec #157, nunca o funil nem o mart.
    57 — Escanteios do mandante: Over / Under na mesma linha, mesma regra do 5/45. Mesma
         história do 45 (órfão desde 11/09, declarado em AE#164). Mencionado no documento de
         metodologia como "depois do 56" — sem spec própria ainda.
    58 — Escanteios do visitante: idem ao 57, lado visitante.
-#}
