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


{#-
  A FRONTEIRA DO CONGELAMENTO, declarada num lugar só (issue #96, ADR 0011).

  TRUE = esta linha ainda pode ser escrita. O funil é append-only: a linha é escrita e
  atualizada enquanto o jogo não começou, e no apito ela para de ser tocada por build
  nenhum e deploy nenhum.

  É no **apito inicial**, e não no status final: entre um e outro há duas horas em que os
  modelos de premissa continuam rodando, e tudo escrito ali seria nota nascida depois de a
  bola rolar — nota que ninguém podia ler antes de apostar. É a fresta que a ADR 0009
  existe para fechar.

  ⚠️ Por que macro e não SQL repetido — a mesma lição de `futebol_expurgo.sql`, e aqui ela
  vale em CINCO lugares: o modelo, os dois lados da `assert_funil_reconcilia_com_devig` e os
  dois lados da `assert_funil_paridade_com_board`. Predicado copiado em cinco arquivos é
  predicado que diverge no primeiro refactor, e a divergência é muda nos dois sentidos:
  guarda mais frouxa que o modelo nunca acende, guarda mais estrita acende sem defeito. Com
  um macro só, modelo e guardas não têm como discordar.

  ⚠️ FIXTURE AUSENTE É FAIL-OPEN (ADR 0003). `NULL > CURRENT_TIMESTAMP()` é NULL, e sem o
  `COALESCE(..., TRUE)` a linha nunca mais seria escrita: ela sumiria do funil e a
  reconciliação acenderia vermelha, com razão. Preferimos a linha eternamente gravável à
  linha perdida — não dá para congelar no apito de um jogo cuja hora não se sabe.

  ⚠️ JOGO ADIADO REABRE, e de graça: o predicado lê o kickoff CORRENTE, não o que estava lá
  quando a linha foi escrita. `PST`/`SUSP` empurram o kickoff para o futuro e a linha volta
  a ser gravável — o jogo voltou a ser apostável, e o que estava escrito descrevia uma
  partida que não aconteceu.

  `kickoff_col` é expressão já qualificada pelo chamador (ex.: `f.kickoff_utc`), porque os
  consumidores juntam as tabelas com aliases diferentes.
-#}
{% macro futebol_funil_e_gravavel(kickoff_col) -%}
    COALESCE({{ kickoff_col }} > CURRENT_TIMESTAMP(), TRUE)
{%- endmacro %}
