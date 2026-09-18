WITH par AS (
    SELECT
        u.classe,
        u.premissa,
        u.antes,
        u.depois
    FROM `smartbetting-dados.futebol_task0.int_futebol_premissas_ou_before` AS o
    JOIN `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou` AS h
      USING (fixture_id, outcome, line_value)
    CROSS JOIN UNNEST([
        STRUCT('A. ja era limpa — LE ODDS' AS classe, 'linha_subindo' AS premissa,
               o.linha_subindo AS antes, h.linha_subindo AS depois),
        STRUCT('A. ja era limpa — LE ODDS' AS classe, 'linha_descendo' AS premissa,
               o.linha_descendo AS antes, h.linha_descendo AS depois),
        STRUCT('B. ja era limpa — le historico (CONTROLE)' AS classe, 'historico_over' AS premissa,
               o.historico_over AS antes, h.historico_over AS depois),
        STRUCT('B. ja era limpa — le historico (CONTROLE)' AS classe, 'historico_under' AS premissa,
               o.historico_under AS antes, h.historico_under AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'ataque_combinado' AS premissa,
               o.ataque_combinado AS antes, h.ataque_combinado AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'defesas_firmes' AS premissa,
               o.defesas_firmes AS antes, h.defesas_firmes AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'defesas_vazaveis' AS premissa,
               o.defesas_vazaveis AS antes, h.defesas_vazaveis AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'clean_sheets_altos' AS premissa,
               o.clean_sheets_altos AS antes, h.clean_sheets_altos AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'ataques_fracos' AS premissa,
               o.ataques_fracos AS antes, h.ataques_fracos AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'ambos_vazam' AS premissa,
               o.ambos_vazam AS antes, h.ambos_vazam AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'xg_combinado_alto' AS premissa,
               o.xg_combinado_alto AS antes, h.xg_combinado_alto AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'xg_baixo_combinado' AS premissa,
               o.xg_baixo_combinado AS antes, h.xg_baixo_combinado AS depois),
        STRUCT('C. corrigida na Task 0 (diferenca esperada)' AS classe, 'ritmo_alto' AS premissa,
               o.ritmo_alto AS antes, h.ritmo_alto AS depois)
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