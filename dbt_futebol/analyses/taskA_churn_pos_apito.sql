/*
    [A-86] A CHURN PÓS-APITO — quantas versões do `hist` nasceram DEPOIS do jogo.

    ⚠️ OS NÚMEROS NÃO MORAM AQUI. Eles estão em `docs/TASKA_RESULTADOS.md`, seção do #86, com o
    instante da medição e o teto da janela. Este cabeçalho carrega o CRITÉRIO e as ARMADILHAS —
    o que muda quando a lógica muda, nunca quando o número muda.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE ESTE ARQUIVO EXISTE

    O congelamento de 17/08 (ADR 0009, issue #80) publicou as contagens do baseline **sem guardar
    a query**. A #86 tinha de remedir "com a mesma query do congelamento" e ela não existia em
    lugar nenhum do repositório — foi preciso RECONSTRUIR o critério e depois provar que era o
    mesmo, reproduzindo os checkpoints congelados. Este arquivo existe para que a próxima
    remedição não pague isso de novo.

    ────────────────────────────────────────────────────────────────────────────────
    O CRITÉRIO, em uma linha

        versão pós-apito  ⇔  h.dbt_valid_from > f.kickoff_utc

    Três decisões dentro dele, e nenhuma é cosmética:

      1. `dbt_valid_from` é IMUTÁVEL — é o instante em que o snapshot inseriu aquela versão, e
         nada depois o reescreve. É por isso que a janela de qualquer remedição se escreve com
         ele, e é por isso que a série inteira continua replayável a partir de hoje.

         ⚠️ `dbt_valid_to` NÃO é imutável: ele é escrito quando a versão seguinte nasce (ou quando
         `invalidate_hard_deletes` fecha a chave). Toda contagem de "chave morta" do congelamento
         de 17/08 é IRREPRODUTÍVEL por replay: relendo o `hist` hoje com o teto daquele dia, as
         chaves aparecem fechadas, porque elas fecharam depois. Quem quiser essa métrica tem de
         medi-la no dia, não reconstruí-la — e é por isso que ela não está entre as saídas daqui.

      2. `LEFT JOIN fact_fixtures`, nunca INNER. Fixture ausente é fail-open (ADR 0003): a
         comparação vira NULL, a versão não conta como pós-apito, e ela sai contada à parte
         (`sem_kickoff`) em vez de sumir dentro do join.

      3. `kickoff_utc` é lido AGORA, não no instante da versão. Jogo remarcado move o próprio
         apito, e uma versão pode trocar de lado da fronteira retroativamente. É o preço de o
         `hist` não carregar kickoff; declará-lo é mais barato que carimbar coluna nova em tabela
         sincronizada, que a ADR 0009 recusou de propósito.

    ────────────────────────────────────────────────────────────────────────────────
    A CALIBRAÇÃO — é ela que satisfaz o aceite "mesma query do congelamento"

    O critério acima reproduz, ao número e com as faixas, os DOIS checkpoints congelados. Basta
    mover os cortes abaixo:

      · `corte_inicio` = época, `corte_fim` = 2026-08-17 16:32:17.191019 UTC
        → o congelamento da ADR 0009, publicado no #80
      · `corte_inicio` = época, `corte_fim` = 2026-08-20 16:41:25 UTC
        → o fatiamento por faixa publicado no #85, no dia do deploy

    O teto de 17/08 não é escolha a dedo: é a última versão do lote das 16:32 daquele dia, o único
    instante em que o `hist` bate exatamente a contagem publicada. **As contagens que os dois
    tetos devolvem estão na seção do #86 do `TASKA_RESULTADOS.md`** — reproduzir DOIS pontos com
    um critério de uma linha é o que torna a remedição comparável ao baseline em vez de uma
    métrica nova.

    ────────────────────────────────────────────────────────────────────────────────
    AS TRÊS FAIXAS, e por que o corte é em 24 h

    Contar "pós-apito" em bloco mistura três coisas com donos diferentes (pré-atribuição feita no
    #85 ANTES do deploy, justamente para esta medição atribuir em vez de investigar):

      0–10 h    o status ainda não chegou. `fact_fixtures` é reconstruída UMA VEZ POR DIA
                (`workflow-futebol-daily`, `0 9 * * *`) e o board a cada ciclo de odds, que não
                toca fixtures. Entre o apito e as 09:00 UTC seguintes o status ainda não é `FT` e
                a linha continua no board. Nenhuma carência alcança isto — a linha não passou de
                24 h. Dono: **task [C]** (frequência da coleta de placar).
      10–24 h   resíduo da carência. Função direta de `var expurgo_carencia_horas` (24, fixada
                pela ADR 0009). Quem quiser derrubá-lo baixa a var. Dono: **decisão de produto**.
      > 24 h    **defeito**. Passou da carência e o expurgo não pegou. É o único número cujo alvo
                é zero de verdade, e o único que vira ticket de churn.

    ⚠️ A fronteira é `> 24` e não `>= 24` de propósito: a carência do macro é
    `TIMESTAMP_ADD(kickoff, INTERVAL 24 HOUR) < CURRENT_TIMESTAMP()`, estritamente maior. Uma
    faixa `>= 24` acenderia vermelho na versão nascida no segundo exato da fronteira, que o mart
    ainda tinha o direito de emitir.

    ⚠️ E `PST`/`SUSP`/`INT` SAEM DA FAIXA DE DEFEITO, pelo mesmo motivo que saem do expurgo: a
    ADR 0009 os preserva **inclusive além da carência** ("kickoff no passado com jogo ainda por
    acontecer é oportunidade legítima, e um corte por relógio a mataria"). Um jogo adiado fica
    adiado por semanas e nasceria versão nova o tempo todo — contá-lo como defeito faria esta
    medição acusar o expurgo exatamente onde ele está obedecendo. A lista vem de
    `futebol_status_sobrevivem()`, o MESMO macro que o mart e a guarda 1 usam, nunca uma quarta
    cópia à mão. Eles saem contados à parte (`acima_24h_sobrevivente`), não apagados: sumir com
    eles esconderia um adiamento que virou entulho.

    ────────────────────────────────────────────────────────────────────────────────
    A DESCONTINUIDADE DO `.25` (#101), 2026-08-21 19:05:23 UTC

    O conserto da `is_half_line` tirou a linha de quarto (`.25`) do board. Ele muda VOLUME, não
    taxa de nascimento pós-apito: é monotônico (nenhum candidato anda de quarto para meia), então
    nada passou a ser publicado que não era. As contagens absolutas de versão e de chave caem a
    partir dali, e por isso toda saída deste arquivo sai FATIADA pelos dois lados do corte.

    ⚠️ `lotes_snapshot` e `dias_observados` saem junto das contagens, e não são enfeite: as duas
    fatias não têm o mesmo tamanho (a de antes do corte é de horas, a de depois é de dias). Sem
    eles, "zero de um lado" se lê como efeito quando pode ser só janela curta. `dias_observados` é
    o vão entre o primeiro e o último LOTE do lado, não o comprimento do intervalo de corte — é a
    janela em que houve reconstrução, que é o que dá chance a uma versão de nascer.

    ────────────────────────────────────────────────────────────────────────────────
    OS PARÂMETROS

    Trocar os três `set` abaixo e nada mais. Eles compilam para literais, então o SQL compilado é
    a rodada — carimbar o teto é o que torna a medição reproduzível, que é o vício que este
    arquivo existe para não repetir.

      · `corte_inicio`  o piso da janela (na #86, o instante do deploy do #85)
      · `corte_fim`     o teto (na #86, o instante da medição)
      · `corte_25`      a descontinuidade do `.25`. É história, não parâmetro: só muda se alguém
                        descobrir que o deploy foi outro.

    ────────────────────────────────────────────────────────────────────────────────
    COMO RODAR

        cd dbt_futebol
        DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_churn_pos_apito
        bq query --use_legacy_sql=false --format=csv \
          < target/compiled/dbt_futebol/analyses/taskA_churn_pos_apito.sql

    Nada aqui escreve. É `compile` + `bq query`, nunca `dbt run` (a armadilha de ambiente da
    ADR 0009: `dev` e `prod` apontam para o mesmo dataset).
*/

{% set corte_inicio = "2026-08-31 20:39:21 UTC" %}   {# DE#67: deploy do DE#60 (PR#66) — cadência de placar via poll de 15min #}
{% set corte_fim    = "2026-09-04 17:57:14 UTC" %}   {# DE#67: o instante desta medição, D+3,89 do deploy #}
{% set corte_25     = "2026-08-21 19:05:23 UTC" %}   {# conserto do .25 (#101) — história, não parâmetro #}

WITH versoes AS (

    SELECT
        h.opportunity_key,
        h.fixture_id,
        h.competition,
        h.dbt_valid_from,
        f.kickoff_utc,
        f.status_short,
        {# NULL quando o fixture não existe (fail-open, ADR 0003) — e NULL não entra em faixa
           nenhuma, por isso `sem_kickoff` é contado à parte. #}
        TIMESTAMP_DIFF(h.dbt_valid_from, f.kickoff_utc, MINUTE) / 60 AS horas_apos_apito,
        {# O mesmo `COALESCE(status, '')` do macro do expurgo: status nulo não é nenhum dos três
           que sobrevivem, então ele CAI na faixa de defeito em vez de escapar dela por NULL. #}
        COALESCE(f.status_short, '') IN ({{ futebol_status_sobrevivem() }}) AS status_sobrevive,
        IF(
            h.dbt_valid_from <= TIMESTAMP '{{ corte_25 }}',
            'A · antes do .25',
            'B · depois do .25'
        ) AS lado_do_corte
    FROM {{ ref('fact_value_opportunities_hist') }} h
    LEFT JOIN {{ ref('fact_fixtures') }} f USING (fixture_id)
    WHERE h.dbt_valid_from >  TIMESTAMP '{{ corte_inicio }}'
      AND h.dbt_valid_from <= TIMESTAMP '{{ corte_fim }}'

),

{# Um bloco por lado do corte, mais o TOTAL da janela. O total sai de `ROLLUP` e não de um
   segundo `SELECT`: as treze agregações copiadas divergiriam da primeira no primeiro refactor,
   e este repositório já pagou por predicado copiado (a meia-linha chegou a quatro cópias, #101
   e #114). `lado_do_corte` nunca é NULL de verdade — o `IF` acima só devolve dois literais —,
   então o `COALESCE` só pode estar nomeando a linha do rollup. #}
agregado AS (

    SELECT
        {# `v.` obrigatório: sem a qualificação, o `lado_do_corte` de dentro do COALESCE resolve
           para o ALIAS de saída (ele mesmo) e a linha do rollup sai sem rótulo, em silêncio. #}
        COALESCE(v.lado_do_corte, 'TOTAL da janela')                    AS lado_do_corte,
        COUNT(DISTINCT dbt_valid_from)                                  AS lotes_snapshot,
        ROUND(TIMESTAMP_DIFF(MAX(dbt_valid_from), MIN(dbt_valid_from), MINUTE) / 1440, 2)
                                                                        AS dias_observados,
        COUNT(*)                                                        AS versoes,
        COUNT(DISTINCT opportunity_key)                                 AS chaves,
        COUNTIF(kickoff_utc IS NULL)                                    AS sem_kickoff,
        COUNTIF(horas_apos_apito > 0)                                   AS pos_apito,
        COUNT(DISTINCT IF(horas_apos_apito > 0, opportunity_key, NULL)) AS chaves_pos_apito,
        COUNTIF(horas_apos_apito > 0  AND horas_apos_apito <= 10)       AS faixa_0_10h,
        COUNTIF(horas_apos_apito > 10 AND horas_apos_apito <= 24)       AS faixa_10_24h,
        COUNTIF(horas_apos_apito > 24 AND NOT status_sobrevive)         AS faixa_acima_24h,
        COUNTIF(horas_apos_apito > 24 AND status_sobrevive)             AS acima_24h_sobrevivente,
        ROUND(AVG(IF(horas_apos_apito > 0, horas_apos_apito, NULL)), 1) AS media_h,
        ROUND(MAX(horas_apos_apito), 1)                                 AS max_h
    FROM versoes v
    GROUP BY ROLLUP(v.lado_do_corte)

),

{# O resíduo aberto por fixture. Se `faixa_acima_24h` for diferente de zero, é AQUI que se lê
   QUAL jogo — para o ticket de churn nascer com nome, e não com adjetivo. #}
residuo AS (

    SELECT
        FORMAT('fixture %d · %s · %s', fixture_id, competition, COALESCE(status_short, 'NULL'))
                                                                    AS item,
        STRING_AGG(DISTINCT lado_do_corte, ' + ')                   AS lado_do_corte,
        FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', ANY_VALUE(kickoff_utc))  AS kickoff_utc_fmt,
        COUNT(*)                                                    AS pos_apito,
        COUNT(DISTINCT opportunity_key)                             AS chaves_pos_apito,
        COUNTIF(horas_apos_apito > 24 AND NOT status_sobrevive)     AS faixa_acima_24h,
        COUNTIF(horas_apos_apito > 24 AND status_sobrevive)         AS acima_24h_sobrevivente,
        ROUND(MAX(horas_apos_apito), 1)                             AS max_h
    FROM versoes
    WHERE horas_apos_apito > 0
    GROUP BY fixture_id, competition, status_short

),

{# Saída alta e estreita: o bloco `1` responde o aceite, o bloco `2` nomeia quem sobrou. Cada
   bloco alinha as colunas com nome dentro do próprio CTE, e o `UNION ALL` junta dois `*` já
   nomeados — é o padrão da casa (`taskA_linha_de_base_funil.sql`), e ele existe para que
   reordenar uma coluna num bloco não desalinhe o outro em silêncio. As colunas que só um dos
   blocos tem saem NULL no outro, de propósito: inventar zero ali faria a leitura confundir "não
   se aplica" com "medido e deu zero". #}
bloco_agregado AS (

    SELECT
        '1 · agregado'          AS bloco,
        lado_do_corte           AS lado_do_corte,
        CAST(NULL AS STRING)    AS item,
        CAST(NULL AS STRING)    AS kickoff_utc_fmt,
        lotes_snapshot          AS lotes_snapshot,
        dias_observados         AS dias_observados,
        versoes                 AS versoes,
        chaves                  AS chaves,
        sem_kickoff             AS sem_kickoff,
        pos_apito               AS pos_apito,
        chaves_pos_apito        AS chaves_pos_apito,
        faixa_0_10h             AS faixa_0_10h,
        faixa_10_24h            AS faixa_10_24h,
        faixa_acima_24h         AS faixa_acima_24h,
        acima_24h_sobrevivente  AS acima_24h_sobrevivente,
        media_h                 AS media_h,
        max_h                   AS max_h
    FROM agregado

),

bloco_residuo AS (

    SELECT
        '2 · residuo por fixture' AS bloco,
        lado_do_corte             AS lado_do_corte,
        item                      AS item,
        kickoff_utc_fmt           AS kickoff_utc_fmt,
        CAST(NULL AS INT64)       AS lotes_snapshot,
        CAST(NULL AS FLOAT64)     AS dias_observados,
        CAST(NULL AS INT64)       AS versoes,
        CAST(NULL AS INT64)       AS chaves,
        CAST(NULL AS INT64)       AS sem_kickoff,
        pos_apito                 AS pos_apito,
        chaves_pos_apito          AS chaves_pos_apito,
        CAST(NULL AS INT64)       AS faixa_0_10h,
        CAST(NULL AS INT64)       AS faixa_10_24h,
        faixa_acima_24h           AS faixa_acima_24h,
        acima_24h_sobrevivente    AS acima_24h_sobrevivente,
        CAST(NULL AS FLOAT64)     AS media_h,
        max_h                     AS max_h
    FROM residuo

),

tudo AS (
    SELECT * FROM bloco_agregado
    UNION ALL
    SELECT * FROM bloco_residuo
)

SELECT
    *,
    {# o instante em que a rodada rodou — o teto está nos literais do cabeçalho. #}
    CURRENT_TIMESTAMP() AS medido_em
FROM tudo
ORDER BY bloco, pos_apito DESC, lado_do_corte, item
