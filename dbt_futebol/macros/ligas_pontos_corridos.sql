{#- FONTE ÚNICA das ligas de PONTOS CORRIDOS — as em que `rank` é a classificação de um
    campeonato inteiro, e não a de um grupo de mata-mata.

    Existe porque a lista é lida em DOIS lugares que precisam concordar: a premissa
    `sem_rodizio` do int_futebol_premissas_ah (que só a deixa acender nessas ligas, porque
    compara o rank contra o tamanho da liga) e a chave de aplicabilidade da mesma premissa no
    mapa futebol_insumos_premissa(). Duas listas copiadas à mão concordam no dia em que são
    escritas e divergem na liga seguinte — e a divergência aqui é silenciosa nos dois sentidos:
    liga a mais na premissa vira ruído no score, liga a mais no mapa vira ruído no contador de
    premissas sem dado.

    Copa do Brasil não entra (não tem tabela nenhuma). Libertadores, Sudamericana e Champions
    também não: elas TÊM standings, mas o rank é por grupo/fase de liga e congela no mata-mata —
    o raciocínio completo está no comentário da premissa, no modelo. -#}
{% macro futebol_ligas_pontos_corridos() %}
    {{ return([
        'brasileirao', 'serie_b', 'la_liga', 'premier_league',
        'serie_a_ita', 'bundesliga', 'ligue_1', 'primeira_liga'
    ]) }}
{% endmacro %}


{#- A mesma lista como literal SQL: ('brasileirao', 'serie_b', ...). Usada tanto dentro do
    modelo quanto na string de aplicabilidade do mapa. -#}
{% macro futebol_ligas_pontos_corridos_sql() -%}
    ({% for liga in futebol_ligas_pontos_corridos() %}'{{ liga }}'{{ ", " if not loop.last }}{% endfor %})
{%- endmacro %}
