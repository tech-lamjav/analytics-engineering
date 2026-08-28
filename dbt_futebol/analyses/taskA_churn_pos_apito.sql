/*
    [A-86] A CHURN PÓS-APITO — quantas versões do `hist` nasceram DEPOIS do jogo.

    ⚠️ OS NÚMEROS NÃO MORAM AQUI. Eles estão em `docs/TASKA_RESULTADOS.md`, seção do #86, com o
    instante da medição e o teto da janela. Este cabeçalho carrega o CRITÉRIO e as ARMADILHAS —
    o que muda quando a lógica muda, nunca quando o número muda.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE ESTE ARQUIVO EXISTE

    O congelamento de 17/08 (ADR 0009, issue #80) publicou "15.452 versões / 210 chaves / 14.946
    pós-apito" **sem guardar a query**. A #86 tinha de remedir "com a mesma query do congelamento"
    e ela não existia em lugar nenhum do repositório — foi preciso RECONSTRUIR o critério e depois
    provar que era o mesmo, reproduzindo os dois checkpoints congelados (ver a calibração abaixo).
    Este arquivo existe para que a próxima remedição não pague isso de novo.

    ────────────────────────────────────────────────────────────────────────────────
    O CRITÉRIO, em uma linha

        versão pós-apito  ⇔  h.dbt_valid_from > f.kickoff_utc

    Três decisões dentro dele, e nenhuma é cosmética:

      1. `dbt_valid_from` é IMUTÁVEL — é o instante em que o snapshot inseriu aquela versão, e
         nada depois o reescreve. É por isso que a janela de qualquer remedição se escreve com
         ele, e é por isso que a série inteira continua replayável a partir de hoje.

         ⚠️ `dbt_valid_to` NÃO é imutável: ele é escrito quando a versão seguinte nasce (ou quando
         `invalidate_hard_deletes` fecha a chave). Toda contagem de "chave morta" do congelamento
         de 17/08 — as 89, das quais 54 morreram depois do apito — é IRREPRODUTÍVEL por replay:
         relendo o `hist` hoje com o teto de 17/08, as 210 chaves aparecem fechadas, porque elas
         fecharam depois. Quem quiser essa métrica tem de medi-la no dia, não reconstruí-la — e é
         por isso que ela não está entre as saídas deste arquivo.

      2. `LEFT JOIN fact_fixtures`, nunca INNER. Fixture ausente é fail-open (ADR 0003): a
         comparação vira NULL, a versão não conta como pós-apito, e ela sai contada à parte
         (`sem_kickoff`) em vez de sumir dentro do join. Nas duas medições deu 0 — o dia em que
         der outra coisa, o número aparece em vez de calar.

      3. `kickoff_utc` é lido AGORA, não no instante da versão. Jogo remarcado move o próprio
         apito, e uma versão pode trocar de lado da fronteira retroativamente. É o preço de o
         `hist` não carregar kickoff; declará-lo é mais barato que carimbar coluna nova em tabela
         sincronizada, que a ADR 0009 recusou de propósito.

    ────────────────────────────────────────────────────────────────────────────────
    A CALIBRAÇÃO — é ela que satisfaz o aceite "mesma query do congelamento"

    O critério acima reproduz os DOIS checkpoints congelados, ao número:

      · teto 2026-08-17 16:32:17.191019 UTC  →  15.452 versões / 210 chaves / 14.946 pós-apito
        / média 668,2 h   (o congelamento da ADR 0009, issue #80)
      · teto 2026-08-20 16:41:25 UTC         →  17.719 pós-apito
        (o fatiamento por faixa publicado na #85 no dia do deploy)

    O teto de 17/08 não foi escolhido a dedo: é a última versão do lote das 16:32 daquele dia, o
    único instante em que o `hist` tem exatamente 15.452 linhas. Reproduzir DOIS pontos com um
    critério de uma linha é o que torna a remedição comparável ao baseline em vez de uma métrica
    nova. Para refazer a calibração, é só mover `corte_inicio`/`corte_fim` abaixo.

    ────────────────────────────────────────────────────────────────────────────────
    AS TRÊS FAIXAS, e por que o corte é em 24 h

    Contar "pós-apito" em bloco mistura três coisas com donos diferentes (pré-atribuição feita na
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

    ────────────────────────────────────────────────────────────────────────────────
    A DESCONTINUIDADE DO `.25` (#101), 2026-08-21 19:05:23 UTC

    O conserto da `is_half_line` tirou a linha de quarto (`.25`) do board. Ele muda VOLUME, não
    taxa de nascimento pós-apito: é monotônico (nenhum candidato anda de quarto para meia), então
    nada passou a ser publicado que não era. As contagens absolutas de versão e de chave caem a
    partir dali, e por isso toda saída deste arquivo sai FATIADA pelos dois lados do corte.

    ⚠️ `lotes_snapshot` e `dias_observados` saem junto das contagens, e não são enfeite: as duas
    fatias não têm o mesmo tamanho (a de antes do corte é de horas, a de depois é de dias). Sem
    eles, "zero de um lado" se lê como efeito quando pode ser só janela curta.

    ────────────────────────────────────────────────────────────────────────────────
    OS PARÂMETROS

    Trocar os três `set` abaixo e nada mais. Eles compilam para literais, então o SQL compilado é
    a rodada — carimbar o teto é o que torna a medição reproduzível, que é o vício que este
    arquivo existe para não repetir.

    Nada aqui escreve. É `compile` + `bq query`, nunca `dbt run` (a armadilha de ambiente da
    ADR 0009: `dev` e `prod` apontam para o mesmo dataset).
*/

{% set corte_inicio = "2026-08-20 16:41:25 UTC" %}   {# deploy do #85 em produção #}
{% set corte_fim    = "2026-08-28 12:40:53 UTC" %}   {# o instante desta medição #}
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

{# Um bloco por lado do corte, mais o TOTAL da janela. #}
agregado AS (

    SELECT
        lado_do_corte,
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
        COUNTIF(horas_apos_apito > 24)                                  AS faixa_acima_24h,
        ROUND(AVG(IF(horas_apos_apito > 0, horas_apos_apito, NULL)), 1) AS media_h,
        ROUND(MAX(horas_apos_apito), 1)                                 AS max_h
    FROM versoes
    GROUP BY lado_do_corte

    UNION ALL

    SELECT
        'TOTAL da janela',
        COUNT(DISTINCT dbt_valid_from),
        ROUND(TIMESTAMP_DIFF(MAX(dbt_valid_from), MIN(dbt_valid_from), MINUTE) / 1440, 2),
        COUNT(*),
        COUNT(DISTINCT opportunity_key),
        COUNTIF(kickoff_utc IS NULL),
        COUNTIF(horas_apos_apito > 0),
        COUNT(DISTINCT IF(horas_apos_apito > 0, opportunity_key, NULL)),
        COUNTIF(horas_apos_apito > 0  AND horas_apos_apito <= 10),
        COUNTIF(horas_apos_apito > 10 AND horas_apos_apito <= 24),
        COUNTIF(horas_apos_apito > 24),
        ROUND(AVG(IF(horas_apos_apito > 0, horas_apos_apito, NULL)), 1),
        ROUND(MAX(horas_apos_apito), 1)
    FROM versoes

),

{# O resíduo aberto por fixture. Se `faixa_acima_24h` for diferente de zero, é AQUI que se lê
   QUAL jogo — para o ticket de churn nascer com nome, e não com adjetivo. #}
residuo AS (

    SELECT
        FORMAT('fixture %d · %s · %s', fixture_id, competition, COALESCE(status_short, 'NULL'))
                                                        AS item,
        STRING_AGG(DISTINCT lado_do_corte, ' + ')       AS lado_do_corte,
        FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', ANY_VALUE(kickoff_utc)) AS kickoff_utc_fmt,
        COUNT(*)                                        AS pos_apito,
        COUNT(DISTINCT opportunity_key)                 AS chaves_pos_apito,
        ROUND(MAX(horas_apos_apito), 1)                 AS max_h,
        COUNTIF(horas_apos_apito > 24)                  AS faixa_acima_24h
    FROM versoes
    WHERE horas_apos_apito > 0
    GROUP BY fixture_id, competition, status_short

),

{# Saída alta e estreita: o bloco `agregado` responde o aceite, o bloco `residuo` nomeia quem
   sobrou. As colunas que só um dos blocos tem saem NULL no outro, de propósito — inventar zero
   ali faria a leitura confundir "não se aplica" com "medido e deu zero". #}
tudo AS (

    SELECT
        '1 · agregado'      AS bloco,
        lado_do_corte,
        CAST(NULL AS STRING) AS item,
        CAST(NULL AS STRING) AS kickoff_utc_fmt,
        lotes_snapshot,
        dias_observados,
        versoes,
        chaves,
        sem_kickoff,
        pos_apito,
        chaves_pos_apito,
        faixa_0_10h,
        faixa_10_24h,
        faixa_acima_24h,
        media_h,
        max_h
    FROM agregado

    UNION ALL

    SELECT
        '2 · residuo por fixture',
        lado_do_corte,
        item,
        kickoff_utc_fmt,
        CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        CAST(NULL AS INT64),
        CAST(NULL AS INT64),
        CAST(NULL AS INT64),
        pos_apito,
        chaves_pos_apito,
        CAST(NULL AS INT64),
        CAST(NULL AS INT64),
        faixa_acima_24h,
        CAST(NULL AS FLOAT64),
        max_h
    FROM residuo

)

SELECT
    *,
    {# o instante em que a rodada rodou — o teto está nos literais acima. #}
    CURRENT_TIMESTAMP() AS medido_em
FROM tudo
ORDER BY bloco, pos_apito DESC, lado_do_corte, item
