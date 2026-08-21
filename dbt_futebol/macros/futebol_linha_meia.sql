{#-
  A PORTA DA LINHA MEIA, declarada num lugar só (issue #101).

  Handicap asiático e Gols O/U têm LINHA, e o quarto da linha decide o que acontece com a
  aposta quando o placar bate nela:

    · x.0   linha cheia  — o placar pode bater exatamente: PUSH, a aposta inteira volta.
    · x.25  linha de quarto — metade em x.0 e metade em x.5: MEIO-PUSH.
    · x.5   linha meia   — o placar não pode bater: a aposta ganha ou perde, nunca volta.
    · x.75  linha de quarto — metade em x.5 e metade em x1.0: MEIO-PUSH.

  Só a **meia** é resolvida em duas saídas exaustivas. É por isso que a porta existe: o
  de-vig é 2-way e normaliza as probabilidades sobre Over/Under (ou Home/Away) como se
  fossem as únicas saídas possíveis. Quando parte da aposta pode voltar como push, essa
  normalização superdimensiona o edge — o número publicado descreve uma aposta que não é
  a que o usuário faria.

  ⚠️ O DEFEITO QUE ESTE MACRO CONSERTA (#101). A expressão anterior comparava em MEIOS:

      MOD(CAST(ROUND(ABS(line_value) * 2) AS INT64), 2) = 1

  e o BigQuery arredonda **meio para longe do zero** (`ROUND(0.5) = 1`). Então:

      | line_value | ABS*2 | ROUND | MOD 2 | resultado | correto? |
      |------------|-------|-------|-------|-----------|----------|
      | x.0        | 0.0   | 0     | 0     | false     | ✅       |
      | x.25       | 0.5   | 1     | 1     | TRUE      | ❌       |
      | x.5        | 1.0   | 1     | 1     | true      | ✅       |
      | x.75       | 1.5   | 2     | 0     | false     | ✅ (por sorte) |

  A linha de quarto `.25` era classificada como meia e entrava no gate como se não
  tivesse push. Medido no `int_futebol_odds_devig` em 20/08/2026, mercados 4 e 5:
  **18.809 linhas** de `.25` contra 29.260 de `.5`. E no histórico já publicado,
  **78 das 234 chaves (33,3%)** do `fact_value_opportunities_hist` estão numa linha de
  quarto. O `.75` acertava por acidente aritmético, não por construção.

  ⚠️ E O DEFEITO NÃO SE VÊ NO NÚMERO. As linhas de quarto aparecem com edge publicado
  ligeiramente MENOR que as de meia (3,47% vs 4,33% em Gols; 3,44% vs 3,77% em Handicap).
  A inflação é do edge publicado contra o valor VERDADEIRO, nunca contra o edge das `.5` —
  as duas populações são indistinguíveis na tela, e nada no número denuncia que numa delas
  parte do risco pode voltar como push.

  Comparar em QUARTOS em vez de meios torna o `.75` correto por construção, e não por
  sorte: em quartos, `resto 2` é a definição de meia, e nenhum dos outros três restos
  ({0, 1, 3}) pode ser alcançado por arredondamento a partir dela.

  ⚠️ POR QUE MACRO E NÃO SQL NO MODELO — e esta é a lição que o próprio defeito ensinou:
  a expressão tinha TRÊS cópias (`fact_value_opportunities`, `fact_value_funnel` e a
  análise `taskA_linha_de_base`), e o funil nasceu com o defeito porque copiou a
  expressão do board **byte a byte**, de propósito, para que a guarda
  `assert_funil_paridade_com_board` pudesse provar que o funil descreve o board. Predicado
  copiado é predicado que diverge no primeiro refactor — e aqui a divergência seria muda:
  a paridade continuaria verde comparando dois erros iguais. Com um macro só, os três não
  têm como discordar. É a mesma razão de `futebol_expurgo.sql`.

  ⚠️ NULL É NULL, DE PROPÓSITO. Mercado sem linha (1X2 / BTTS / Dupla Chance) tem
  `line_value` NULL e o predicado resolve para NULL — não para FALSE. A porta não se
  aplica a esses mercados; quem a consome escreve `market NOT IN (...) OR is_half_line`,
  e o `COALESCE(..., FALSE)` fica no CONSUMIDOR, onde a degradação graciosa do Motor
  pertence. Resolver aqui para FALSE apagaria a diferença entre "esta linha pode dar push"
  e "este mercado não tem linha".
-#}

{#-
  TRUE = a linha é meia (.5) e não pode dar push nem meio-push.
  NULL onde não há linha. `coluna` é a expressão já qualificada pelo chamador.
-#}
{% macro futebol_e_linha_meia(coluna) -%}
    (MOD(CAST(ROUND(ABS({{ coluna }}) * 4) AS INT64), 4) = 2)
{%- endmacro %}
