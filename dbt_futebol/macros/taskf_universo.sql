{#
    O UNIVERSO CONGELADO da medição da task [F] (issue #49), escrito UMA vez.

    ⚠️ Isto é o recorte de tempo do UNIVERSO DE MEDIÇÃO — os kickoffs que entram na conta. NÃO é
    a janela de COLETA DE ODDS (daily/t24h/t1h/t15m) nem o eixo `recorte` do PIT: são três coisas
    distintas e só esta decide quais jogos são medidos. O glossário do CONTEXT.md pede que a
    palavra `janela` fique reservada à coleta de odds, e por isso ela não é usada aqui — a exceção
    são as colunas `janela_ini`/`janela_fim`, que são os nomes da própria [0.1] e ficam como
    estão para a saída medida bater campo a campo com a tabela publicada.

    O corte NÃO é escolha do implementador: é o recorte publicado no doc de resultados da Task
    [0.1] — 16/06/2026 a 04/08/2026, 169 jogos (`docs/TASK01_RESULTADOS.md`, ticket #5). A
    terceira invariante da Costura B pede que a célula `base` reproduza aquele Teste 2, e a
    reconciliação só fecha contra o mesmo corte. Um corte diferente faria a comparação falhar
    sem motivo aparente.

    ⚠️ O TETO É UM INSTANTE, NÃO UM DIA — e isto foi medido, não escolhido. A [0.1] rodou SEM
    corte congelado: o teto dela é o instante em que a query executou, e `janela_fim = 04/08` é
    só o `MAX(DATE(kickoff))` que saiu daquilo. Cortar em `DATE(kickoff) <= '2026-08-04'` devolve
    **178** jogos, não 169. Os 9 excedentes são exatamente os jogos de 04/08 com kickoff a partir
    das 16:00 UTC (8 da Champions e 1 da Copa do Brasil, o das 22:30) — no dia inteiro só UM jogo
    começou antes disso, o das 00:00 UTC, e ele está nos 169. Ou seja: quando a [0.1] rodou, os
    outros nove ainda não tinham sido disputados.

    O teto fica no MEIO do vão vazio: entre o fim do jogo das 00:00 (~02:00 UTC) e o kickoff das
    16:00 não existe nenhum jogo na base. Qualquer instante nessa faixa de catorze horas devolve
    os mesmos 169 — o corte é robusto a essa incerteza, e não um valor calibrado até o número
    bater. As datas continuam sendo 16/06 e 04/08 nas duas pontas, porque o último jogo INCLUÍDO
    é mesmo de 04/08; o que muda é a hora.

    O piso de 16/06 é no-op e fica explícito de propósito: a coleta de odds é forward-only e
    começou nesse dia, então o universo já nasce cortado ali. Medido — `A_sem_corte` e
    `B_ate_0408` devolvem `janela_ini = 2026-06-16` sozinhos. Declarar o piso custa nada e tira o
    corte da dependência de um efeito colateral da coleta.

    Por que existe como macro, e não como duas datas digitadas em cada análise: as quatro células
    são comparadas entre si, e duas análises com cortes que derivaram um do outro comparam
    universos diferentes sem ninguém perceber. Aqui a divergência é impossível por construção.

    O `jogos_esperados` fica junto de propósito. Ele é o número publicado, e serve de gabarito:
    quem materializar uma célula e vir outro número sabe na hora que o universo se mexeu (jogo
    remarcado, resultado que entrou depois, odd que apareceu), em vez de descobrir isso na
    diferença de uma premissa.

    Uso:

        {%- set j = taskf_universo() %}
        WHERE {{ taskf_universo_filtro('a.') }}
#}

{% macro taskf_universo() %}
    {{ return({
        'ini':             '2026-06-16',
        'fim':             '2026-08-04',
        'teto_utc':        '2026-08-04 12:00:00',
        'jogos_esperados': 169
    }) }}
{% endmacro %}


{#-
    Predicado do universo congelado, para não haver duas escritas do mesmo intervalo. `alias` inclui
    o ponto: taskf_universo_filtro('a.')

    Recortar em cima de `apostas` equivale a recortar `jogos_encerrados`: no task01_base() todo o
    resto pende do universo de jogos por JOIN, e o `pit` é LEFT JOIN a partir dele. O recorte fica
    aqui, e não num parâmetro novo do macro compartilhado, para que a definição que produziu os
    números publicados da [0.1] não seja tocada por esta medição.
-#}
{% macro taskf_universo_filtro(alias='') %}
    {%- set j = taskf_universo() -%}
    ({{ alias }}kickoff_utc >= TIMESTAMP('{{ j.ini }}')
     AND {{ alias }}kickoff_utc < TIMESTAMP('{{ j.teto_utc }}'))
{%- endmacro %}
