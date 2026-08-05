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
        12: 3
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
-#}
