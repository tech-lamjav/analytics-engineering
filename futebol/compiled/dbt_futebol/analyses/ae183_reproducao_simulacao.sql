

WITH jogos_encerrados AS (
    SELECT fixture_id, competition, competition_id, season, round, home_team_id, away_team_id,
           kickoff_utc, goals_home, goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      AND DATE(kickoff_utc) <= DATE('2026-09-12')
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
    FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    WHERE market_id = 45
      AND janela_usada = 't24h'
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
      AND COALESCE(n_casas >= 3, FALSE)
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

,

universo AS (
    SELECT
        COUNT(*)                       AS linhas,
        COUNT(DISTINCT fixture_id)     AS jogos,
        406                             AS jogos_declarados,
        812                             AS linhas_declaradas
    FROM apostas
),

-- ROI sobre odd crua, réplica de `roi()` do script: lucro = odd-1 se ganhou, -1 senão.
-- 'lado' aqui é outcome_side (Over/Under = Mais/Menos), a aposta REAL — não o lado_medido
-- de um catálogo (esta CTE não usa o catálogo de premissas, é só liquidação bruta).
roi_geral AS (
    SELECT
        'geral' AS recorte,
        COUNT(*)                                              AS n,
        ROUND(AVG(IF(ganhou, best_odd - 1, -1)) * 100, 2)      AS roi_pct,
        -3.41                                                  AS roi_declarado
    FROM apostas
),

roi_por_lado AS (
    SELECT
        CASE outcome_side WHEN 'Over' THEN 'lado Mais' WHEN 'Under' THEN 'lado Menos' END AS recorte,
        COUNT(*)                                              AS n,
        ROUND(AVG(IF(ganhou, best_odd - 1, -1)) * 100, 2)      AS roi_pct,
        CASE outcome_side WHEN 'Over' THEN -1.37 WHEN 'Under' THEN -5.46 END AS roi_declarado
    FROM apostas
    GROUP BY outcome_side
),

roi AS (
    SELECT * FROM roi_geral
    UNION ALL
    SELECT * FROM roi_por_lado
)

SELECT
    'universo' AS bloco,
    NULL AS recorte,
    u.jogos AS n_jogos,
    u.linhas AS n,
    NULL AS roi_pct,
    NULL AS roi_declarado,
    NULL AS diferenca_pp,
    CASE
        WHEN ABS(u.jogos  - u.jogos_declarados)  > 0.10 * u.jogos_declarados
          OR ABS(u.linhas - u.linhas_declaradas) > 0.10 * u.linhas_declaradas
        THEN CONCAT('NÃO REPRODUZ (porta 1): declarado ', CAST(u.jogos_declarados AS STRING),
                     ' jogos / ', CAST(u.linhas_declaradas AS STRING),
                     ' linhas; medido ', CAST(u.jogos AS STRING), ' / ', CAST(u.linhas AS STRING))
        ELSE 'dentro da porta 1 (±10%)'
    END AS veredito
FROM universo u

UNION ALL

SELECT
    'roi' AS bloco,
    r.recorte,
    NULL AS n_jogos,
    r.n,
    r.roi_pct,
    r.roi_declarado,
    ROUND(r.roi_pct - r.roi_declarado, 2) AS diferenca_pp,
    CASE
        WHEN ABS(r.roi_pct - r.roi_declarado) > 3.0
        THEN 'NÃO REPRODUZ (porta 2, >3pp)'
        ELSE 'dentro da porta 2 (±3pp)'
    END AS veredito
FROM roi r
ORDER BY bloco, recorte