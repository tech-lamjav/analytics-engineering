{#
    OS DOIS EIXOS DA MEDIÇÃO DA TASK [F] (issue #49, ADR 0007), lidos e validados num lugar só.

        pit_escopo   da_competicao | todas (default)
                     Quais COMPETIÇÕES contam no histórico do time.

        pit_recorte  temporada     | ultimos_10 (default)
                     Qual TRECHO do passado conta.

    ⚠️ OS DEFAULTS MUDARAM NA #91 (ADR 0010). Até 24/08/2026 eles eram `da_competicao` e
    `temporada`, escolhidos para que o SQL compilado no default fosse idêntico ao de antes das
    vars existirem — as vars serviam à medição e produção nunca as passava. A [F] mediu o custo
    disso e a Recomendação 1 mandou soltar: a célula `ambos` é a que produção passa a usar.

    Por que os DOIS eixos e não só o escopo: soltar `competition_id` sozinho resgata **0 de 43**
    jogos europeus na janela nova, porque o ramo default do PIT mantinha `AND l.season =
    a.season` e a temporada 2026 das europeias tinha acabado de começar. Medido no piso 5, janela
    de 112 jogos (04/08 12:00 → 19/08): `base` 57, `escopo` 69, `recorte` 88, **`ambos` 94**.

    Produção AGORA usa o default — e é por isso que a Costura A
    (`assert_taskf_pit_default_igual_baseline`) foi recongelada no mesmo commit: ela existia para
    provar que produção nunca usava a var, e virar o default matou a premissa dela.

    Devolve também `tamanho_do_recorte` — o 10 de `ultimos_10`, escrito UMA vez. Ele é lido por
    seis sites de histórico em cinco modelos, mais o PIT, mais a análise que confere a saturação
    (analyses/taskf_saturacao_recorte.sql). Sete cópias de um literal não ficam iguais para
    sempre, e um site com 5 enquanto os outros têm 10 mediria célula misturada sem levantar nada
    — o mesmo argumento que trouxe a lista de valores aceitos para cá. NÃO é var: um botão livre
    de tamanho de recorte multiplicaria as células do 2x2 sem que a spec tenha pedido, e é
    exatamente o tipo de porta que o fail-closed abaixo existe para fechar.

    ⚠️ `recorte`, nunca `janela`: janela é a janela de coleta de odds (daily/t24h/t1h/t15m) e as
    duas coisas não têm relação. Ver o glossário no CONTEXT.md.

    POR QUE UMA MACRO, E NÃO A VALIDAÇÃO REPETIDA EM CADA CONSUMIDOR. O eixo de escopo não mora
    num modelo só: além do int_futebol_team_form_pit, os cinco modelos de premissas têm fontes de
    histórico competição-scoped próprias (os `last5` locais de Gols, BTTS e Dupla Chance, o
    `margin_stats` do Handicap e o spine de xG/ritmo). São SEIS modelos lendo as mesmas vars, mais
    a taskf_celula() que rotula a saída. Sete cópias da lista de valores aceitos não ficam iguais
    para sempre, e a divergência seria MUDA: um modelo aceitando um valor que outro rejeita mede
    célula misturada sem levantar nada. É o mesmo raciocínio que pôs a digital do insumo do PIT
    numa macro só (taskf_fingerprint_insumo_pit).

    FAIL-CLOSED, e é o ponto todo. Valor desconhecido levanta erro de compilação em vez de cair no
    default: sem isso, um `pit_escopo: todos` (com S) mediria `base` calado — com o rótulo `base`,
    porque taskf_celula() deriva o nome dos mesmos valores —, e a comparação entre células, que é
    o entregável inteiro da [F], compararia duas coisas erradas com cara de certo.

    Uso:

        {%- set eixos = taskf_eixos() -%}
        {%- if eixos.escopo == 'da_competicao' %} AND l.competition_id = a.competition_id {% endif %}
#}

{% macro taskf_eixos() %}

    {%- set escopo  = var('pit_escopo',  'todas') -%}
    {%- set recorte = var('pit_recorte', 'ultimos_10') -%}

    {%- if escopo not in ['da_competicao', 'todas'] -%}
        {{ exceptions.raise_compiler_error(
            "pit_escopo inválido: '" ~ escopo ~ "'. Valores aceitos: da_competicao | todas.") }}
    {%- endif -%}
    {%- if recorte not in ['temporada', 'ultimos_10'] -%}
        {{ exceptions.raise_compiler_error(
            "pit_recorte inválido: '" ~ recorte ~ "'. Valores aceitos: temporada | ultimos_10.") }}
    {%- endif -%}

    {{ return({'escopo': escopo, 'recorte': recorte, 'tamanho_do_recorte': 10}) }}

{% endmacro %}
