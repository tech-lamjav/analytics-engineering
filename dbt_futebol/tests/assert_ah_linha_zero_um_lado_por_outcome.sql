{{ config(tags=['guarda']) }}
-- GUARDA DO LADO NA LINHA 0 DO HANDICAP (AE#204). Na linha 0 (side_handicap = 0) quem decide
-- o lado é a odd, com o mando desempatando (B3, #109) — e a decisão é POR PAR: se um outcome
-- é o favorito, o outcome complementar é o azarão. Até a AE#204 o `int_futebol_premissas_ah`
-- dava aos DOIS outcomes o veredito do mandante (`home_e_favorito_por_odd` sem trocar o sinal
-- no Away): com odd na linha 0, o par saía favorito/favorito ou azarão/azarão, e o outcome Away
-- somava as premissas de um lado enquanto o funil (`futebol_lado()`, por outcome) o dividia
-- pelo teto do outro.
-- Retorna (= falha) todo par (fixture, linha 0) sem exatamente um favorito e um azarão.
-- ⚠️ O que ela NÃO pega: o par inteiro invertido (Home e Away trocados juntos) sai coerente
-- e passa; e a concordância com a coluna `lado` do funil, que decide pela odd de CADA janela
-- enquanto este modelo lê só a janela corrente — divergência anterior à AE#204, fora dela.
SELECT
    fixture_id,
    COUNTIF(is_favorito) AS n_favorito,
    COUNTIF(is_azarao)   AS n_azarao,
    COUNT(*)             AS n_outcomes
FROM {{ ref('int_futebol_premissas_ah') }}
WHERE line_value = 0
GROUP BY fixture_id
HAVING COUNTIF(is_favorito) != 1
    OR COUNTIF(is_azarao)   != 1
    OR COUNT(*)             != 2
