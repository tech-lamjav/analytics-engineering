

CREATE TEMP TABLE apostas_t AS (
    WITH jogos_encerrados AS (
    SELECT fixture_id, competition, competition_id, season, round, home_team_id, away_team_id,
           kickoff_utc, goals_home, goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
),

-- Fase de pontos corridos de cada (competition_id, season) — mesma CTE de
-- ae161_base_escanteios/AE#162, reaproveitada aqui para reta_final. `total_rodadas` é
-- informação de CALENDÁRIO (existe antes do fim da temporada), não medição.
total_rodadas AS (
    SELECT competition_id, season,
           MAX(CAST(REGEXP_EXTRACT(round, r'(\d+)$') AS INT64)) AS total_rodadas
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE round LIKE 'Regular Season%'
    GROUP BY 1, 2
),

-- mata_mata e reta_final do JOGO (não do time/lado — Total é um mercado do jogo inteiro,
-- diferente do Away-only "Decisão" do Handicap/#162).
--
-- mata_mata: regex de INCLUSÃO, não de exclusão. AE#162 (Handicap) usa
-- `round NOT LIKE 'Regular Season%'/'Group Stage%'/'League Stage%'` — mais largo, varre
-- pra dentro "1st Round" de copa, rodadas de qualificação, "Relegation Round" etc. O
-- script original do Total (scripts/futebol-escanteios-total.mjs) usa
-- `/final|semi|quarter|round of|play-?off|3rd place/i` — mais estreito, de propósito
-- (é o texto que o documento declara: "rodada com final, semi, quarta, oitava ou
-- playoff"). Reproduzido aqui LITERALMENTE porque #183 mede a reprodução deste script
-- específico, não redescobre uma classificação nova — e porque o achado do #183 sobre
-- must_win/reta_final só vale a pena comparar com o documento se usar a mesma régua dele.
-- Note `(?i)` via LOWER(): pega "Semi-finals" e "Semi-Finals" (as duas grafias existem em
-- produção) sem depender de qual delas a fonte usar num dado torneio.
--
-- reta_final: rodada do PRÓPRIO jogo (não do visitante, ao contrário do #162) >=
-- (última rodada da fase de pontos corridos − 6), só quando essa fase tem >= 20 rodadas.
-- Diferença deliberada do script original: lá, "última rodada" é o MAX observado por
-- `competition` (nome, sem season) sobre a janela de leitura inteira — pode misturar
-- temporadas de tamanho diferente da mesma competição. Aqui uso `total_rodadas`
-- particionado por (competition_id, season), que já existe e evita essa mistura — mais
-- correto, na prática quase sempre idêntico (a janela de odds cobre uma temporada por
-- competição). Registrado como divergência deliberada, não descoberta tarde.
jogo_classificado AS (
    SELECT
        j.fixture_id,
        REGEXP_CONTAINS(LOWER(j.round), r'final|semi|quarter|round of|play-?off|3rd place') AS mata_mata,
        (tr.total_rodadas >= 20
         AND CAST(REGEXP_EXTRACT(j.round, r'(\d+)$') AS INT64) >= tr.total_rodadas - 6
         AND j.round LIKE 'Regular Season%')                                                AS reta_final
    FROM jogos_encerrados j
    LEFT JOIN total_rodadas tr
      ON  tr.competition_id = j.competition_id
      AND tr.season         = j.season
),

-- Traço do campeonato, ponto-no-tempo: média de escanteios TOTAIS (dos dois lados) dos
-- jogos JÁ OCORRIDOS naquele campeonato antes deste, mínimo 30. Por `competition_id`,
-- SEM particionar por season — mesma leitura do script original (`porComp` chaveia só por
-- `f.home.competition`, pooling entre temporadas): "traço do campeonato" é uma
-- característica de estilo que atravessa temporada, não reseta a cada uma. Um corte
-- artificial por season faria toda liga recomeçar do zero (sem as 30 partidas mínimas)
-- toda virada de temporada, o que o documento nunca pede.
resultado_por_jogo AS (
    SELECT
        j.fixture_id,
        j.competition_id,
        j.kickoff_utc,
        r.corners_home + r.corners_away AS total_corners
    FROM jogos_encerrados j
    JOIN (
        SELECT fixture_id,
               MAX(IF(team_side = 'home', corner_kicks, NULL)) AS corners_home,
               MAX(IF(team_side = 'away', corner_kicks, NULL)) AS corners_away
        FROM `smartbetting-dados`.`futebol`.`fact_fixture_stats`
        GROUP BY fixture_id
    ) r ON r.fixture_id = j.fixture_id
    WHERE r.corners_home IS NOT NULL AND r.corners_away IS NOT NULL
),

campeonato_pit AS (
    SELECT
        fixture_id,
        AVG(total_corners) OVER (
            PARTITION BY competition_id ORDER BY kickoff_utc
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS campeonato_media_pit,
        COUNT(*) OVER (
            PARTITION BY competition_id ORDER BY kickoff_utc
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS campeonato_jogos_anteriores
    FROM resultado_por_jogo
),

-- Resultado REAL do jogo (não PIT), 1 linha por fixture — usado pra liquidar. Refeito
-- aqui (não reaproveitado de resultado_por_jogo) só porque aquela CTE já perdeu o
-- team_side; mais simples repetir o pivot que desmontar o total de novo.
resultado_escanteios AS (
    SELECT
        fixture_id,
        MAX(IF(team_side = 'home', corner_kicks, NULL)) AS corners_home,
        MAX(IF(team_side = 'away', corner_kicks, NULL)) AS corners_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixture_stats`
    GROUP BY fixture_id
),

odds_45 AS (
    SELECT *
    FROM (SELECT * EXCEPT (janela_prioridade, janela_e_corrente)
    FROM (SELECT
        d.* EXCEPT (_janela_prioridade, _line_key),
        d._janela_prioridade AS janela_prioridade,
        d._janela_prioridade = MAX(d._janela_prioridade) OVER (
            PARTITION BY d.fixture_id, d.market_id, d._line_key
        ) AS janela_e_corrente
    FROM (
        SELECT
            *,
            CASE janela_usada
        WHEN 't15m'  THEN 4   -- fechamento
        WHEN 't1h'   THEN 3
        WHEN 't24h'  THEN 2
        WHEN 'daily' THEN 1   -- varredura diária, até 7 dias do apito
        ELSE 0
    END AS _janela_prioridade,
            COALESCE(CAST(line_value AS STRING), 'NONE')    AS _line_key
        FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    ) d)
    WHERE janela_e_corrente)
    WHERE market_id = 45
),

-- Gates de preço APLICADOS ANTES da escolha da linha principal (ver comentário do topo
-- do macro pela ordem e a razão).
odds_45_gated AS (
    SELECT *
    FROM odds_45
    WHERE best_odd              IS NOT NULL
      -- Divergência RECONHECIDA da reprodução literal, não descoberta tarde (achado do
      -- code-review desta issue): o script original nunca lê de-vig, só `best_odd` cru — este
      -- filtro não existe lá. Aplicado aqui mesmo assim, nos dois modos, pela mesma razão que
      -- o #161 já declarou pro Handicap (ae161_base_escanteios.sql): reusar UMA base pros dois
      -- modos, em vez de bifurcar o macro, e aceitar a diferença de universo pequena que isso
      -- causa (no #161 foi 4 jogos/10 linhas de 514/2238) em troca de não ter duas cópias da
      -- mesma lógica de gate pra divergir entre si depois.
      AND prob_justa_fechamento IS NOT NULL   -- só linhas que o de-vig realmente emitiu (AE#158)
      AND (MOD(CAST(ROUND(ABS(line_value) * 4) AS INT64), 4) = 2)
      AND COALESCE(n_casas >= 4, FALSE)
      AND COALESCE(NOT pen_odd_outlier, FALSE)
      AND COALESCE(best_odd >= 1.5
               AND best_odd <= 4.0, FALSE)
),

-- A LINHA PRINCIPAL: por (fixture_id, outcome_side), a de odd mais perto de 2,00 entre as
-- que sobreviveram ao gate acima. Empate (mesma distância, acontece com odds simétricas
-- tipo 1,90/2,10) resolvido por line_value ASC — determinístico, não afeta o n agregado.
linha_principal AS (
    SELECT *
    FROM odds_45_gated
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY fixture_id, outcome_side
        ORDER BY ABS(best_odd - 2.00) ASC, line_value ASC
    ) = 1
),

pit_home AS (SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_team_corner_form_pit`),
pit_away AS (SELECT * FROM `smartbetting-dados`.`futebol`.`int_futebol_team_corner_form_pit`),

apostas AS (
    SELECT
        o.fixture_id,
        o.outcome_side,                     -- 'Over' (Mais) / 'Under' (Menos)
        o.line_value,
        o.best_odd,
        o.n_casas,
        o.prob_justa_fechamento,
        IF(o.valor_fonte = 'pinnacle', 'pinnacle', 'consenso') AS benchmark,
        j.competition,
        j.competition_id,
        j.season,
        j.kickoff_utc,
        LEAST(COALESCE(ph.played_total_disponivel, 0), COALESCE(pa.played_total_disponivel, 0)) AS min_jogos,

        jc.mata_mata,
        jc.reta_final,

        -- Liquidação: TOTAL real contra a linha. Over ganha se total > linha, Under se
        -- total < linha (linha meia: nunca empata).
        IF(o.outcome_side = 'Over',
           r.corners_home + r.corners_away > o.line_value,
           r.corners_home + r.corners_away < o.line_value)                                AS ganhou,

        -- Insumos PIT (AE#159/#181), point-in-time, expostos pra ae183_premissas_escanteios_total() montar em cima.
        ph.possession_avg10        AS h_po,  pa.possession_avg10        AS a_po,
        ph.xg_avg10                AS h_xg,  pa.xg_avg10                AS a_xg,
        ph.corners_for_avg10       AS h_ck,  pa.corners_for_avg10       AS a_ck,
        ph.corners_against_avg10   AS h_sof, pa.corners_against_avg10   AS a_sof,
        ph.shots_insidebox_avg10   AS h_ib,  pa.shots_insidebox_avg10   AS a_ib,
        ph.total_shots_avg10       AS h_ts,  pa.total_shots_avg10       AS a_ts,
        ph.shots_outsidebox_avg10  AS h_ob,  pa.shots_outsidebox_avg10  AS a_ob,
        ph.blocked_shots_avg10     AS h_bl,  pa.blocked_shots_avg10     AS a_bl,
        ph.goalkeeper_saves_avg10  AS h_gs,  pa.goalkeeper_saves_avg10  AS a_gs,
        ph.fouls_avg10             AS h_fl,  pa.fouls_avg10             AS a_fl,
        ph.corners_for_avg_mando5     AS h_ck_lado,   -- pressao_do_mandante
        pa.corners_against_avg_mando5 AS a_sof_lado,  -- visitante_que_cede

        cp.campeonato_media_pit    AS campeonato_de_escanteio,

        -- Escanteio previsto do jogo, fórmula do documento (idêntica à do Handicap/#161):
        -- (a_favor_mandante + sofridos_visitante + a_favor_visitante + sofridos_mandante) / 2
        SAFE_DIVIDE(ph.corners_for_avg10 + pa.corners_against_avg10
                  + pa.corners_for_avg10 + ph.corners_against_avg10, 2)                     AS escanteio_previsto

    FROM linha_principal o
    JOIN jogos_encerrados j
      ON j.fixture_id = o.fixture_id
    JOIN jogo_classificado jc
      ON jc.fixture_id = o.fixture_id
    JOIN resultado_escanteios r
      ON r.fixture_id = o.fixture_id
    LEFT JOIN pit_home ph
      ON ph.fixture_id = o.fixture_id AND ph.team_id = j.home_team_id
    LEFT JOIN pit_away pa
      ON pa.fixture_id = o.fixture_id AND pa.team_id = j.away_team_id
    LEFT JOIN campeonato_pit cp
      ON  cp.fixture_id = o.fixture_id
      AND cp.campeonato_jogos_anteriores >= 30       -- piso do documento: mínimo 30 jogos já ocorridos
    WHERE r.corners_home IS NOT NULL AND r.corners_away IS NOT NULL  -- resultado real existe p/ liquidar
      -- AE#172 (achado do code-review desta issue #183): o comentário do topo do macro já
      -- dizia "min_jogos>=10 SEMPRE aplicado" ao lado dos outros filtros sempre-ligados, mas
      -- só estava implementado como coluna exposta, filtrada DEPOIS, dentro do `acesa` de
      -- cada premissa — nunca aqui. Isso deixava `apostas` (e por extensão
      -- ae183_reproducao_simulacao.sql, que nunca passa por ae183_premissas_escanteios_total_sql)
      -- com jogos de menos de 10 partidas de histórico dentro do universo, contra o que a
      -- seção 2 do documento declara ("jogo com menos de 10 partidas anteriores no histórico
      -- fica de fora") e contra o próprio script original (todo insumo obrigatório não-nulo
      -- já exige os dois times com >=10 jogos). Piso movido pra cá — grão do JOGO, não só da
      -- premissa — mesmo efeito de antes pra ae183_teste2.sql (min_jogos>=10 dentro de
      -- `acesa` continua lá, agora redundante-e-inofensivo, não a única linha de defesa).
      AND LEAST(COALESCE(ph.played_total_disponivel, 0), COALESCE(pa.played_total_disponivel, 0)) >= 10
)


    SELECT * FROM apostas
);

-- ÚNICA MUDANÇA EM RELAÇÃO AO #185: PARTITION BY competition_id, não global.
CREATE TEMP TABLE metades_t AS (
    SELECT fixture_id,
           NTILE(2) OVER (PARTITION BY competition_id ORDER BY kickoff_utc, fixture_id) AS metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc, competition_id FROM apostas_t)
);

-- Sub-partição DENTRO de cada metade (nunca cruza a fronteira metade 1/2) — usada só pra
-- checar estabilidade na metade de AJUSTE, nunca toca a metade de medição. Mesma técnica
-- do #185, sem estratificação adicional aqui (a fronteira metade 1/2 já é estratificada;
-- dentro dela, a ordem temporal simples é suficiente pro teste de estabilidade).
CREATE TEMP TABLE sub_metades_t AS (
    SELECT j.fixture_id, m.metade,
           NTILE(2) OVER (PARTITION BY m.metade ORDER BY j.kickoff_utc, j.fixture_id) AS sub_metade
    FROM (SELECT DISTINCT fixture_id, kickoff_utc FROM apostas_t) j
    JOIN metades_t m USING (fixture_id)
);

CREATE TEMP TABLE premissas_t AS (
    
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'ataque_de_escanteio'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_ck + a_ck) >= 10.4, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'ataque_de_escanteio'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_ck + a_ck) <= 9.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'defesa_que_cede'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_sof + a_sof) >= 10.3, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'defesa_que_cede'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_sof + a_sof) <= 8.9, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'volume_de_finalizacao'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_ts + a_ts) >= 27.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'volume_de_finalizacao'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_ts + a_ts) <= 23.9, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'finalizacao_de_fora'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_ob + a_ob) >= 10.4, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'finalizacao_de_fora'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_ob + a_ob) <= 8.6, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'finalizacao_na_area'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_ib + a_ib) >= 16.9, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'finalizacao_na_area'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_ib + a_ib) <= 14.5, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'bloqueios'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_bl + a_bl) >= 7.3, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'bloqueios'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_bl + a_bl) <= 6.2, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'defesas_do_goleiro'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_gs + a_gs) >= 6.3, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'defesas_do_goleiro'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_gs + a_gs) <= 5.46, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'jogo_faltoso'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_fl + a_fl) >= 26.4, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'jogo_faltoso'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_fl + a_fl) <= 23.4, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'chute_de_longe'  AS premissa,
        'Mais' AS lado,
        (COALESCE((SAFE_DIVIDE(h_ob, h_ts) + SAFE_DIVIDE(a_ob, a_ts)) >= 0.81, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'chute_de_longe'  AS premissa,
        'Menos' AS lado,
        (COALESCE((SAFE_DIVIDE(h_ob, h_ts) + SAFE_DIVIDE(a_ob, a_ts)) <= 0.69, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'desequilibrio_de_posse'  AS premissa,
        'Mais' AS lado,
        (COALESCE(ABS(h_po - a_po) >= 8.3, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'desequilibrio_de_posse'  AS premissa,
        'Menos' AS lado,
        (COALESCE(ABS(h_po - a_po) <= 3.7, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'pressao_do_mandante'  AS premissa,
        'Mais' AS lado,
        (COALESCE(h_ck_lado >= 6.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'pressao_do_mandante'  AS premissa,
        'Menos' AS lado,
        (COALESCE(h_ck_lado <= 4.8, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'visitante_que_cede'  AS premissa,
        'Mais' AS lado,
        (COALESCE(a_sof_lado >= 6.0, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'visitante_que_cede'  AS premissa,
        'Menos' AS lado,
        (COALESCE(a_sof_lado <= 4.6, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'campeonato_de_escanteio'  AS premissa,
        'Mais' AS lado,
        (COALESCE(campeonato_de_escanteio >= 10.06, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'campeonato_de_escanteio'  AS premissa,
        'Menos' AS lado,
        (COALESCE(campeonato_de_escanteio <= 9.51, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'escanteio_previsto'  AS premissa,
        'Mais' AS lado,
        (COALESCE(escanteio_previsto >= 10.05, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'escanteio_previsto'  AS premissa,
        'Menos' AS lado,
        (COALESCE(escanteio_previsto <= 9.3, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'previsao_x_linha'  AS premissa,
        'Mais' AS lado,
        (COALESCE((escanteio_previsto - line_value) >= 0.5, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'previsao_x_linha'  AS premissa,
        'Menos' AS lado,
        (COALESCE((escanteio_previsto - line_value) <= -0.5, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'chance_de_gol'  AS premissa,
        'Mais' AS lado,
        (COALESCE((h_xg + a_xg) >= 2.87, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'chance_de_gol'  AS premissa,
        'Menos' AS lado,
        (COALESCE((h_xg + a_xg) <= 2.38, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'mata_mata'  AS premissa,
        'Mais' AS lado,
        -- booleana (mata_mata/reta_final): mesmo flag acende nos dois lados do catálogo
        (COALESCE(mata_mata, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'mata_mata'  AS premissa,
        'Menos' AS lado,
        -- booleana (mata_mata/reta_final): mesmo flag acende nos dois lados do catálogo
        (COALESCE(mata_mata, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'reta_final'  AS premissa,
        'Mais' AS lado,
        -- booleana (mata_mata/reta_final): mesmo flag acende nos dois lados do catálogo
        (COALESCE(reta_final, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Over'
    UNION ALL
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        'reta_final'  AS premissa,
        'Menos' AS lado,
        -- booleana (mata_mata/reta_final): mesmo flag acende nos dois lados do catálogo
        (COALESCE(reta_final, FALSE) AND min_jogos >= 10) AS acesa
    FROM apostas_t
    WHERE outcome_side = 'Under'

);

-- Catálogo candidato — idêntico ao #185.
CREATE TEMP TABLE candidato_t AS (
    SELECT * FROM UNNEST([
        STRUCT('Mais' AS lado, 'ataque_de_escanteio'     AS premissa),
        STRUCT('Mais' AS lado, 'finalizacao_na_area'     AS premissa),
        STRUCT('Mais' AS lado, 'volume_de_finalizacao'   AS premissa),
        STRUCT('Mais' AS lado, 'chance_de_gol'           AS premissa),
        STRUCT('Mais' AS lado, 'desequilibrio_de_posse'  AS premissa),
        STRUCT('Mais' AS lado, 'mata_mata'               AS premissa),
        STRUCT('Mais' AS lado, 'finalizacao_de_fora'     AS premissa),
        STRUCT('Mais' AS lado, 'pressao_do_mandante'     AS premissa),
        STRUCT('Mais' AS lado, 'jogo_faltoso'            AS premissa),
        STRUCT('Mais' AS lado, 'bloqueios'                AS premissa),
        STRUCT('Menos' AS lado, 'volume_de_finalizacao'   AS premissa),
        STRUCT('Menos' AS lado, 'bloqueios'                AS premissa),
        STRUCT('Menos' AS lado, 'finalizacao_de_fora'      AS premissa),
        STRUCT('Menos' AS lado, 'chute_de_longe'           AS premissa),
        STRUCT('Menos' AS lado, 'jogo_faltoso'             AS premissa),
        STRUCT('Menos' AS lado, 'finalizacao_na_area'      AS premissa),
        STRUCT('Menos' AS lado, 'escanteio_previsto'       AS premissa),
        STRUCT('Menos' AS lado, 'ataque_de_escanteio'      AS premissa),
        STRUCT('Menos' AS lado, 'desequilibrio_de_posse'   AS premissa),
        STRUCT('Menos' AS lado, 'campeonato_de_escanteio'  AS premissa),
        STRUCT('Menos' AS lado, 'previsao_x_linha'         AS premissa),
        STRUCT('Menos' AS lado, 'chance_de_gol'            AS premissa),
        STRUCT('Menos' AS lado, 'pressao_do_mandante'      AS premissa)
    ])
);

CREATE TEMP TABLE linhas_t AS (
    SELECT
        pc.fixture_id, pc.outcome_side, pc.lado, pc.premissa, pc.acesa,
        pc.ganhou, pc.prob_justa_fechamento, pc.benchmark,
        a.kickoff_utc, a.best_odd,
        m.metade, sm.sub_metade
    FROM premissas_t pc
    JOIN candidato_t c    ON c.lado = pc.lado AND c.premissa = pc.premissa
    JOIN apostas_t a      ON a.fixture_id = pc.fixture_id AND a.outcome_side = pc.outcome_side
    JOIN metades_t m      ON m.fixture_id = a.fixture_id
    JOIN sub_metades_t sm ON sm.fixture_id = a.fixture_id
);

CREATE TEMP TABLE ganho_full_t AS (
    SELECT
        'A' AS direcao, lado, premissa,
        COUNTIF(acesa) AS n,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp
    FROM linhas_t
    WHERE metade = 1 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa
    HAVING COUNTIF(acesa) > 0

    UNION ALL

    SELECT
        'B' AS direcao, lado, premissa,
        COUNTIF(acesa) AS n,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp
    FROM linhas_t
    WHERE metade = 2 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa
    HAVING COUNTIF(acesa) > 0
);

CREATE TEMP TABLE ganho_sub_t AS (
    SELECT
        'A' AS direcao, lado, premissa, sub_metade,
        COUNTIF(acesa) AS n_sub,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp_sub
    FROM linhas_t
    WHERE metade = 1 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa, sub_metade
    HAVING COUNTIF(acesa) > 0

    UNION ALL

    SELECT
        'B' AS direcao, lado, premissa, sub_metade,
        COUNTIF(acesa) AS n_sub,
        (AVG(IF(acesa, CAST(ganhou AS INT64), NULL))
       - AVG(IF(acesa, prob_justa_fechamento, NULL))) * 100 AS diferenca_pp_sub
    FROM linhas_t
    WHERE metade = 2 AND benchmark = 'pinnacle'
    GROUP BY lado, premissa, sub_metade
    HAVING COUNTIF(acesa) > 0
);

CREATE TEMP TABLE pesos_t AS (
    WITH estabilidade AS (
        SELECT
            direcao, lado, premissa,
            MAX(IF(sub_metade = 1, diferenca_pp_sub, NULL)) AS diff_sub1,
            MAX(IF(sub_metade = 2, diferenca_pp_sub, NULL)) AS diff_sub2
        FROM ganho_sub_t
        GROUP BY direcao, lado, premissa
    ),
    niveis_tamanho AS (
        SELECT direcao, lado, premissa,
            NTILE(3) OVER (
                PARTITION BY direcao, lado
                ORDER BY diferenca_pp DESC, n DESC, premissa ASC
            ) AS nivel_tamanho
        FROM ganho_full_t
        WHERE diferenca_pp > 0
    )
    SELECT
        gf.direcao, gf.lado, gf.premissa, gf.n,
        ROUND(gf.diferenca_pp, 2) AS diferenca_pp,
        COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AS estavel,
        nt.nivel_tamanho,
        CASE
            WHEN gf.diferenca_pp <= 0 THEN 0
            WHEN     COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 1 THEN 9
            WHEN     COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 2 THEN 6
            WHEN     COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 3 THEN 3
            WHEN NOT COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 1 THEN 3
            WHEN NOT COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 2 THEN 2
            WHEN NOT COALESCE(e.diff_sub1 > 0 AND e.diff_sub2 > 0, FALSE) AND nt.nivel_tamanho = 3 THEN 1
            ELSE 0
        END AS peso
    FROM ganho_full_t gf
    LEFT JOIN estabilidade e    USING (direcao, lado, premissa)
    LEFT JOIN niveis_tamanho nt USING (direcao, lado, premissa)
);

CREATE TEMP TABLE teto_t AS (
    SELECT direcao, lado, SUM(peso) AS teto
    FROM pesos_t
    GROUP BY direcao, lado
);

CREATE TEMP TABLE score_t AS (
    SELECT
        'A' AS direcao, l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd,
        ANY_VALUE(l.ganhou) AS ganhou,
        SUM(IF(l.acesa, COALESCE(w.peso, 0), 0)) AS soma_pesos
    FROM linhas_t l
    LEFT JOIN pesos_t w
      ON w.direcao = 'A' AND w.lado = l.lado AND w.premissa = l.premissa
    WHERE l.metade = 2
    GROUP BY l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd

    UNION ALL

    SELECT
        'B' AS direcao, l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd,
        ANY_VALUE(l.ganhou) AS ganhou,
        SUM(IF(l.acesa, COALESCE(w.peso, 0), 0)) AS soma_pesos
    FROM linhas_t l
    LEFT JOIN pesos_t w
      ON w.direcao = 'B' AND w.lado = l.lado AND w.premissa = l.premissa
    WHERE l.metade = 1
    GROUP BY l.fixture_id, l.outcome_side, l.lado, l.kickoff_utc, l.best_odd
);

CREATE TEMP TABLE faixado_t AS (
    SELECT
        s.*,
        t.teto,
        SAFE_DIVIDE(100.0 * s.soma_pesos, t.teto) AS score_0_100,
        CASE
            WHEN t.teto IS NULL OR t.teto = 0 THEN 'sem_teto'
            WHEN SAFE_DIVIDE(100.0 * s.soma_pesos, t.teto) >= 60 THEN 'Alta'
            WHEN SAFE_DIVIDE(100.0 * s.soma_pesos, t.teto) >= 30 THEN 'Média'
            ELSE 'Baixa'
        END AS faixa,
        IF(s.ganhou, s.best_odd - 1, -1) AS lucro
    FROM score_t s
    LEFT JOIN teto_t t ON t.direcao = s.direcao AND t.lado = s.lado
);

WITH checagem_unicidade AS (
    SELECT COUNT(*) AS linhas,
           COUNT(DISTINCT CONCAT(CAST(fixture_id AS STRING), '|', outcome_side)) AS chaves_distintas
    FROM apostas_t
),

resultado AS (
    SELECT
        direcao, lado, faixa,
        COUNT(*)                   AS n,
        ROUND(AVG(lucro) * 100, 2) AS roi_pct
    FROM faixado_t
    GROUP BY 1, 2, 3
)

SELECT
    'faixa' AS bloco, direcao, lado, faixa, n, roi_pct,
    CAST(NULL AS FLOAT64) AS linhas_check, CAST(NULL AS FLOAT64) AS chaves_check,
    CAST(NULL AS BOOL) AS estavel, CAST(NULL AS INT64) AS nivel_tamanho
FROM resultado

UNION ALL

SELECT
    'checagem_unica' AS bloco, CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
    CAST(NULL AS INT64), CAST(NULL AS FLOAT64),
    CAST(linhas AS FLOAT64), CAST(chaves_distintas AS FLOAT64),
    CAST(NULL AS BOOL), CAST(NULL AS INT64)
FROM checagem_unicidade

UNION ALL

SELECT
    'pesos' AS bloco, direcao, lado, premissa, n, diferenca_pp,
    CAST(peso AS FLOAT64) AS linhas_check, CAST(NULL AS FLOAT64) AS chaves_check,
    estavel, nivel_tamanho
FROM pesos_t

UNION ALL

SELECT
    'teto' AS bloco, t.direcao, t.lado, CAST(NULL AS STRING),
    CAST(NULL AS INT64), CAST(NULL AS FLOAT64),
    CAST(t.teto AS FLOAT64) AS linhas_check, CAST(NULL AS FLOAT64) AS chaves_check,
    CAST(NULL AS BOOL), CAST(NULL AS INT64)
FROM teto_t AS t

ORDER BY bloco, direcao, lado, faixa