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


{#
    O QUE CONTA COMO "A PREMISSA SE MEXEU" NO PISO 0 — os quatro campos, escritos UMA vez.

        n_p0            em quantas linhas de aposta a premissa acendeu
        a_odd_dava_p0   o que o preço prometia nelas
        aconteceu_p0    o que aconteceu de fato
        diferenca_p0    a diferença entre os dois — o número do Teste 2

    São os NOMES DE COLUNA da tabela acumulativa (`futebol_taskF.taskf_teste2`), e não os aliases
    que cada análise cria depois de juntar duas células. Quem alia (a comparação entre células
    chama `diferenca_p0` de `dif_p0`) traduz na hora de usar, e a tradução fica visível.

    Por que num lugar só: "mexeu" é o veredito que a comparação entre células
    (analyses/taskf_delta_celulas.sql) e o entregável (analyses/taskf_entregavel.sql) emitem sobre
    a MESMA linha. Duas listas fariam as duas análises discordarem sobre a mesma premissa — e a
    discordância seria muda, porque cada uma continuaria internamente coerente. É o mesmo
    argumento do taskf_pisos() acima e da lista de valores aceitos do taskf_eixos().

    ⚠️ `n_p0` entra de propósito: mudança no CONJUNTO de linhas em que a premissa acende é efeito,
    não ruído. E o veredito é do piso 0 e só dele — nos pisos maiores até as premissas de tabela
    mudam, porque o `min_jogos` segue a célula (ADR 0008, seção *Consequences*).

    Uso:

        {%- for campo in taskf_campos_do_piso0() %} ... {%- endfor %}
#}

{% macro taskf_campos_do_piso0() %}
    {{ return(['n_p0', 'a_odd_dava_p0', 'aconteceu_p0', 'diferenca_p0']) }}
{% endmacro %}
