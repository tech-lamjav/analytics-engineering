{{ config(
    materialized='incremental',
    on_schema_change='append_new_columns',
    full_refresh=false,
    cluster_by=['dia_kickoff'],
    description='O SELO DE IMUTABILIDADE DO FUNIL (#96, ADR 0011). 1 linha por (fixture_id, dia_kickoff) já passado, com a CONTAGEM e a SOMA DE NOTA que o fact_value_funnel tinha na primeira vez em que aquele dia ficou para trás. Escrito UMA VEZ e nunca reescrito — é a única testemunha externa que a guarda de imutabilidade pode consultar: um rebuild que reescrevesse o passado apagaria, junto, qualquer evidência guardada DENTRO do próprio funil. É a mesma lição da costura B da task [F] e da guarda de reconciliação: guarda que lê só o próprio produto não é guarda. NÃO VAI PARA O SUPABASE e não tem leitor no app.'
) }}

-- ============================================================================
-- POR QUE ESTA TABELA EXISTE
--
-- O aceite da #96 pede que "contagem e soma de nota por dia de kickoff já passado não
-- mudem ENTRE BUILDS". Entre builds é a parte difícil: nenhuma consulta ao funil de agora
-- sabe o que o funil de ontem dizia. O `gravado_em` quase resolve — mas ele é reescrito
-- junto com a linha, então um rebuild completo produz uma tabela internamente coerente e
-- inteiramente nova, e a guarda de congelamento (que só olha `origem = 'corrente'`) passa
-- por ela sem acender. O selo é o registro que o rebuild NÃO consegue reescrever.
--
-- O GRÃO INCLUI O FIXTURE, e não é detalhe (ADR 0011, jogo adiado): selar só por dia
-- deixaria a guarda vermelha para sempre no primeiro `PST`. O jogo adiado muda de dia,
-- some do agregado do dia velho, e um selo por dia acusaria uma diferença que é o
-- comportamento correto. Com o fixture na chave, o selo do dia velho fica ÓRFÃO (o
-- fixture não mora mais lá), a guarda o reconhece e o ignora, e o fixture é selado de
-- novo quando o dia NOVO dele passar.
--
-- ⚠️ `full_refresh=false` pelo mesmo motivo do funil: a fase de RECOVERY do
-- `workflow_futebol_odds` roda o mesmo `--select` com `--full-refresh`. Um selo
-- reconstruído a partir do funil de agora é um selo que concorda com qualquer coisa.
--
-- ⚠️ Quando o funil PRECISAR ser reconstruído de propósito (mudança de esquema que exija
-- recriar a tabela), o selo tem de ser derrubado JUNTO, no mesmo passo. Derrubar só um
-- dos dois deixa a guarda vermelha permanentemente — e guarda permanentemente vermelha
-- morre ignorada.
-- ============================================================================
WITH passados AS (
    SELECT
        fixture_id,
        DATE(kickoff_utc) AS dia_kickoff,
        score
    FROM {{ ref('fact_value_funnel') }}
    -- Kickoff NULL não sela: sem hora não há dia, e a linha é gravável para sempre por
    -- decisão do modelo (fail-open, ADR 0003). Selá-la seria congelar o que o funil
    -- deliberadamente não congela.
    WHERE kickoff_utc IS NOT NULL
      -- `< CURRENT_DATE()` e não `kickoff < now`: um dia só está inteiro no passado
      -- quando o dia seguinte começou. Selar um dia ainda em curso congelaria a metade
      -- dele que ainda estava sendo escrita.
      AND DATE(kickoff_utc) < CURRENT_DATE()
),

agregado AS (
    SELECT
        fixture_id,
        dia_kickoff,
        COUNT(*)                        AS linhas,
        -- NUMERIC, e não FLOAT64: soma de float depende da ORDEM das parcelas, e a ordem
        -- de leitura de uma tabela do BigQuery não é estável entre execuções. Em NUMERIC
        -- a soma é exata, e a guarda compara igualdade sem tremer no último bit (#92).
        SUM(CAST(score AS NUMERIC))     AS soma_nota
    FROM passados
    GROUP BY fixture_id, dia_kickoff
)

SELECT
    a.fixture_id,
    a.dia_kickoff,
    a.linhas,
    a.soma_nota,
    CURRENT_TIMESTAMP() AS selado_em
FROM agregado a
{% if is_incremental() %}
-- INSERT-ONLY: sem `unique_key`, o incremental do dbt-bigquery insere e nunca atualiza.
-- O anti-join é o que impede a duplicata — e é ele, não o merge, que garante que um selo
-- já escrito jamais é revisto.
LEFT JOIN {{ this }} s
       ON s.fixture_id = a.fixture_id
      AND s.dia_kickoff = a.dia_kickoff
WHERE s.fixture_id IS NULL
{% endif %}
