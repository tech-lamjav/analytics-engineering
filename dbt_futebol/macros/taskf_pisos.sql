{#
    A VARREDURA DE PISO DE AMOSTRA da task [F] (issue #49), escrita UMA vez.

        [0, 3, 5, 10]

    A [0.1] varria [0, 5, 10]; o 3 é acréscimo da spec #49, "para distinguir achado de escolha de
    corte". A spec pede a varredura NAS QUATRO CÉLULAS, e é isso que faz a lista precisar existir
    num lugar só: ela é lida pelo Teste 2 (que dela deriva os nomes das colunas `n_p*`,
    `diferenca_p*`, `peso_p*`), pela comparação entre células e pela análise que confere que o
    piso corta a mesma coisa nas quatro. Três cópias de uma lista que precisa ficar igual para
    sempre não ficam — e a divergência seria muda: uma análise varrendo [0, 5, 10] contra uma
    tabela gravada com [0, 3, 5, 10] devolveria a coluna do 3 vazia, que se parece com "essa
    premissa não acende nesse piso".

    ⚠️ NÃO é var. O piso final é decisão da [B] (a spec põe "decidir o valor final do piso de
    amostra" fora de escopo aqui); esta lista é o que a medição REPORTA, e mexer nela muda o
    schema da tabela acumulativa — ver o cabeçalho de analyses/taskf_teste2.sql.

    Uso:

        {%- set pisos = taskf_pisos() -%}
        {%- for piso in pisos %} ... {%- endfor %}
#}

{% macro taskf_pisos() %}
    {{ return([0, 3, 5, 10]) }}
{% endmacro %}
