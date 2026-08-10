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
  de falha que este repositório passa o tempo consertando. O ponto cego que sobra
  (duas janelas desconhecidas empatando e abrindo fan-out) é coberto pelo
  accepted_values de `janela_usada`, que fica vermelho antes disso acontecer.
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
-#}
{% macro futebol_devig_janela_corrente() -%}
    SELECT d.* EXCEPT (_janela_prioridade, _line_key)
    FROM (
        SELECT
            *,
            {{ futebol_janela_prioridade('janela_usada') }} AS _janela_prioridade,
            COALESCE(CAST(line_value AS STRING), 'NONE')    AS _line_key
        FROM {{ ref('int_futebol_odds_devig') }}
    ) d
    QUALIFY d._janela_prioridade = MAX(d._janela_prioridade) OVER (
        PARTITION BY d.fixture_id, d.market_id, d._line_key
    )
{%- endmacro %}
