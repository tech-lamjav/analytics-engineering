{#-
  A FRONTEIRA DO EXPURGO DO BOARD, declarada num lugar só (issue #85, ADR 0009).

  O `fact_value_opportunities` não tinha filtro de data nem de status: a linha de um jogo
  que já terminou continuava sendo reavaliada e reemitida enquanto os modelos de premissa e
  o de-vig continuassem produzindo-a. Medido em 17/08/2026 no PRD, o board tinha 121 linhas
  e apenas 2 de jogo futuro, a mais velha de 19/06.

  A ADR 0009 decidiu que **o board é a janela do que ainda dá para apostar**. Este macro é
  essa janela, escrita como predicado.

  ⚠️ Por que macro e não SQL no modelo: a **guarda 1** (`assert_board_sem_jogo_encerrado`)
  espelha exatamente este predicado para provar que o expurgo aconteceu. Predicado copiado
  em dois arquivos é predicado que diverge no primeiro refactor — e a divergência aqui é
  muda nos dois sentidos: guarda mais frouxa que o mart nunca acende, guarda mais estrita
  que o mart acende sem defeito. Com um macro só, mart e guarda não têm como discordar.

  A fronteira é o STATUS, não o relógio:

    · expurgam os TERMINAIS — o jogo acabou (ou nunca vai acontecer): FT, AET, PEN, CANC,
      ABD, AWD, WO;
    · expurgam os AO VIVO — não se aposta pré-jogo com a bola rolando;
    · SOBREVIVEM `PST`, `SUSP` e `INT`. Kickoff no passado com jogo ainda por acontecer é
      oportunidade legítima, e um corte por relógio a mataria.

  A rede de segurança (kickoff + carência) existe para o jogo que passou do apito e **nunca
  recebeu status final** — falha de coleta de placar, não de modelagem. Ela é parametrizada
  em `var expurgo_carencia_horas` (default 24, declarado no `dbt_project.yml`) porque é um
  parâmetro da QUALIDADE DA COLETA, que é a task [C] e vai mudar. Nenhum workflow passa a
  var: mudar o default é mudar o arquivo, e isso é de propósito.

  ⚠️ A CARÊNCIA NÃO SE APLICA A `PST`/`SUSP`/`INT` (ambiguidade da spec-mãe, resolvida no
  fatiamento da #85). Sem essa exceção a rede de 24 h expurgaria exatamente a linha que a
  decisão manda preservar — jogo adiado fica adiado por semanas — e a guarda 1, que espelha
  o predicado, acenderia vermelha nela sem que houvesse defeito nenhum.

  ⚠️ NULL É FAIL-OPEN, DE PROPÓSITO. Se o fixture não existir em `fact_fixtures`, tanto o
  `IN` quanto o `NOT IN` devolvem NULL e o predicado inteiro vira NULL — a linha NÃO é
  expurgada. É a ADR 0003 aplicada aqui (dado faltante diagnostica, não elimina): sumir com
  a linha por falta do lado direito do join seria a perda silenciosa que a ADR 0009 existe
  para impedir. Quem grita nesse caso é a guarda 1, que trata fixture ausente como vermelho
  próprio, com diagnóstico próprio. Por isso o consumidor deste macro escreve
  `NOT COALESCE(<predicado>, FALSE)` — explícito, nunca `NOT <predicado>`.
-#}

{#- Terminais: o jogo acabou, ou foi decidido fora de campo, ou não vai acontecer. -#}
{% macro futebol_status_terminais() -%}
    'FT', 'AET', 'PEN', 'CANC', 'ABD', 'AWD', 'WO'
{%- endmacro %}


{#-
  Ao vivo: a bola está rolando. `SUSP` e `INT` são estados de jogo interrompido e ficam
  FORA desta lista de propósito — eles sobrevivem, porque o jogo ainda pode ser retomado.
-#}
{% macro futebol_status_ao_vivo() -%}
    '1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'
{%- endmacro %}


{#-
  Os que sobrevivem mesmo com o kickoff no passado: adiado, suspenso, interrompido.
  Kickoff velho aqui não é sintoma de coleta ruim — é o estado real do jogo.
-#}
{% macro futebol_status_sobrevivem() -%}
    'PST', 'SUSP', 'INT'
{%- endmacro %}


{#-
  O predicado. TRUE = a linha sai do board.

  `status_col` e `kickoff_col` são expressões já qualificadas pelo chamador (ex.:
  `fx.status_short`, `fx.kickoff_utc`), porque os dois consumidores juntam `fact_fixtures`
  com aliases diferentes.
-#}
{% macro futebol_expurga_do_board(status_col, kickoff_col) -%}
    (
        {{ status_col }} IN ({{ futebol_status_terminais() }}, {{ futebol_status_ao_vivo() }})
        OR (
            TIMESTAMP_ADD({{ kickoff_col }}, INTERVAL {{ var('expurgo_carencia_horas') }} HOUR)
                < CURRENT_TIMESTAMP()
            AND {{ status_col }} NOT IN ({{ futebol_status_sobrevivem() }})
        )
    )
{%- endmacro %}
