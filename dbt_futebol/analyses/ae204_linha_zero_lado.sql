{#
    A MEDIÇÃO DO LADO NA LINHA 0 DO HANDICAP (AE#204) — feita ANTES da correção, 25/09/2026.

    O defeito: o `int_futebol_premissas_ah` dava aos dois outcomes da linha 0 o veredito de
    favoritismo do MANDANTE. Com odd na linha 0, o outcome Away saía sempre com o lado errado
    (o Home saía certo; sem odd, o mando decidia e os dois saíam certos). O funil acertava o
    lado — `futebol_lado()` recebe o favoritismo por outcome —, então a linha Away/0 somava as
    premissas de um lado e era dividida pelo teto do outro.

    As duas perguntas da issue, nesta ordem:

      (a) quantas linhas PUBLICADAS foram afetadas desde a B3 (#109, 01/09)?
      (b) a correção muda o teto ou a faixa dessas linhas?

    Resposta de 25/09: (a) ZERO. A linha 0 nunca passa no gate — a `porta_linha_meia` a
    reprova sempre (linha 0 tem push) —, então board, histórico PIT e `passou_no_gate` têm
    zero linhas de Handicap com line_value = 0, em qualquer data. (b) O teto não muda (o
    `lado` do funil já estava certo); o que muda é o NUMERADOR, e a faixa muda em 744 das 1.273
    linhas Away/0 do funil. Nenhuma delas é publicada. Números completos na AE#204.

    ────────────────────────────────────────────────────────────────────────────────
    O PTS CERTO sem rodar o modelo corrigido: `pts_premissas` não lê `line_value` (só o
    `handicap_alto` lê, e ele é penalidade, fora da soma), então as premissas do Away no lado
    FAVORITO são as da linha Away +0,5 (side_handicap −0,5) e as do lado AZARÃO são as da linha
    Away −0,5. As duas são canônicas: existem para todo fixture. Por isso esta leitura vale
    antes E depois do deploy da correção — ela nunca lê a linha 0 do modelo.

    ⚠️ Linhas do funil congeladas antes da correção GUARDAM o erro para sempre (append-only,
    ADR 0011): é registro do que o Motor disse. Quem ler `nota_contexto`/`score_normalizado`
    do Handicap Away/0 com kickoff anterior ao deploy da AE#204 precisa recompor como aqui.

    ⚠️ Os cortes da faixa (>=60 Alta, >=30 Média) são CÓPIA dos de fact_value_opportunities.sql
    — a faixa não tem macro. Se lá mudar, muda aqui.

    São dois SELECTs; o `bq query` imprime um por um.
#}

-- (a) linhas publicadas: board, histórico PIT e gate do funil.
SELECT 'board' AS onde, COUNT(*) AS linhas_linha_zero
FROM {{ ref('fact_value_opportunities') }}
WHERE market = 'asian_handicap' AND line_value = 0
UNION ALL
SELECT 'hist', COUNT(*)
FROM {{ ref('fact_value_opportunities_hist') }}
WHERE market = 'asian_handicap' AND line_value = 0
UNION ALL
SELECT 'funil_passou_no_gate', COUNTIF(passou_no_gate)
FROM {{ ref('fact_value_funnel') }}
WHERE market = 'asian_handicap' AND line_value = 0;

-- (b) o erro no funil: nota gravada × nota recomposta com as premissas do lado certo.
WITH gravado AS (
    SELECT fixture_id, janela, lado, pts_premissas, penalidades_especificas_pts, score_normalizado
    FROM {{ ref('fact_value_funnel') }}
    WHERE market = 'asian_handicap' AND line_value = 0 AND outcome = 'Away'
      AND gravado_em >= '2026-09-01'
),
premissas_do_lado AS (
    SELECT fixture_id, IF(line_value > 0, 'Favorito', 'Azarao') AS lado, pts_premissas
    FROM {{ ref('int_futebol_premissas_ah') }}
    WHERE outcome = 'Away' AND line_value IN (0.5, -0.5)
),
recomposto AS (
    SELECT
        g.*,
        p.pts_premissas AS pts_certo,
        CASE
            WHEN t.teto IS NULL OR t.teto <= 0 THEN 0
            ELSE LEAST(100, CAST(ROUND(
                GREATEST(p.pts_premissas - g.penalidades_especificas_pts, 0) / t.teto * 100) AS INT64))
        END AS score_certo
    FROM gravado g
    LEFT JOIN premissas_do_lado p USING (fixture_id, lado)
    LEFT JOIN {{ ref('futebol_teto_nota_contexto') }} t
        ON t.market = 'asian_handicap' AND t.lado = g.lado
),
faixas AS (
    SELECT
        *,
        CASE WHEN score_normalizado >= 60 THEN 'Alta' WHEN score_normalizado >= 30 THEN 'Média' ELSE 'Baixa' END AS faixa_gravada,
        CASE WHEN score_certo       >= 60 THEN 'Alta' WHEN score_certo       >= 30 THEN 'Média' ELSE 'Baixa' END AS faixa_certa
    FROM recomposto
)
SELECT
    lado,
    COUNT(*)                                AS linhas,
    COUNT(DISTINCT fixture_id)              AS fixtures,
    COUNTIF(pts_certo IS NULL)              AS sem_pts_certo,
    COUNTIF(pts_premissas != pts_certo)     AS pts_muda,
    ROUND(AVG(score_normalizado), 1)        AS score_medio_gravado,
    ROUND(AVG(score_certo), 1)              AS score_medio_certo,
    COUNTIF(faixa_gravada != faixa_certa)   AS faixa_muda
FROM faixas
GROUP BY lado
ORDER BY lado
