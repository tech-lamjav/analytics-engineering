{#- FONTE ÚNICA das COMPETIÇÕES DE INSUMO — as que alimentam a forma das seleções e nunca geram
    oportunidade (ADR 0004 no data-engineering; verbete "competição de insumo" no CONTEXT.md de lá).
    Hoje só amistosos de seleção (league_id 10).

    Cada uma declara duas coisas, e as duas são lidas em mais de um lugar:

    - `slug`: o `competition` que ela recebe em fact_fixtures. É o que a guarda
      assert_per_fixture_coverage_anomala tira da conta — não coletamos os fatos per-fixture de
      competição de insumo (decisão 17), então a cobertura é 0% por construção.
    - `entra_a_partir_de`: a data (UTC, inclusiva) de kickoff a partir da qual os jogos entram no
      mart. Lida pelo corte em stg_futebol_fixtures e pela guarda
      assert_competicao_insumo_sem_passado. Duas cópias da mesma data concordam no dia em que são
      escritas e divergem na competição seguinte — o precedente da meia-linha em quatro cópias.

    POR QUE AMISTOSOS TÊM DATA DE ENTRADA (DE#95/DE#96). A forma PIT atravessa competição desde a
    #91/ADR 0010, então ligar a temporada inteira (115 amistosos FT, jan–jun/2026) movia a forma
    de âncoras de Copa do Mundo e Nations League já medidas em ~23 pp, contra a régua de 0,25 pp
    — 47 de 48 âncoras de Copa que estreavam sem forma passariam a carregar amistoso. Veredito da
    #95: o passado não entra. `2026-09-23` é a data do veredito. No raw, o último amistoso
    encerrado é de 10/06 e o primeiro futuro de 24/09, então qualquer data entre as duas daria o
    mesmo mart hoje; fixar a do veredito faz o corte não depender do dia em que o deploy acontece.

    Competição de insumo nova (eliminatórias de Copa têm o mesmo perfil, ADR 0004) entra aqui E no
    CASE de fact_fixtures, e em nenhum dos outros cinco CASE. -#}
{% macro futebol_competicoes_insumo() %}
    {{ return({
        10: {'slug': 'amistosos', 'entra_a_partir_de': '2026-09-23'},
    }) }}
{% endmacro %}


{#- Predicado SQL "esta linha é de competição de insumo ANTERIOR à sua data de entrada", sobre uma
    coluna de league_id e uma de kickoff em TIMESTAMP. Quem filtra usa NOT (...); quem guarda
    conta as linhas em que ele é verdadeiro. Kickoff NULL deixa o predicado NULL: o filtro
    descarta a linha (o lado conservador) e a guarda não a conta. -#}
{% macro futebol_insumo_antes_da_entrada(league_id_col, kickoff_ts_col) -%}
    (FALSE
        {%- for league_id, competicao in futebol_competicoes_insumo().items() %}
        OR ({{ league_id_col }} = {{ league_id }} AND {{ kickoff_ts_col }} < TIMESTAMP('{{ competicao.entra_a_partir_de }}'))
        {%- endfor %}
    )
{%- endmacro %}


{#- Os slugs como lista e como literal SQL ('amistosos', ...) — para quem exclui competição de
    insumo por `competition` (as duas guardas de cobertura per-fixture). -#}
{% macro futebol_competicoes_insumo_slugs() %}
    {{ return(futebol_competicoes_insumo().values() | map(attribute='slug') | list) }}
{% endmacro %}

{% macro futebol_competicoes_insumo_slugs_sql() -%}
    ({% for slug in futebol_competicoes_insumo_slugs() %}'{{ slug }}'{{ ", " if not loop.last }}{% endfor %})
{%- endmacro %}
