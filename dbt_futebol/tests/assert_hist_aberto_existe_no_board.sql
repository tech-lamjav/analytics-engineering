{{ config(tags=['guarda'], severity='error') }}
-- GUARDA 2 DO EXPURGO DO BOARD (#85, ADR 0009): nada sai do `fact_value_opportunities` sem
-- ficar com a versão FECHADA no `fact_value_opportunities_hist`.
--
-- Uma chave "aberta" no histórico (`dbt_valid_to IS NULL`) diz: *esta oportunidade está no
-- board agora*. Se ela não está mais no mart, o histórico está mentindo — e a mentira é do
-- tipo que ninguém vê, porque o app lê o `hist` e recebe 200 com uma linha que já não
-- existe.
--
-- POR QUE A GUARDA 1 NÃO BASTA. A guarda 1 prova que o expurgo ACONTECE. Esta prova que ele
-- não vira PERDA. São as duas metades da mesma decisão: a ADR 0009 aceita apagar do board
-- justamente porque o histórico guarda — se o carimbo falhar, o expurgo deixa de ser uma
-- mudança de janela e passa a ser destruição de evidência. É a diferença entre "a linha
-- saiu de cartaz" e "a linha nunca existiu".
--
-- ⚠️ ELA DEPENDE DA ORDEM, e a ordem já está certa — foi verificada, não presumida. No
-- `workflow_futebol_odds.yml` a fase 3 é o `dbt snapshot` e a fase 4 é o
-- `dbt test --select tag:guarda`. O snapshot fecha (`invalidate_hard_deletes`) as chaves
-- que sumiram do mart, e só depois a guarda lê. Rodada ANTES do snapshot ela acusaria
-- vermelho em cima do funcionamento normal: entre o `dbt run` e o `dbt snapshot` toda linha
-- expurgada está legitimamente aberta no `hist` e ausente do mart.
--
-- Isso é o que faz esta guarda entrar sem tocar em YAML nenhum: a fase que ela precisa já
-- existe, com status próprio (`guardas_status`), e nenhum workflow precisa de redeploy.
--
-- ⚠️ Consequência para quem roda na mão: `dbt test --select tag:guarda` sem ter rodado o
-- `dbt snapshot` depois do `dbt run` acende vermelho aqui, e é vermelho legítimo — está
-- descrevendo o estado real do banco, não um defeito do código.
--
-- A chave é reconstruída com o MESMO `CONCAT` NULL-safe do snapshot (`line_value` é NULL em
-- match_winner/btts/double_chance). Se as duas expressões divergirem, esta guarda acende —
-- o que também é o comportamento certo: chave que não casa entre mart e histórico é
-- exatamente o defeito que ela procura.

WITH board AS (
    SELECT
        CONCAT(
          CAST(fixture_id AS STRING), '|', market, '|', outcome, '|',
          COALESCE(CAST(line_value AS STRING), 'NONE')
        ) AS opportunity_key
    FROM {{ ref('fact_value_opportunities') }}
)

SELECT
    h.opportunity_key,
    h.fixture_id,
    h.market,
    h.outcome,
    h.line_value,
    h.janela_usada,
    h.dbt_valid_from,
    'chave aberta no hist (dbt_valid_to IS NULL) sem par no board — o histórico está dizendo que a oportunidade está no ar e ela não está. Ou o snapshot não rodou depois do run, ou a linha evaporou do mart sem carimbo' AS diagnostico
FROM {{ ref('fact_value_opportunities_hist') }} h
LEFT JOIN board b
       ON b.opportunity_key = h.opportunity_key
WHERE h.dbt_valid_to IS NULL
  AND b.opportunity_key IS NULL
