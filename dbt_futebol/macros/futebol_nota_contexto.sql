{#-
  A NOTA DE CONTEXTO, declarada num lugar só (issue #103, ADR 0012).

  É a nota depois que o preço saiu dela: **pontos de premissa menos as penalidades de
  CONTEXTO, com piso em zero**, e nada mais. Sem `pts_valor`, sem corroboração e sem as
  quatro penalidades de odd.

  ⚠️ POR QUE MACRO, E SEM ARGUMENTO. A composição tem DOIS consumidores — o
  `fact_value_funnel`, que a grava, e a `assert_funil_nota_contexto_reconstroi`, que a
  recompõe da tabela gravada — e os dois leem as MESMAS duas colunas, com os mesmos nomes:
  o funil normaliza `pts_premissas` e `penalidades_especificas_pts` nos cinco ramos antes
  de somar, e a tabela publica as duas com esses nomes.

  Sem argumento porque argumento é porta de entrada: `futebol_nota_contexto('pts_valor +
  pts_premissas')` devolveria uma nota com preço dentro sem que uma linha deste arquivo
  mudasse, e a `assert_nota_contexto_sem_preco` — que varre o TEXTO que este macro emite —
  não veria nada. Com a composição fechada aqui, a única forma de pôr preço na nota é
  editar este arquivo, que é exatamente o que a sentinela vigia.

  ⚠️ SEM `COALESCE`, e de propósito (ADR 0003). `GREATEST(NULL, 0)` no BigQuery é NULL, e é
  o valor certo para a saída que não tem premissa a avaliar — a "12" da Dupla Chance.
  Zero ali diria "foi avaliada e tirou zero", que é outra coisa. É a mesma decisão que o
  `score` do funil já toma, e a guarda de reconstrução a absorve com `IS DISTINCT FROM`.

  As quatro penalidades de contexto que entram (e são o `penalidades_especificas_pts` de
  cada ramo, sem exceção): `pick_empate` (−10), `desfalque_proprio` (−15), `linha_extrema`
  (−10, Gols) e `handicap_alto` (−12, Handicap). Nenhuma lê preço: `linha_extrema` e
  `handicap_alto` leem a LINHA, que é característica do mercado apostado e não do preço
  dele. Medido na A4.0: elas ajudam (0,119 com, 0,105 sem).
-#}
{% macro futebol_nota_contexto() -%}
    GREATEST(pts_premissas - penalidades_especificas_pts, 0)
{%- endmacro %}


{#-
  OS COMPONENTES DE PREÇO, declarados num lugar só — a lista que a sentinela da decisão
  (`assert_nota_contexto_sem_preco`) procura dentro do texto emitido por
  `futebol_nota_contexto()`.

  São os três blocos que a A1 tirou da nota, mais os insumos crus de que eles saem:

    · o valor         — `pts_valor`, e o `edge` de que ele é o arredondamento por faixa;
    · a corroboração  — `pts_corroboracao` e as suas duas parcelas;
    · a penalidade de odd — o agregado `penalidades_globais_pts` e as quatro flags;
    · o preço cru     — `best_odd`, `avg_odd`, `prob_justa_fechamento`.

  ⚠️ `penalidades_especificas_pts` NÃO está aqui, e é a distinção inteira desta decisão:
  ela é a penalidade de CONTEXTO, e continua dentro da nota.

  ⚠️ A lista é de SUBSTRING. `avg_odd` casa dentro de `avg_odd_ex_best`, e é para casar —
  a sentinela reporta o componente encontrado, não a coluna exata, e reportar duas vezes o
  mesmo pecado é melhor que deixá-lo passar por diferença de sufixo.
-#}
{% macro futebol_componentes_de_preco() %}
    {{ return([
        'pts_valor',
        'edge',
        'pts_corroboracao',
        'modelo_api_concorda',
        'linha_sharp_confirma',
        'penalidades_globais_pts',
        'pen_odd_outlier',
        'pen_poucas_casas',
        'pen_odd_longshot',
        'pen_odd_juice',
        'best_odd',
        'avg_odd',
        'prob_justa_fechamento'
    ]) }}
{% endmacro %}
