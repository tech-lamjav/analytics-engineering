{#-
  A ORDEM DAS JANELAS DE COLETA, declarada num lugar só (issue #37, ADR 0004).

  Da mais cedo para a mais tarde: `daily` (até 7 dias do apito) < t24h < t1h < t15m.
  Depois da #37 o de-vig emite uma avaliação POR JANELA e não escolhe nenhuma; quem
  escolhe é o consumidor, e é esta ordem que ele usa.

  ⚠️ São QUATRO janelas, não três. A `daily` entrou em produção em 07/08/2026
  (`tech-lamjav/data-engineering#34`, horizonte de 7 dias) e o board já publica nela.
  Qualquer coisa que assuma três janelas está desatualizada — a ADR 0004 rejeitou
  "uma coluna por janela" justamente para que acrescentar a quinta não custe schema.

  `ELSE 0` põe janela desconhecida ABAIXO de todas as conhecidas em vez de NULL: com
  NULL, uma linha cuja única janela fosse desconhecida teria MAX(prioridade) NULL, a
  comparação daria NULL e a linha desapareceria em silêncio — que é exatamente o modo
  de falha que este repositório passa o tempo consertando.

  ⚠️ O ponto cego que SOBRA: duas janelas desconhecidas empatam no MAX e abrem fan-out.
  O accepted_values de `janela_usada` reporta isso, mas **não previne** — e a diferença
  importa. No `workflow_futebol.yml` a fase de `dbt run` é a 2 e a de `dbt test
  --select tag:guarda` é a 4, sem gate (de propósito, para teste vermelho não derrubar
  o board nem o sync). Ou seja: o fan-out seria construído, publicado e sincronizado, e
  só depois o resumo diário reportaria. A guarda encurta o tempo até alguém saber; ela
  não impede a linha duplicada de chegar ao board. Quem previne de verdade é o
  accepted_values do MODELO A MONTANTE (`fact_odds_snapshot.collection_window`), porque
  janela nova só existe aqui se antes existir lá.
-#}
{% macro futebol_janela_prioridade(coluna) -%}
    CASE {{ coluna }}
        WHEN 't15m'  THEN 4   -- fechamento
        WHEN 't1h'   THEN 3
        WHEN 't24h'  THEN 2
        WHEN 'daily' THEN 1   -- varredura diária, até 7 dias do apito
        ELSE 0
    END
{%- endmacro %}


{#-
  O DE-VIG COM AS QUATRO JANELAS ABERTAS, cada uma carimbada com a sua prioridade e
  com a resposta para "esta é a janela corrente desta linha?" (issue #40).

  Existe porque o consumidor que precisa avaliar TODAS as janelas — hoje só o
  `fact_value_opportunities`, para achar a janela de detecção — precisa saber qual
  delas é a corrente ANTES de qualquer filtro seu. O flag é calculado aqui, sobre as
  linhas cruas do de-vig, e não depois dos filtros do consumidor.

  ⚠️ A diferença não é estética. Os ramos do mart filtram por completude do conjunto
  (`pin_n_outcomes >= 3` no 1X2, `>= 2` no O/U e no AH). Se o `MAX(prioridade)` fosse
  tirado DEPOIS desse filtro, uma linha cuja janela mais recente tem conjunto
  incompleto veria a t24h virar "a corrente" e continuaria no board com o preço de
  ontem — que é o oposto do que a ADR 0004 decidiu (preço que não dá para pegar sai
  do board). Tirado aqui, a linha simplesmente não tem janela corrente publicável.

  A partição é (fixture, mercado, LINHA) e deliberadamente NÃO inclui a saída — pela
  mesma razão explicada em `futebol_devig_janela_corrente()` logo abaixo.
-#}
{% macro futebol_devig_todas_janelas() -%}
    SELECT
        d.* EXCEPT (_janela_prioridade, _line_key),
        d._janela_prioridade AS janela_prioridade,
        d._janela_prioridade = MAX(d._janela_prioridade) OVER (
            PARTITION BY d.fixture_id, d.market_id, d._line_key
        ) AS janela_e_corrente
    FROM (
        SELECT
            *,
            {{ futebol_janela_prioridade('janela_usada') }} AS _janela_prioridade,
            COALESCE(CAST(line_value AS STRING), 'NONE')    AS _line_key
        FROM {{ ref('int_futebol_odds_devig') }}
    ) d
{%- endmacro %}


{#-
  O DE-VIG REDUZIDO À JANELA CORRENTE — a forma como todo consumidor lê o de-vig.

  O de-vig emite N linhas por (fixture, mercado, saída, linha), uma por janela
  coletada. Consumidor que fizer join direto abre N vezes: o mart triplicaria (hoje
  quadruplicaria) em silêncio, com a mesma oportunidade contada uma vez por janela.
  Por isso a redução é um macro e não SQL copiado: a regra existe num lugar só, e
  consumidor novo herda a redução em vez de redescobrir o problema.

  A partição é (fixture, mercado, LINHA) e deliberadamente NÃO inclui a saída. A
  linha inteira resolve para a MESMA janela, porque o de-vig normaliza sobre o
  conjunto de saídas: se o Home viesse da t15m e o Away da t1h, o Σ(1/odd) somaria
  preços de momentos diferentes. É a mesma partição que o `eval_odds` usava antes
  da #37, e é o que faz a saída do mart sair idêntica à de antes da mudança de grão.

  Desde a #40 esta redução é um FILTRO sobre `futebol_devig_todas_janelas()`, e não
  uma segunda cópia do `MAX(prioridade)`: as duas leituras do de-vig não têm como
  divergir na definição de "janela corrente" porque só existe uma.
-#}
{% macro futebol_devig_janela_corrente() -%}
    SELECT * EXCEPT (janela_prioridade, janela_e_corrente)
    FROM ({{ futebol_devig_todas_janelas() }})
    WHERE janela_e_corrente
{%- endmacro %}
