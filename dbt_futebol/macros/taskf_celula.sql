{#
    O NOME DA CÉLULA sai dos eixos, e não de um rótulo que alguém digita.

    A medição da task [F] (issue #49) é um 2x2 de eixos independentes:

        pit_escopo \ pit_recorte |  temporada  |  ultimos_10
        -------------------------+-------------+-------------
        da_competicao            |  base       |  recorte
        todas                    |  escopo     |  ambos

    Por que derivar, e não aceitar uma var `taskf_celula` livre: se o rótulo fosse digitado, seria
    possível materializar a célula `escopo` e gravá-la como `base`. Nada no dado denunciaria — as
    quatro têm o mesmo formato —, e a comparação entre células, que é o entregável inteiro da [F],
    passaria a comparar duas coisas erradas com cara de certo. Derivado dos eixos, o rótulo não
    tem como discordar do que de fato rodou.

    A saída carrega os dois valores de eixo ao lado do nome pelo mesmo motivo: quem lê a tabela de
    medição não precisa confiar no dicionário acima, ele está na linha.

    A LEITURA E A VALIDAÇÃO DOS EIXOS não moram aqui: vêm de taskf_eixos(), que é a fonte única
    dos valores aceitos. Continua valendo que uma análise compila SEM os modelos na seleção — aí a
    validação deles não roda, e é por isso que esta macro também valida (via taskf_eixos): um
    `pit_escopo: todos` (com S) mediria `base` calado, com o rótulo `base`, que é exatamente o modo
    de falha que esta macro existe para fechar. O que mudou é que a lista de valores aceitos existe
    UMA vez, e não uma por consumidor.

    Uso:

        {%- set c = taskf_celula() %}
        SELECT '{{ c.nome }}' AS celula, '{{ c.escopo }}' AS pit_escopo, ...
#}

{% macro taskf_celula() %}

    {%- set eixos   = taskf_eixos() -%}
    {%- set escopo  = eixos.escopo -%}
    {%- set recorte = eixos.recorte -%}

    {{ return({
        'nome':    taskf_nomes_de_celula()[escopo ~ '|' ~ recorte],
        'escopo':  escopo,
        'recorte': recorte
    }) }}

{% endmacro %}


{#-
    O 2x2 em forma de dicionário, exposto à parte para que os NOMES das quatro células existam uma
    vez só. Quem rotula uma célula chama taskf_celula(); quem precisa da LISTA dos quatro nomes
    — as análises que comparam duas células e validam qual par foi pedido — lê daqui:

        {%- set validas = taskf_nomes_de_celula().values() | list -%}

    É o mesmo argumento que pôs os valores aceitos dos eixos em taskf_eixos() e a digital do
    insumo do PIT em taskf_fingerprint_insumo_pit(): uma segunda cópia da lista não fica igual à
    primeira para sempre, e a divergência aqui seria muda — uma análise recusando `ambos` como
    nome inválido depois de a #54 o materializar devolveria zero linha, que se parece com "as duas
    células são idênticas".
-#}
{% macro taskf_nomes_de_celula() %}
    {{ return({
        'da_competicao|temporada':  'base',
        'todas|temporada':          'escopo',
        'da_competicao|ultimos_10': 'recorte',
        'todas|ultimos_10':         'ambos'
    }) }}
{% endmacro %}
