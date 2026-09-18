

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
WITH apitados AS (
    SELECT
        fixture_id,
        DATE(kickoff_utc) AS dia_kickoff,
        score
    FROM `smartbetting-dados`.`futebol`.`fact_value_funnel`
    -- Kickoff NULL não sela: sem hora não há dia, e a linha é gravável para sempre por
    -- decisão do modelo (fail-open, ADR 0003). Selá-la seria congelar o que o funil
    -- deliberadamente não congela.
    WHERE kickoff_utc IS NOT NULL
      -- NO APITO, e não na virada do dia. O grão é por FIXTURE, então não há "metade do
      -- dia ainda sendo escrita" a proteger: um jogo que já começou está inteiramente
      -- congelado, e esperar a meia-noite deixaria o dia mais novo até 24 h sem selo —
      -- justamente o dia em que um rebuild indevido é mais provável, logo depois de um
      -- deploy. É a mesma fronteira que congela o funil, e de propósito.
      AND kickoff_utc < CURRENT_TIMESTAMP()
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
    FROM apitados
    GROUP BY fixture_id, dia_kickoff
)

SELECT
    a.fixture_id,
    a.dia_kickoff,
    a.linhas,
    a.soma_nota,
    CURRENT_TIMESTAMP() AS selado_em
FROM agregado a

-- INSERT-ONLY: sem `unique_key`, o incremental do dbt-bigquery insere e nunca atualiza.
-- O anti-join é o que impede a duplicata — e é ele, não o merge, que garante que um selo
-- já escrito jamais é revisto.
LEFT JOIN `smartbetting-dados`.`futebol`.`fact_value_funnel_selo` s
       ON s.fixture_id = a.fixture_id
      AND s.dia_kickoff = a.dia_kickoff
WHERE s.fixture_id IS NULL
