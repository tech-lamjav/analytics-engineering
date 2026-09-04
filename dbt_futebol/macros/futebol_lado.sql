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

  ⚠️ O `Pick` do Handicap (linha 0) FICOU DORMENTE NA #109/B3 (2026-09-01). Até então
  entrava na enumeração pelo mesmo motivo que o `Draw` do 1X2 — nenhuma premissa disparava,
  `is_favorito`/`is_azarao` eram as duas FALSE em handicap zero, e o seed carrega o lado
  com denominador zero explícito. O achado da B3: ao contrário do empate (que é
  estrutural — não existe "favorito no empate"), a linha 0 do Handicap TEM lado. O `Pick`
  segue no seed (zero explícito — p95 até 03/09, teto do catálogo desde a PPP#365/ADR
  0013) mas nenhum candidato vivo volta a produzi-lo — é dormente, não removido, mesmo
  padrão de valor legado que este projeto já usa em `motivo_primario`.

  ⚠️ QUEM DECIDE O LADO NA LINHA 0 É A ODD, NÃO O MANDO — decisão do Victor na B3
  (comentário de 25/08/2026, ClickUp `wdx6zev656`): "vamos pela menor odd, com desempate
  pelo mando quando as odds forem iguais". A primeira entrega (#138, 01/09) implementou só
  mando — corrigido aqui. O `outcome_e_favorito_por_odd_col` é um BOOLEAN já resolvido pelo
  CHAMADOR (TRUE quando este `outcome_col` tem a menor odd pra esse fixture+linha, com
  empate desempatado pelo mando) — o macro não tem acesso a odd sozinho, porque ela não
  está nos três argumentos de sempre. `NULL`/omitido cai no mando puro: é a degradação
  graciosa de quando não há odd pra essa linha (mesmo padrão do resto do projeto — dado
  ausente nunca propaga NULL pro veredito, decide pelo fallback mais simples). MESMA regra
  em `int_futebol_premissas_ah` (`is_favorito`/`is_azarao`), porque os dois têm de
  concordar sobre qual lado é qual (é a chave do join com o denominador — o teto do
  catálogo desde a PPP#365/ADR 0013).

  ⚠️ FAIL-CLOSED, igual ao `futebol_market_slug`: saída fora do catálogo resolve para NULL
  — a "12" da Dupla Chance, e qualquer `outcome` que o de-vig emita e o Motor não pontue.
  NULL aqui é o que mantém a linha FORA do denominador e fora da cobrança da guarda de
  cobertura, que é exatamente onde ela deve estar: a decisão de não pontuar a "12" é nossa
  e já está carimbada na `porta_saida_catalogada`. Um lado inventado por acidente casaria
  com nenhuma linha do seed, e o modelo o trataria como denominador ausente.

  Os argumentos são expressões já qualificadas pelo chamador (ex.: `f.market`), porque os
  consumidores juntam as tabelas com aliases diferentes.
-#}
{% macro futebol_lado(market_col, outcome_col, line_col, outcome_e_favorito_por_odd_col=none) -%}
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
                -- linha 0 (B3, #109): a odd decide quem é favorito, mando só desempata
                -- odds iguais (ou ausentes). MESMA regra em `int_futebol_premissas_ah`
                -- (is_favorito/is_azarao); os dois têm de concordar, porque é esta coluna
                -- que casa a linha com o p95 do lado.
                WHEN IF({{ outcome_col }} = 'Home', {{ line_col }}, -{{ line_col }}) = 0
                    THEN IF(
                        {% if outcome_e_favorito_por_odd_col is not none -%}
                        COALESCE({{ outcome_e_favorito_por_odd_col }}, {{ outcome_col }} = 'Home')
                        {%- else -%}
                        {{ outcome_col }} = 'Home'
                        {%- endif %},
                        'Favorito', 'Azarao'
                    )
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
