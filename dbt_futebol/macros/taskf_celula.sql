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

    ⚠️ As listas de valores aceitos aparecem também no int_futebol_team_form_pit, que valida por
    conta própria. A duplicação é consciente e assimétrica: o modelo valida porque produção passa
    por ele, e esta macro valida porque uma análise compila SEM o modelo na seleção — aí a
    validação do modelo não roda e um `pit_escopo: todos` (com S) mediria `base` calado, com o
    rótulo `base`, que é exatamente o modo de falha que esta macro existe para fechar.

    Uso:

        {%- set c = taskf_celula() %}
        SELECT '{{ c.nome }}' AS celula, '{{ c.escopo }}' AS pit_escopo, ...
#}

{% macro taskf_celula() %}

    {%- set escopo  = var('pit_escopo',  'da_competicao') -%}
    {%- set recorte = var('pit_recorte', 'temporada') -%}

    {%- if escopo not in ['da_competicao', 'todas'] -%}
        {{ exceptions.raise_compiler_error(
            "pit_escopo inválido: '" ~ escopo ~ "'. Valores aceitos: da_competicao | todas.") }}
    {%- endif -%}
    {%- if recorte not in ['temporada', 'ultimos_10'] -%}
        {{ exceptions.raise_compiler_error(
            "pit_recorte inválido: '" ~ recorte ~ "'. Valores aceitos: temporada | ultimos_10.") }}
    {%- endif -%}

    {%- set nomes = {
        'da_competicao|temporada':  'base',
        'todas|temporada':          'escopo',
        'da_competicao|ultimos_10': 'recorte',
        'todas|ultimos_10':         'ambos'
    } -%}

    {{ return({
        'nome':    nomes[escopo ~ '|' ~ recorte],
        'escopo':  escopo,
        'recorte': recorte
    }) }}

{% endmacro %}
