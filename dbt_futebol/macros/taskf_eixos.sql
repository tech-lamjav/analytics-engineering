{#
    OS DOIS EIXOS DA MEDIÇÃO DA TASK [F] (issue #49, ADR 0007), lidos e validados num lugar só.

        pit_escopo   da_competicao (default) | todas
                     Quais COMPETIÇÕES contam no histórico do time.

        pit_recorte  temporada (default)     | ultimos_10
                     Qual TRECHO do passado conta.

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

    {{ return({'escopo': escopo, 'recorte': recorte}) }}

{% endmacro %}
