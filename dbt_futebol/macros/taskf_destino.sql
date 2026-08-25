{#
    ONDE A MEDIÇÃO GRAVA — o 2×2 congelado da [F], ou a âncora da remedição (#82, ADR 0010).

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

        taskf_destino  medicao (default) → smartbetting-dados.futebol_taskF.<tabela>
                       ancora            → smartbetting-dados.futebol_taskF.<tabela>_ancora

    FAIL-CLOSED, pelo mesmo motivo do taskf_eixos(): valor desconhecido levanta erro de compilação
    em vez de cair no default. Um `taskf_destino: âncora` (com acento) escreveria por cima do 2×2
    congelado em silêncio, e o dano é irreversível — a acumulativa não tem histórico.

    O default é `medicao` porque o caminho perigoso tem de exigir declaração explícita, nunca o
    contrário. E o projeto e o dataset ficam escritos aqui, fixos: o destino da medição NÃO segue
    o target, senão um `--target dev` distraído publicaria medição no dataset do board (ADR 0007).

    Uso:

        {%- set tabela = taskf_destino('taskf_teste2') -%}
        CREATE TABLE IF NOT EXISTS `{{ tabela }}` ( ... )
#}

{% macro taskf_destino(tabela) %}

    {%- set destino = var('taskf_destino', 'medicao') -%}

    {%- if destino not in ['medicao', 'ancora'] -%}
        {{ exceptions.raise_compiler_error(
            "taskf_destino inválido: '" ~ destino ~ "'. Valores aceitos: medicao | ancora.") }}
    {%- endif -%}

    {%- set sufixo = '' if destino == 'medicao' else '_ancora' -%}

    {{ return('smartbetting-dados.futebol_taskF.' ~ tabela ~ sufixo) }}

{% endmacro %}
