
-- GUARDA DO LADO NO VALOR MEDIDO DO HANDICAP (AE#202). Toda linha de int_futebol_premissas_ah
-- publica em `insumos_medidos` SÓ premissas do lado dela (favorito OU azarão), e nunca publica
-- vazio — toda linha é um dos dois desde o B3 (#109), que acabou com o pick.
--
-- É isto que decidiu o grão do fact_insumos_medidos no Handicap (uma linha por linha de
-- handicap, #202): o mesmo lado é favorito numa linha e azarão na outra, e o que muda entre
-- elas é o conjunto de premissas medidas. O unit test do fact recebe esse conjunto pronto no
-- mock; esta guarda confere o conjunto que o modelo de verdade produz.
--
-- Os conjuntos por lado saem do catálogo futebol_insumos_premissa() pelo `aplicavel` de cada
-- premissa — nunca escritos aqui à mão. Premissa nova de favorito/azarão entra sozinha.

WITH linhas AS (
    SELECT
        fixture_id,
        outcome,
        line_value,
        is_favorito,
        is_azarao,
        insumos_medidos
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
)

SELECT
    fixture_id,
    outcome,
    line_value,
    is_favorito,
    is_azarao,
    CASE
        WHEN ARRAY_LENGTH(insumos_medidos) = 0
            THEN 'linha do Handicap sem valor medido — toda linha é favorito ou azarão'
        ELSE 'premissa medida fora do lado desta linha'
    END AS diagnostico
FROM linhas
WHERE ARRAY_LENGTH(insumos_medidos) = 0
   OR EXISTS (
        SELECT 1
        FROM UNNEST(insumos_medidos) AS im
        WHERE (is_favorito AND im.premissa NOT IN ('supremacia', 'tende_golear', 'adversario_fragil_fora', 'mando_forte', 'sem_rodizio'))
           OR (is_azarao   AND im.premissa NOT IN ('raramente_perde_por_2', 'defesa_fora_solida', 'favorito_irregular'))
   )