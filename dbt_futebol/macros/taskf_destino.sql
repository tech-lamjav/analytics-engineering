{#
    ONDE A MEDIÇÃO GRAVA — o 2×2 congelado da [F], a âncora da remedição (#82, ADR 0010) ou a
    remedição em si (AE#117, termo 5).

    A [F] mediu quatro células e as pôs em duas tabelas acumulativas de `futebol_taskF`
    (`taskf_teste2` e `taskf_pit_por_celula`), uma linha por célula, cada execução substituindo só
    a sua. A #82 precisa medir a célula `ambos` DE NOVO, sob o código que a #91 virou default, para
    servir de âncora à remedição do Teste 2 — e não pode gravá-la ali dentro.

    POR QUE NÃO PODE, e isto é medido e não estético: a primeira invariante da Costura B
    (`assert_taskf_celulas_mesmo_universo`, CTE `execucao`) cobra `git_sha` IDÊNTICO nas quatro
    células, e o cabeçalho dela diz por quê — "medir a `base` num commit e a `ambos` noutro, sobre
    os mesmos fatos, passaria pelas duas primeiras pontas e ainda assim compararia duas coisas
    diferentes". Sobrescrever a célula `ambos` com uma medição de outro commit deixaria a guarda
    vermelha COM RAZÃO: o 2×2 deixaria de ser uma comparação. E a ADR 0010 promete o contrário —
    "`futebol_taskF` permanece como registro congelado do 2×2".

    Então a âncora nasce em tabela irmã, com o mesmo schema e o mesmo código de agregação. É uma
    var, e não uma análise nova, porque copiar a agregação é exatamente o que o cabeçalho do
    analyses/taskf_teste2.sql recusa por escrito: o que a âncora precisa reproduzir é o MESMO
    cálculo, e duas cópias não ficam iguais para sempre.

        taskf_destino  medicao (default)    → smartbetting-dados.futebol_taskF.<tabela>
                       ancora               → smartbetting-dados.futebol_taskF.<tabela>_ancora
                       remedicao            → smartbetting-dados.futebol_taskF.<tabela>_remedicao
                       remedicao_com_gate   → smartbetting-dados.futebol_taskF.<tabela>_remedicao_com_gate

    FAIL-CLOSED, pelo mesmo motivo do taskf_eixos(): valor desconhecido levanta erro de compilação
    em vez de cair no default. Um `taskf_destino: âncora` (com acento) escreveria por cima do 2×2
    congelado em silêncio, e o dano é irreversível — a acumulativa não tem histórico.

    O default é `medicao` porque o caminho perigoso tem de exigir declaração explícita, nunca o
    contrário. E o projeto e o dataset ficam escritos aqui, fixos: o destino da medição NÃO segue
    o target, senão um `--target dev` distraído publicaria medição no dataset do board (ADR 0007).

    O DESTINO `remedicao` (AE#117). A emenda de 29/09 da ADR 0010 declarou a janela nova mas não
    criou onde gravá-la, e as duas opções que existiam eram ruins: `medicao` faria o `DELETE ...
    WHERE celula = 'ambos'` na acumulativa do 2×2 e gravaria ali um `git_sha` diferente (Costura B
    vermelha com razão, registro congelado destruído sem histórico); `ancora` misturaria, na mesma
    tabela, a medição que a âncora reproduz com a medição que ela vai ser comparada. Tabela irmã,
    mesmo schema, mesmo código de agregação — o mesmo argumento que a #82 fez para a âncora.

    E o `remedicao_com_gate` é a LEITURA SECUNDÁRIA da emenda (§1): o mesmo Teste 2 com as três
    portas de preço do board ligadas, "ao lado" e nunca no lugar. É uma tabela própria porque a
    leitura com gate e a sem gate são dois universos de LINHAS (5.605 contra 1.802 na janela
    congelada) e a mesma coluna `universo` não distingue uma da outra.

    TRÊS COISAS SEGUEM O DESTINO, e saem daqui para que não possam divergir dele em silêncio:

      taskf_destino(tabela)            a tabela gravada
      taskf_gates_board()              se o Teste 2 liga as portas de preço do board. Só a leitura
                                       secundária liga. `medicao`/`ancora`/`remedicao` NÃO — é a
                                       decisão da emenda, e a âncora só reproduz sem gate.
      taskf_universos_do_destino()     a lista de universos emitida: os quatro do 2×2 para
                                       `medicao`/`ancora`, os da janela nova para `remedicao*`
                                       (taskf_universos_janela_nova). A lista do 2×2 NÃO ganha os
                                       universos novos: a Costura B a cobraria da tabela congelada.

    Os três aceitam o destino como argumento opcional (default: a var). É por isso que dá para
    testá-los sem `--vars` (tests/assert_taskf_destino_remedicao.sql): o contrato de cada destino é
    afirmado por inteiro, e um sufixo errado — que seria silencioso — deixa de ser.

    Uso:

        {%- set tabela = taskf_destino('taskf_teste2') -%}
        CREATE TABLE IF NOT EXISTS `{{ tabela }}` ( ... )
#}

{#- Destino → sufixo da tabela. O ÚNICO lugar onde os destinos válidos são declarados. -#}
{% macro taskf_destinos() %}
    {{ return({
        'medicao':            '',
        'ancora':             '_ancora',
        'remedicao':          '_remedicao',
        'remedicao_com_gate': '_remedicao_com_gate'
    }) }}
{% endmacro %}


{#- Resolve e VALIDA o destino: argumento explícito, ou a var. Fail-closed. -#}
{% macro taskf_destino_valido(destino=none) %}
    {%- set d = destino if destino is not none else var('taskf_destino', 'medicao') -%}
    {%- set validos = taskf_destinos() -%}
    {%- if d not in validos -%}
        {{ exceptions.raise_compiler_error(
            "taskf_destino inválido: '" ~ d ~ "'. Valores aceitos: " ~ validos.keys() | join(' | ') ~ ".") }}
    {%- endif -%}
    {{ return(d) }}
{% endmacro %}


{% macro taskf_destino(tabela, destino=none) %}

    {%- set d = taskf_destino_valido(destino) -%}

    {{ return('smartbetting-dados.futebol_taskF.' ~ tabela ~ taskf_destinos()[d]) }}

{% endmacro %}


{#- Só a leitura secundária da remedição liga as portas de preço do board. -#}
{% macro taskf_gates_board(destino=none) %}
    {{ return(taskf_destino_valido(destino) == 'remedicao_com_gate') }}
{% endmacro %}


{#- A lista de universos que o Teste 2 emite neste destino. -#}
{% macro taskf_universos_do_destino(destino=none) %}
    {%- set d = taskf_destino_valido(destino) -%}
    {%- if d in ['remedicao', 'remedicao_com_gate'] -%}
        {{ return(taskf_universos_janela_nova()) }}
    {%- else -%}
        {{ return(taskf_universos()) }}
    {%- endif -%}
{% endmacro %}
