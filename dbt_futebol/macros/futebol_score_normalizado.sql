{#-
  A NOTA NORMALIZADA, declarada num lugar só (issue #105, ADR 0005).

  É a nota de contexto reescalada pelo denominador congelado do lado, em 0–100:

      LEAST(100, ROUND(nota_contexto / p95 × 100))

  O serviço dela é fazer o 100 significar a MESMA COISA nos onze lados — o topo da escala
  ancorado no mesmo quantil. Sem ela, a nota é dividida por uma soma de pesos que nunca
  ocorre, e quanto mais premissa um mercado tem, mais baixa é a nota dele: o mercado onde
  se investiu mais modelagem é o mais punido.

  ⚠️ SEM ARGUMENTO, pela mesma razão do `futebol_nota_contexto()`: argumento é porta de
  entrada. `futebol_score_normalizado('score')` devolveria a nota COM PREÇO reescalada sem
  que uma linha deste arquivo mudasse. As duas colunas de que ele depende chegam com nome
  fixo — `nota_contexto`, que o funil grava, e `p95`, que vem do seed
  `futebol_p95_nota_contexto`.

  ⚠️ A NOTA É ABSOLUTA, e nunca percentil dentro do lado (ADR 0005). Dividir por um número
  CONGELADO é o que a torna absoluta: o denominador não sabe quantas linhas boas o lado teve
  hoje. A alternativa relativa garantiria volume de publicação independente de qualidade,
  contradiria a degradação graciosa e envenenaria o funil — a rejeição passaria a ser X% por
  construção. O preço, declarado em voz alta: **os mercados publicam em taxas diferentes, e
  isso é consequência, não defeito.**

  As três decisões que a ordem do `CASE` codifica, de cima para baixo:

  1. ⚠️ `nota_contexto` NULL ⇒ NULL, e é o PRIMEIRO ramo. É a saída que não tem premissa a
     avaliar — a "12" da Dupla Chance —, e zero ali diria "foi avaliada e tirou zero", que é
     outra coisa (ADR 0003). É o mesmo que o `score` e a `nota_contexto` já fazem, e as oito
     portas absorvem o NULL individualmente.

  2. ⚠️ DENOMINADOR ZERO ⇒ ZERO, escrito como zero EXPLÍCITO e **não** como `SAFE_DIVIDE`.
     O `SAFE_DIVIDE` devolveria NULL, a comparação com a régua também viraria NULL, e a
     linha sairia sem passar e sem ser marcada — descarte silencioso é exatamente o que a
     ADR 0006 proíbe. São os dois lados sem lado apostado: o empate do 1X2 e o `Pick` do
     Handicap. O ramo cobre também o denominador AUSENTE (lado que não está no seed): a
     linha vira zero e reprova visivelmente, em vez de virar NULL e sumir — e quem acende
     nesse caso é a guarda de cobertura, não este `CASE`.

  3. ⚠️ CLAMP EM 100 EXPLÍCITO. Com o p95 no denominador, ~5% das linhas de cada lado ficam
     acima de 100 POR CONSTRUÇÃO — não é erro, é o quantil. Sem o `LEAST` a nota do topo do
     Gols passaria de 100 e a régua deixaria de ser 0–100.

  ⚠️ O `CAST(... AS INT64)` fica DENTRO do `LEAST`, e não fora: `ROUND` devolve FLOAT64 no
  BigQuery, e `LEAST(100, <FLOAT64>)` promoveria o 100 a FLOAT64 — a coluna sairia
  `54.0` em vez de `54` e toda comparação com a régua passaria a ser entre float e inteiro.

  O que esta normalização NÃO compra está na ADR 0005 e no PR: ela não iguala a média, não
  cria resolução (o azarão do Handicap e o "Não" do BTTS têm 3 premissas e 8 notas possíveis
  cada — isso é granularidade de catálogo e pertence à [B]) e não cria sinal.
-#}
{% macro futebol_score_normalizado() -%}
    CASE
        WHEN nota_contexto IS NULL      THEN NULL
        WHEN p95 IS NULL OR p95 <= 0    THEN 0
        ELSE LEAST(100, CAST(ROUND(nota_contexto / p95 * 100) AS INT64))
    END
{%- endmacro %}
