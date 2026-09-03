{% snapshot fact_value_opportunities_hist %}
{{
    config(
      target_schema='futebol',
      unique_key='opportunity_key',
      strategy='check',
      invalidate_hard_deletes=True,
      check_cols=[
        'janela_usada', 'edge', 'score', 'faixa', 'valor_fonte', 'score_versao',
        'best_odd', 'best_book', 'avg_odd', 'n_casas', 'prob_justa_fechamento',
        'penalidades_especificas_pts',
        'modelo_api_concorda', 'linha_sharp_confirma', 'pin_n_outcomes', 'is_half_line'
      ]
    )
}}

-- Histórico append-only de fact_value_opportunities: strategy=check só insere uma nova versão
-- quando algo em check_cols muda (ex.: janela_usada vira t1h/t15m, ou score/edge mudam) — runs
-- sem novidade não duplicam linha. invalidate_hard_deletes fecha (dbt_valid_to/dbt_is_deleted)
-- quando a oportunidade some do mart (deixou de passar no gate). ARRAY<STRING> (evidencias/avisos)
-- ficam de fora do check_cols de propósito: BigQuery não suporta =/IS DISTINCT FROM em arrays,
-- então check_cols='all' quebraria a SQL compilada. dbt_loaded_at também fica de fora (muda a
-- cada run, geraria versão nova sempre). opportunity_key é NULL-safe (line_value é NULL em
-- match_winner/btts/double_chance) — mesmo padrão do line_key usado no resto do Motor de Score.
--
-- `janela_deteccao` (#40) fica FORA do check_cols de propósito, e a chave não muda por causa
-- dela. Duas razões:
--   · o histórico já publicado é preservado: as linhas vivas hoje têm a coluna NULL, e um
--     check sobre ela fecharia TODAS elas e abriria uma versão nova de cada uma no primeiro
--     run depois do deploy — um pico de churn fabricado pelo deploy, bem no meio da medição
--     de churn da ADR 0009 (issue #80);
--   · a coluna não precisa do check para chegar ao histórico: o snapshot grava a linha
--     INTEIRA a cada versão nova, e `janela_usada`/`edge` mudam a cada janela antes do apito,
--     então toda oportunidade viva ganha versão com a coluna preenchida sozinha.
-- Se um dia a janela de detecção mudar SEM que nada em check_cols mude, a transição não vira
-- versão — troca aceita: isso só acontece quando a nota de uma janela antiga cruza o gate de
-- 40 por mudança de PREMISSA, não por mudança de preço.
--
-- As quatro flags de penalidade (#87) — `pen_odd_outlier`, `pen_poucas_casas`,
-- `pen_odd_longshot`, `pen_odd_juice` — ficam FORA do check_cols pelo MESMO motivo da
-- `janela_deteccao`, e por mais um que é só delas: elas são função DETERMINÍSTICA de
-- `best_odd`, `avg_odd` e `n_casas`, que já estão no check_cols (AE#109 aposentou
-- `penalidades_globais_pts` e a guarda `assert_penalidades_globais_decompostas` que a
-- decompunha — as flags viraram porta de gate, não componente de nota, e não têm mais
-- agregado próprio para comparar). Flag que muda sem que `best_odd`/`avg_odd`/`n_casas`
-- mudem não existe. Incluí-las seria redundante e cobraria o preço de sempre: um check
-- sobre coluna nova fecha TODAS as linhas vivas no primeiro run depois do deploy — pico de
-- churn fabricado, bem no meio da medição da ADR 0009.
-- Elas chegam ao histórico de graça, na primeira versão que a linha ganhar por preço, e é aí
-- que o `avisos[]` deixa de ser reconstruído do presente e passa a ser point-in-time (#257).
SELECT
    CONCAT(
      CAST(fixture_id AS STRING), '|', market, '|', outcome, '|',
      COALESCE(CAST(line_value AS STRING), 'NONE')
    ) AS opportunity_key,
    *
FROM {{ ref('fact_value_opportunities') }}

{% endsnapshot %}
