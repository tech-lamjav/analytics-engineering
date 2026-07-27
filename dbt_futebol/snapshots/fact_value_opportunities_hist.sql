{% snapshot fact_value_opportunities_hist %}
{{
    config(
      target_schema='futebol',
      unique_key='opportunity_key',
      strategy='check',
      invalidate_hard_deletes=True,
      check_cols=[
        'janela_usada', 'edge', 'score', 'faixa', 'valor_fonte',
        'best_odd', 'best_book', 'avg_odd', 'n_casas', 'prob_justa_fechamento',
        'penalidades_globais_pts', 'penalidades_especificas_pts',
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
SELECT
    CONCAT(
      CAST(fixture_id AS STRING), '|', market, '|', outcome, '|',
      COALESCE(CAST(line_value AS STRING), 'NONE')
    ) AS opportunity_key,
    *
FROM {{ ref('fact_value_opportunities') }}

{% endsnapshot %}
