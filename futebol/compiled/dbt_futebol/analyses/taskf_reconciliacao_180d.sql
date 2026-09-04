

WITH lados AS (
    -- Um par (jogo, time) por lado de cada jogo. Serve de âncora e de histórico ao mesmo tempo:
    -- o que separa um do outro é o predicado de tempo lá embaixo, não a origem.
    SELECT fixture_id, competition, competition_id, season, kickoff_utc, status_short,
           home_team_id AS team_id
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc, status_short,
           away_team_id
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

ancoras AS (
    SELECT 'A_ticket'                       AS variante, l.* FROM lados l
    WHERE (l.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND l.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND l.status_short = 'FT'
    UNION ALL
    SELECT 'B_fronteira_estrita_por_data',   l.* FROM lados l
    WHERE (l.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND l.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND l.status_short = 'FT'
    UNION ALL
    SELECT 'C_fronteira_inclusiva_por_data', l.* FROM lados l
    WHERE (l.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND l.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND l.status_short = 'FT'
    UNION ALL
    SELECT 'D_ancoras_com_pen_aet',          l.* FROM lados l
    WHERE (l.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND l.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND l.status_short IN ('FT', 'AET', 'PEN')
    UNION ALL
    SELECT 'E_historico_com_pen_aet',        l.* FROM lados l
    WHERE (l.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND l.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND l.status_short = 'FT'
    UNION ALL
    SELECT 'F_como_o_pit_conta',             l.* FROM lados l
    WHERE (l.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND l.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND l.status_short = 'FT'
),

pares AS (
    SELECT
        a.variante,
        a.competition,
        a.fixture_id,
        a.team_id,

        -- COLUNA 1 DO TICKET — "jogos na própria competição". Sem limite de tempo e sem limite de
        -- temporada em todas as variantes menos a F, que é como o PIT conta.
        COUNTIF(
            l.competition_id = a.competition_id
            AND (a.variante != 'F_como_o_pit_conta' OR l.season = a.season)
        ) AS propria,

        -- COLUNA 2 DO TICKET — "jogos em tudo, 180 dias". Qualquer competição do time. A
        -- fronteira dos 180 dias é o que separa A, B e C; na F não há fronteira de dias, e sim a
        -- temporada corrente, porque é essa a contagem que a célula `escopo` usa.
        COUNTIF(
            CASE a.variante
                WHEN 'B_fronteira_estrita_por_data' THEN
                    DATE(l.kickoff_utc) >  DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY)
                WHEN 'C_fronteira_inclusiva_por_data' THEN
                    DATE(l.kickoff_utc) >= DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY)
                WHEN 'F_como_o_pit_conta' THEN
                    l.season = a.season
                ELSE
                    l.kickoff_utc >= TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY)
            END
        ) AS tudo

    FROM ancoras a
    LEFT JOIN lados l
        ON  l.team_id     = a.team_id
        AND l.kickoff_utc < a.kickoff_utc
        -- O histórico é `FT` em todas as variantes menos a E, onde AET e PEN entram — e entram
        -- SÓ aqui: a régua da âncora é outra linha, na CTE acima, e é a D que a solta.
        AND (l.status_short = 'FT'
             OR (a.variante = 'E_historico_com_pen_aet' AND l.status_short IN ('AET', 'PEN')))
    GROUP BY 1, 2, 3, 4
),

-- A variante G: a MESMA contagem da A, com a unidade trocada. Um time que joga três vezes no
-- corte entra uma vez só, com a média das suas três contagens.
por_time AS (
    SELECT p.competition, p.team_id,
           AVG(p.propria) AS propria,
           AVG(p.tudo)    AS tudo
    FROM pares p
    WHERE p.variante = 'A_ticket'
    GROUP BY 1, 2
),
jogos_ancora AS (
    SELECT competition, COUNT(DISTINCT fixture_id) AS jogos
    FROM pares
    WHERE variante = 'A_ticket'
    GROUP BY 1
),

-- O GABARITO: os 16 números publicados no ticket, digitados. Ficam aqui, e não na prosa do doc,
-- para a divergência ser alta — quem rodar a análise vê o delta, não precisa conferir de olho.
gabarito AS (
    SELECT * FROM UNNEST([
        STRUCT('copa_do_brasil'   AS competition, 10.2 AS propria_tkt, 25.5 AS tudo_tkt,
                                    19 AS p5_propria_tkt, 0 AS p5_tudo_tkt),
               ('sudamericana',     8.9, 12.5, 27,   0),
               ('copa_mundo',       2.0,  2.0, 96,  96),
               ('champions_league', 4.0,  1.0, 69, 100)
    ])
),

medido AS (
    SELECT
        p.variante,
        p.competition,
        COUNT(DISTINCT p.fixture_id)                        AS jogos,
        COUNT(*)                                            AS unidades,
        ROUND(AVG(p.propria), 1)                            AS propria,
        ROUND(AVG(p.tudo), 1)                               AS tudo,
        ROUND(100 * COUNTIF(p.propria < 5) / COUNT(*))      AS p5_propria,
        ROUND(100 * COUNTIF(p.tudo    < 5) / COUNT(*))      AS p5_tudo,
        -- As somas brutas saem junto porque são elas que tornam o resíduo legível: um delta de
        -- 0,1 numa média de 16 pares é UMA partida a mais ou a menos, e a média arredondada não
        -- deixa isso aparecer.
        SUM(p.propria)                                      AS soma_propria,
        SUM(p.tudo)                                         AS soma_tudo
    FROM pares p
    GROUP BY 1, 2

    UNION ALL

    SELECT
        'G_por_time_distinto',
        t.competition,
        j.jogos,
        COUNT(*),
        ROUND(AVG(t.propria), 1),
        ROUND(AVG(t.tudo), 1),
        ROUND(100 * COUNTIF(t.propria < 5) / COUNT(*)),
        ROUND(100 * COUNTIF(t.tudo    < 5) / COUNT(*)),
        -- Soma bruta não existe nesta unidade: somar média de time não conta partida nenhuma.
        CAST(NULL AS INT64),
        CAST(NULL AS INT64)
    FROM por_time t
    JOIN jogos_ancora j USING (competition)
    GROUP BY 1, 2, 3
)

SELECT
    m.variante,
    m.competition                          AS competicao,
    m.jogos,
    -- O denominador da variante: par (jogo, time) em A–F, time distinto na G.
    m.unidades,

    m.propria,      g.propria_tkt,    ROUND(m.propria - g.propria_tkt, 1)  AS d_propria,
    m.tudo,         g.tudo_tkt,       ROUND(m.tudo    - g.tudo_tkt,    1)  AS d_tudo,
    m.p5_propria,   g.p5_propria_tkt, m.p5_propria - g.p5_propria_tkt      AS d_p5_propria,
    m.p5_tudo,      g.p5_tudo_tkt,    m.p5_tudo    - g.p5_tudo_tkt         AS d_p5_tudo,

    m.soma_propria,
    m.soma_tudo,

    -- Quantos dos quatro campos da linha bateram. A tolerância é meia casa da última casa
    -- publicada — não é folga para acomodar divergência, é o que separa igualdade de ruído de
    -- ponto flutuante depois do ROUND.
    CAST(ABS(m.propria    - g.propria_tkt)    < 0.05 AS INT64)
  + CAST(ABS(m.tudo       - g.tudo_tkt)       < 0.05 AS INT64)
  + CAST(ABS(m.p5_propria - g.p5_propria_tkt) < 0.5  AS INT64)
  + CAST(ABS(m.p5_tudo    - g.p5_tudo_tkt)    < 0.5  AS INT64) AS campos_exatos

FROM medido m
JOIN gabarito g USING (competition)
ORDER BY m.variante, m.unidades DESC