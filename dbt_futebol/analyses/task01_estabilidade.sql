{#
    Task [0.1] — separa as DUAS hipóteses que a reconciliação não consegue distinguir
    sozinha.  Ticket #4, spec #3.

    Quando `task01_reconciliacao.sql` acusa delta, há duas explicações possíveis:

      (1) a máquina generalizada quebrou a lógica;
      (2) as tabelas de origem não são estáveis entre rebuilds.

    Esta análise ataca a (2) diretamente, e o faz com CONTROLE — não por eliminação.

    COMO: o dataset `futebol_task0` guarda o estado das premissas congelado em
    2026-08-03, salvo durante a Task [0] para auditoria. Ele é referenciado por caminho
    literal, e não por `ref()`, porque está deliberadamente fora do DAG do dbt: é um
    snapshot morto, ninguém o reconstrói.

    A comparação só é legítima para as premissas que a Task [0] NÃO alterou. As outras
    nove mudaram de propósito (passaram a ler `int_futebol_team_form_pit` e o spine
    ancorado no kickoff), então qualquer diferença nelas é a correção, não instabilidade.
    Elas vão na saída assim mesmo, marcadas — servem de referência para o tamanho da
    correção, e a ausência delas esconderia que a comparação é parcial.

    A LEITURA: entre as quatro "já eram limpas", duas leem `fact_odds_snapshot`
    (`linha_subindo`/`linha_descendo`) e duas leem histórico de jogos
    (`historico_over`/`historico_under`). Se só as duas primeiras se mexerem, a
    instabilidade tem endereço e causa, e não é hipótese.

    → RESULTADOS DAS EXECUÇÕES: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_estabilidade
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_estabilidade.sql
#}

{%- set premissas_ou = [
    ('linha_subindo',      'A. ja era limpa — LE ODDS'),
    ('linha_descendo',     'A. ja era limpa — LE ODDS'),
    ('historico_over',     'B. ja era limpa — le historico (CONTROLE)'),
    ('historico_under',    'B. ja era limpa — le historico (CONTROLE)'),
    ('ataque_combinado',   'C. corrigida na Task 0 (diferenca esperada)'),
    ('defesas_firmes',     'C. corrigida na Task 0 (diferenca esperada)'),
    ('defesas_vazaveis',   'C. corrigida na Task 0 (diferenca esperada)'),
    ('clean_sheets_altos', 'C. corrigida na Task 0 (diferenca esperada)'),
    ('ataques_fracos',     'C. corrigida na Task 0 (diferenca esperada)'),
    ('ambos_vazam',        'C. corrigida na Task 0 (diferenca esperada)'),
    ('xg_combinado_alto',  'C. corrigida na Task 0 (diferenca esperada)'),
    ('xg_baixo_combinado', 'C. corrigida na Task 0 (diferenca esperada)'),
    ('ritmo_alto',         'C. corrigida na Task 0 (diferenca esperada)')
] -%}

WITH par AS (
    SELECT
        u.classe,
        u.premissa,
        u.antes,
        u.depois
    FROM `smartbetting-dados.futebol_task0.int_futebol_premissas_ou_before` AS o
    JOIN {{ ref('int_futebol_premissas_ou') }} AS h
      USING (fixture_id, outcome, line_value)
    CROSS JOIN UNNEST([
        {%- for col, classe in premissas_ou %}
        STRUCT('{{ classe }}' AS classe, '{{ col }}' AS premissa,
               o.{{ col }} AS antes, h.{{ col }} AS depois){{ "," if not loop.last }}
        {%- endfor %}
    ]) AS u
)

SELECT
    classe,
    premissa,
    COUNT(*)                    AS linhas_comparadas,
    COUNTIF(antes != depois)    AS flips,
    ROUND(SAFE_DIVIDE(COUNTIF(antes != depois), COUNT(*)) * 100, 3) AS pct_flips,
    -- A conclusão só é válida se as duas linhas de CONTROLE derem exatamente zero. Se
    -- o controle se mexer, a explicação não é "lê odds" — é alguma outra coisa, e esta
    -- análise não a encontrou.
    CASE
        WHEN classe LIKE 'B.%' AND COUNTIF(antes != depois) > 0
            THEN 'CONTROLE QUEBROU — a leitura abaixo nao se sustenta'
        WHEN classe LIKE 'A.%' AND COUNTIF(antes != depois) > 0
            THEN 'instabilidade confirmada'
        WHEN classe LIKE 'A.%'
            THEN 'estavel nesta janela'
        ELSE '—'
    END AS leitura
FROM par
GROUP BY classe, premissa
ORDER BY classe, flips DESC
