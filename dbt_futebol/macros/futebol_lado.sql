{#-
  O LADO APOSTADO, declarado num lugar só (issue #105, ADR 0005).

  É a chave — junto com o `market` — do denominador congelado da nota normalizada. São
  **onze pares** de (mercado, lado), e a enumeração é a mesma que a `taskA_a40_transporte.sql`
  usou para medir a normalização por lado; reusá-la byte a byte é o que faz o seed medido lá
  descrever o mesmo eixo que o modelo aplica aqui.

    1X2       Home · Draw · Away          (3)
    Gols      Over · Under                (2)
    Handicap  Favorito · Azarao · Pick    (3)
    BTTS      Yes · No                    (2)
    DC        unico                       (1)

  ⚠️ POR QUE O `outcome` NÃO SERVE SOZINHO, e é o motivo de este macro existir. No Handicap
  o `outcome` é Home/Away e o LADO é favorito/azarão: `line_value` vem na ótica do MANDANTE
  e é o MESMO para os dois lados ("Home −1.5" e "Away −1.5" são o par complementar), então o
  handicap na ótica do lado apostado é `IF(side = 'Home', line, -line)` e o SINAL dele é que
  diz quem dá e quem recebe. Os conjuntos de premissa dos dois são disjuntos (Σ40 contra
  Σ30) — normalizar os dois pelo mesmo denominador seria dividir por uma escala que metade
  das linhas não tem.

  ⚠️ A DUPLA CHANCE COLAPSA EM UM LADO SÓ, e não por preguiça: o
  `int_futebol_premissas_dc` não tem premissa por lado ("as quatro se aplicam às duas
  saídas"), então 1X e X2 dividem o MESMO teto (Σ34) e a MESMA distribuição de pontos.
  Dois denominadores ali seriam duas medições do mesmo número, cada uma com metade da
  amostra.

  ⚠️ O `Pick` do Handicap (linha 0) entra na enumeração pelo mesmo motivo que o `Draw` do
  1X2: nenhuma premissa dispara — todas são `is_favorito AND ...` ou `is_azarao AND ...`, e
  as duas flags são FALSE quando o handicap é zero. Teto de premissa zero, p95 zero,
  denominador zero. A ADR 0005 nomeia só o empate porque foi o caso que apareceu na
  medição; a aritmética é a mesma, e o seed carrega os dois com zero explícito.

  ⚠️ FAIL-CLOSED, igual ao `futebol_market_slug`: saída fora do catálogo resolve para NULL
  — a "12" da Dupla Chance, e qualquer `outcome` que o de-vig emita e o Motor não pontue.
  NULL aqui é o que mantém a linha FORA da medição do p95 e fora da cobrança da guarda de
  cobertura, que é exatamente onde ela deve estar: a decisão de não pontuar a "12" é nossa
  e já está carimbada na `porta_saida_catalogada`. Um lado inventado por acidente casaria
  com nenhuma linha do seed, e o modelo o trataria como denominador ausente.

  Os três argumentos são expressões já qualificadas pelo chamador (ex.: `f.market`), porque
  os consumidores juntam as tabelas com aliases diferentes.
-#}
{% macro futebol_lado(market_col, outcome_col, line_col) -%}
    CASE {{ market_col }}
        WHEN '{{ futebol_mercados_pontuados()[1] }}' THEN
            IF({{ outcome_col }} IN ('Home', 'Draw', 'Away'), {{ outcome_col }}, NULL)
        WHEN '{{ futebol_mercados_pontuados()[5] }}' THEN
            IF({{ outcome_col }} IN ('Over', 'Under'), {{ outcome_col }}, NULL)
        WHEN '{{ futebol_mercados_pontuados()[8] }}' THEN
            IF({{ outcome_col }} IN ('Yes', 'No'), {{ outcome_col }}, NULL)
        WHEN '{{ futebol_mercados_pontuados()[12] }}' THEN
            IF({{ outcome_col }} IN ('1X', 'X2'), 'unico', NULL)
        WHEN '{{ futebol_mercados_pontuados()[4] }}' THEN
            CASE
                WHEN {{ outcome_col }} NOT IN ('Home', 'Away') THEN NULL
                -- o handicap na ótica do lado apostado; `line_value` vem na do mandante.
                WHEN IF({{ outcome_col }} = 'Home', {{ line_col }}, -{{ line_col }}) < 0 THEN 'Favorito'
                WHEN IF({{ outcome_col }} = 'Home', {{ line_col }}, -{{ line_col }}) > 0 THEN 'Azarao'
                -- linha 0: ninguém dá e ninguém recebe. Nenhuma premissa dispara.
                WHEN IF({{ outcome_col }} = 'Home', {{ line_col }}, -{{ line_col }}) = 0 THEN 'Pick'
                -- handicap ausente: não dá para dizer o lado, e inventá-lo é pior.
                ELSE NULL
            END
    END
{%- endmacro %}


{#-
  O p95 OBSERVADO, declarado num lugar só (issue #105, ADR 0005).

  É a função de agregação que a `taskA_a6_p95.sql` usa para MEDIR o número que vai ao seed
  e que a `assert_p95_nota_contexto_nao_derivou.sql` usa para RECALCULAR o p95 vivo e
  comparar com ele.

  ⚠️ POR QUE MACRO. Duas expressões de percentil diferentes fabricam deriva que não existe:
  `APPROX_QUANTILES` é aproximado por construção e num lado com poucos valores possíveis ele
  salta de degrau; medir com uma e vigiar com a outra deixaria a guarda vermelha sem que
  nada tivesse mudado no catálogo. Com um macro só, medição e guarda não têm como discordar.

  ⚠️ `PERCENTILE_DISC` e não `PERCENTILE_CONT`, e é o que "p95 **observado**" quer dizer: a
  nota de contexto é INT64 e só assume as somas de peso que o catálogo permite (o azarão do
  Handicap tem 8 notas possíveis no total). O `PERCENTILE_CONT` interpolaria entre duas
  delas e devolveria um denominador que nenhuma linha jamais alcança — o mesmo defeito do
  teto estrutural que a ADR 0005 rejeitou, chegando pelo outro lado.

  ⚠️ NULL não conta. Linha sem premissa a avaliar (`pts_premissas` NULL, a "12" da DC) sai
  do percentil em vez de entrar como zero — é a mesma distinção da ADR 0003, e é o padrão
  de `PERCENTILE_DISC` no BigQuery.

  Sai como função de JANELA (é o que o BigQuery oferece), então o chamador precisa do
  `OVER (PARTITION BY ...)` e de um `DISTINCT`/agregação por cima. Os dois consumidores
  fazem exatamente isso.
-#}
{% macro futebol_p95(coluna) -%}
    PERCENTILE_DISC({{ coluna }}, 0.95)
{%- endmacro %}
