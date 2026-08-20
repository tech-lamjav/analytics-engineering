{#-
  O UNIVERSO DO FUNIL, declarado num lugar só (issue #95, ADR 0011).

  São os **cinco mercados pontuados** — os que têm modelo de premissa — e o nome público
  de cada um, que é o `market` que sai no `fact_value_funnel` e no
  `fact_value_opportunities`.

  ⚠️ O mercado **6** (Gols O/U do 1º tempo) está FORA de propósito, e não por esquecimento.
  O de-vig o emite (22.363 linhas na foto de 19/08) porque ele está declarado em
  `futebol_conjunto_saidas()` — lá a lista responde "qual conjunto de saídas este mercado
  precisa ter para o de-vig poder emitir", que é outra pergunta. Aqui a lista responde
  "quais mercados o Motor pontua". Gravar o 6 como *rejeitado* registraria como decisão
  nossa a ausência de um modelo que nunca escrevemos.

  Por que macro e não literal nos dois arquivos: a guarda `assert_funil_reconcilia_com_devig`
  precisa mapear `market_id` -> `market` exatamente como o modelo mapeia, senão ela acende
  vermelha (ou, pior, fica muda) por divergência de vocabulário e não por defeito. É a mesma
  razão que pôs o predicado do expurgo em `futebol_expurgo.sql`.
-#}
{% macro futebol_mercados_pontuados() %}
    {{ return({
        1:  'match_winner',
        4:  'asian_handicap',
        5:  'goals_over_under',
        8:  'btts',
        12: 'double_chance'
    }) }}
{% endmacro %}


{#- Os ids, prontos para um `IN (...)`. -#}
{% macro futebol_mercados_pontuados_ids() -%}
    {{ futebol_mercados_pontuados().keys() | join(', ') }}
{%- endmacro %}


{#- `market_id` -> o nome público do mercado. Mercado fora da lista resolve para NULL
    (fail-closed): ele não é candidato do funil, e um NULL numa chave de reconciliação
    acende vermelho em vez de casar por acidente. -#}
{% macro futebol_market_slug(coluna) -%}
    CASE {{ coluna }}
        {%- for mid, slug in futebol_mercados_pontuados().items() %}
        WHEN {{ mid }} THEN '{{ slug }}'
        {%- endfor %}
    END
{%- endmacro %}
