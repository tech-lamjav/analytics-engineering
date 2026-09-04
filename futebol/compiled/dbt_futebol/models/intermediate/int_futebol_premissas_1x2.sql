

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
),

-- 3 outcomes por fixture; resolve S (apostado) e O (adversário) por lado.
outcomes AS (
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Home' AS outcome, home_team_id AS s_team_id, away_team_id AS o_team_id, TRUE AS s_is_home
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Away', away_team_id, home_team_id, FALSE
    FROM fixtures
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc,
           'Draw', CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS BOOL)
    FROM fixtures
),

-- Correção da Task 0 (look-ahead): forma E tabela POINT-IN-TIME por (fixture, time), só com
-- jogos anteriores ao kickoff. Uma única fonte no lugar das duas contaminadas —
-- fact_team_season_stats (1 snapshot por season: em 24/25 é a temporada FECHADA aplicada à
-- rodada 1) e standings_latest (MAX(snapshot_date) sem âncora no jogo = tabela final).
pit AS (
    SELECT
        fixture_id, team_id,
        goals_for_avg_home, goals_for_avg_away,
        goals_against_avg_home, goals_against_avg_away,
        wins_home, draws_home, played_home,
        wins_away, draws_away, played_away,
        rank, ppg, n_wins_last5, n_games_last5
    FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`
),

-- Spine (fixture-alvo, time) p/ ancorar o xG ao kickoff do jogo (point-in-time).
fixture_team_spine AS (
    SELECT fixture_id, season, competition_id, kickoff_utc, home_team_id AS team_id FROM fixtures
    UNION ALL
    SELECT fixture_id, season, competition_id, kickoff_utc, away_team_id FROM fixtures
),
-- xG médio do time ATÉ o jogo: mesma season/competição e jogos ANTERIORES ao kickoff (date_utc <
-- DATE(kickoff)) — time-bounded igual ao h2h/last5, sem look-ahead em fixtures já jogadas. P/ jogos
-- FUTUROS == média da season (todos os jogos com stats são anteriores). Brasileirão preenchido;
-- Copa ~vazio -> NULL -> premissa de xG não dispara.
-- ⚠️ NÃO USE `AVG()` AQUI — É `SAFE_DIVIDE(SUM(...), COUNT(...))`, E EM NUMERIC (#78).
--
-- `AVG()` no BigQuery NÃO é bit-reproduzível entre execuções. A agregação é paralelizada e as
-- médias PARCIAIS de cada shard são fundidas em ponto flutuante; a ordem da fusão muda de
-- execução para execução e leva o último bit junto. Medido com o insumo CONGELADO, sem join
-- nenhum, 9 linhas: `AVG` devolveu 1.4766666666666667 em três execuções e 1.4766666666666665 em
-- outras três, enquanto a mesma média em BIGNUMERIC saiu byte-idêntica nas seis.
--
-- ⚠️ E ISSO NÃO É PRIVILÉGIO DE COLUNA FRACIONÁRIA — foi a primeira explicação e ela é FALSA.
-- Sobre 15.556 linhas de `total_shots + corner_kicks`, que são INTEIROS, `AVG` deu cinco valores
-- distintos em seis execuções (17.530213422473619 a …661) enquanto
-- `SAFE_DIVIDE(SUM(...), COUNT(...))` sobre os MESMOS inteiros saiu idêntico nas seis. O
-- discriminante é a CONSTRUÇÃO, não o tipo: `SUM` é exato (inteiro, ou ponto fixo em NUMERIC) e
-- independe da ordem, e depois há UMA divisão só. É, aliás, por isso que as outras oito premissas
-- do 1X2 ficam cravadas build após build — o `int_futebol_team_form_pit` já as calcula com
-- `SAFE_DIVIDE(SUM(...), COUNTIF(...))`. Elas não são estáveis por serem de inteiro; são estáveis
-- por não passarem por `AVG`.
--
-- Sozinho o ruído seria inofensivo. O estrago vem do limiar fixo da premissa logo abaixo, contra
-- o qual 16 linhas estão a UM ULP: o delta delas vale 0,30 em decimal, e o `0.3` binário é
-- 0,29999999999999998889…, de modo que nenhuma margem real separa os dois lados. Elas trocavam de
-- lado sozinhas a cada build — `superioridade_xg` acendeu em 4019/4020/4021/4022 linhas em seis
-- execuções do MESMO SQL sobre o MESMO insumo.
--
-- O NUMERIC resolve a segunda metade: é ponto FIXO, então `1,4 − 1,1 >= 0,3` é TRUE, que é o que
-- a premissa quis dizer. As alternativas medidas e recusadas: `ROUND(delta, 2) >= 0.3` NÃO
-- corrige (só muda a borda de faca de 0,300 para 0,295, região mais densa, e segue flapando em
-- 4061/4062/4063); tolerância (`>= 0.3 - 1e-9`) chega ao mesmo número mas exige épsilon com o
-- sinal certo em cada call-site, para sempre. `expected_goals` tem 2 casas na fonte, e NUMERIC
-- (escala 9) as representa exatamente.
-- MEDIÇÃO — recorte de contagem. O filtro de season sai e no lugar dele os pares (jogo-alvo,
-- time) × partida anterior são ranqueados, sobrevivendo só os N mais recentes — contagem móvel,
-- que atravessa a virada de temporada por construção. O corte mora num CTE à parte porque
-- QUALIFY na mesma SELECT da agregação filtraria DEPOIS do GROUP BY, com a média já feita.
-- Desempate por fixture_id: `date_utc` é DATE, e duas partidas do mesmo time na mesma data
-- (dado torto) escolheriam sobrevivente ao acaso.
xg_pares AS (
    SELECT
        sp.fixture_id, sp.team_id,
        st.expected_goals  AS xg_for,
        opp.expected_goals AS xg_against
    FROM fixture_team_spine sp
    JOIN `smartbetting-dados`.`futebol`.`fact_fixture_stats` st
        ON  st.team_id        = sp.team_id
        AND st.date_utc       < DATE(sp.kickoff_utc)
    JOIN `smartbetting-dados`.`futebol`.`fact_fixture_stats` opp
        ON  opp.fixture_id = st.fixture_id
        AND opp.team_id   != st.team_id
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sp.fixture_id, sp.team_id
        ORDER BY st.date_utc DESC, st.fixture_id DESC
    ) <= 10
),
xg AS (
    SELECT
        fixture_id, team_id,
        SAFE_DIVIDE(SUM(CAST(xg_for     AS NUMERIC)), COUNT(xg_for))     AS xg_for_avg,
        SAFE_DIVIDE(SUM(CAST(xg_against AS NUMERIC)), COUNT(xg_against)) AS xg_against_avg
    FROM xg_pares
    GROUP BY fixture_id, team_id
),

-- ============================================================================
-- S7: desfalque PESADO POR IMPORTÂNCIA. Conta só TITULAR IMPORTANTE fora
-- ('Missing Fixture' AND is_important) por (fixture, time). Fonte:
-- int_futebol_desfalques (injuries x proxy de importância de fact_fixture_player_stats).
-- 'Questionable' (dúvida) NÃO dispara — conservador, fiel à §12.1 ("desfalque de
-- titular"); o tipo segue guardado/exibido em int_futebol_desfalques (front).
-- ============================================================================
desf AS (
    SELECT
        fixture_id,
        team_id,
        COUNTIF(injury_type = 'Missing Fixture' AND is_important) AS missing_important_count
    FROM `smartbetting-dados`.`futebol`.`int_futebol_desfalques`
    GROUP BY fixture_id, team_id
),

-- #42 (ADR 0003): o REGISTRO DE QUE PERGUNTAMOS pelo jogo antes do apito. Sem ele, "a fonte
-- respondeu e não havia desfalque" e "nunca perguntamos por este jogo" chegavam aqui como o
-- mesmo zero — e o zero do nosso lado é CONDIÇÃO para desfalque_adversario acender, de modo
-- que a cegueira habilitava a premissa em vez de impedi-la.
-- Mesma âncora do int_futebol_desfalques (coleta ANTES do apito, e não no dia do apito): o
-- poll roda de hora em hora, então no dia do jogo há coleta dos dois lados do apito, e a de
-- depois explicaria um jogo que já aconteceu.
-- ⚠️ QUALQUER registro pré-apito conta, inclusive o das 96h — que é o horizonte do poll,
-- enquanto a fonte só publica a lista a ~53–70h. Ou seja, um jogo distante pode ter registro
-- de uma resposta vazia que só significa "ainda não publicaram". Estreitar isto para uma
-- janela de publicação é a HEURÍSTICA DE JANELA que a ADR 0003 rejeitou explicitamente — é o
-- mesmo conhecimento fabricado com outro nome, derivado de 28 fixtures observados. O erro que
-- sobra é conservador e se cura sozinho: nessa faixa os dois lados valem zero, então a
-- premissa do adversário não acende por falta do adversário desfalcado, e o poll do dia
-- seguinte substitui o registro assim que a fonte publica.
coleta AS (
    SELECT DISTINCT c.fixture_id
    FROM `smartbetting-dados`.`futebol`.`stg_futebol_injuries_coleta` c
    JOIN fixtures f USING (fixture_id)
    WHERE c.coletado_em < f.kickoff_utc
),

-- H2H: confrontos diretos ANTERIORES ao jogo; conta vitórias de S (só Home/Away).
h2h AS (
    SELECT
        o.fixture_id, o.outcome,
        COUNT(*) AS h2h_total,
        COUNTIF(
            (h.home_team_id = o.s_team_id AND h.home_team_winner)
         OR (h.away_team_id = o.s_team_id AND h.away_team_winner)
        ) AS s_wins
    FROM outcomes o
    JOIN `smartbetting-dados`.`futebol`.`fact_h2h` h
        ON h.h2h_pair_key = CONCAT(
               CAST(LEAST(o.s_team_id, o.o_team_id) AS STRING), '-',
               CAST(GREATEST(o.s_team_id, o.o_team_id) AS STRING))
       AND h.fixture_id  != o.fixture_id
       AND h.kickoff_utc  < o.kickoff_utc
    WHERE o.s_team_id IS NOT NULL
    GROUP BY o.fixture_id, o.outcome
),

-- Métricas brutas derivadas (por outcome).
metrics AS (
    SELECT
        o.fixture_id, o.competition, o.season, o.outcome, o.s_is_home,

        -- ataque de S no seu campo / defesa de O no campo dele (forca_mismatch)
        IF(o.s_is_home, s.goals_for_avg_home, s.goals_for_avg_away)          AS s_gf_venue,
        IF(o.s_is_home, od.goals_against_avg_away, od.goals_against_avg_home) AS o_ga_venue,

        -- aproveitamento (mando)
        (s.wins_home * 3 + s.draws_home) / NULLIF(s.played_home * 3, 0) * 100 AS pct_pts_home,
        (s.wins_away * 3 + s.draws_away) / NULLIF(s.played_away * 3, 0) * 100 AS aprov_fora,

        -- xG (superioridade_xg)
        sx.xg_for_avg      AS s_xg_for,
        ox.xg_against_avg  AS o_xg_against,

        -- Desfalques pesados por importância (S7): só titular importante fora conta.
        -- SEM COALESCE PARA ZERO (#42): o zero passa a ter de ser MERECIDO, e são dois os
        -- jeitos de merecê-lo. (1) O time tem linha de desfalque, e aí a contagem é real —
        -- pode ser zero porque só há 'Questionable' ou reserva na lista. (2) Não tem linha,
        -- mas perguntamos pelo jogo antes do apito: o poll devolve a partida inteira, então
        -- "perguntamos e não veio nada deste time" é zero de verdade.
        -- Fora desses dois, o contador é NULL — e o NULL é o que impede a nossa cegueira de
        -- habilitar `desfalque_adversario` e de eximir a penalidade de desfalque próprio.
        -- A ordem dos dois braços importa e protege o CASO ASSIMÉTRICO: quando a fonte
        -- devolveu um lado só, o lado com linha mantém a contagem real e o outro fica NULL,
        -- em vez de o fixture inteiro virar zero (antes) ou NULL (se o registro mandasse).
        COALESCE(si.missing_important_count, IF(cl.fixture_id IS NULL, NULL, 0)) AS s_missing,
        COALESCE(oi.missing_important_count, IF(cl.fixture_id IS NULL, NULL, 0)) AS o_missing,

        -- tabela do campeonato NO INSTANTE DO JOGO (superioridade_tabela)
        s.rank    AS s_rank,
        od.rank   AS o_rank,
        s.ppg     AS s_ppg,
        od.ppg    AS o_ppg,

        -- forma: vitórias nos 5 jogos ANTERIORES ao kickoff (antes: 'W' no form do último snapshot)
        -- SEM COALESCE (#41): time sem linha de forma tem que chegar NULL, senão o zero
        -- forjado é indistinguível de "jogou 5 e não venceu nenhuma" e o contador de
        -- premissas sem dado nasce zerado. A premissa segue FALSE nos dois casos — o
        -- COALESCE(..., FALSE) da CTE `flags` é quem garante isso.
        -- O n_games_last5 na frente é a classe (b) do mapa: o n_wins_last5 do team_form_pit já
        -- é um COUNT sobre UNNEST, e devolve 0 sobre histórico VAZIO sem nenhum NULL para
        -- detectar. Sem histórico nenhum a forma é desconhecida, não é zero. (O corte é em
        -- ZERO jogo, não em cinco: 1 a 4 jogos é medição real de amostra curta, e contá-la
        -- acenderia o contador em toda rodada 2 de toda liga.)
        IF(s.n_games_last5 > 0, s.n_wins_last5, NULL) AS n_wins_last5,

        -- h2h — SEM COALESCE pelo mesmo motivo: sem confronto direto registrado o total é
        -- NULL, não zero. "Nunca se enfrentaram" e "não sabemos se se enfrentaram" eram o
        -- mesmo 0 antes desta mudança.
        hh.h2h_total AS h2h_total,
        hh.s_wins    AS s_wins
    FROM outcomes o
    LEFT JOIN pit s   ON s.fixture_id  = o.fixture_id AND s.team_id  = o.s_team_id
    LEFT JOIN pit od  ON od.fixture_id = o.fixture_id AND od.team_id = o.o_team_id
    LEFT JOIN xg sx   ON sx.fixture_id = o.fixture_id AND sx.team_id = o.s_team_id
    LEFT JOIN xg ox   ON ox.fixture_id = o.fixture_id AND ox.team_id = o.o_team_id
    LEFT JOIN desf si  ON si.fixture_id = o.fixture_id AND si.team_id = o.s_team_id
    LEFT JOIN desf oi  ON oi.fixture_id = o.fixture_id AND oi.team_id = o.o_team_id
    LEFT JOIN coleta cl ON cl.fixture_id = o.fixture_id
    LEFT JOIN h2h hh  ON hh.fixture_id = o.fixture_id AND hh.outcome = o.outcome
),

-- Premissas (booleanos) e pesos.
flags AS (
    SELECT
        m.*,
        COALESCE(m.s_gf_venue >= 1.4 AND m.o_ga_venue >= 1.3, FALSE)        AS forca_mismatch,
        -- O limiar é NUMERIC casado com a média NUMERIC (#78): se um dos lados fosse FLOAT64, o
        -- supertipo da comparação viraria FLOAT64 e o NUMERIC da CTE seria convertido de volta,
        -- reintroduzindo exatamente o ruído que ele existe para tirar.
        COALESCE(m.s_xg_for - m.o_xg_against >= NUMERIC '0.3', FALSE)       AS superioridade_xg,
        CASE
            WHEN m.s_is_home       AND m.pct_pts_home >= 55 THEN 8
            WHEN m.s_is_home = FALSE AND m.aprov_fora  >= 45 THEN 4
            ELSE 0
        END                                                                AS pts_mando,
        COALESCE(m.o_missing >= 1 AND m.s_missing = 0, FALSE)              AS desfalque_adversario,
        (COALESCE(m.o_rank - m.s_rank >= 6, FALSE)
            OR COALESCE(m.s_ppg >= 1.3 * m.o_ppg, FALSE))                  AS superioridade_tabela,
        COALESCE(m.n_wins_last5 >= 3, FALSE)                               AS forma,
        COALESCE(m.h2h_total >= 1 AND m.s_wins * 2 >= m.h2h_total, FALSE)  AS h2h_favoravel,
        -- penalidades específicas 1X2
        (m.outcome = 'Draw')                                              AS pick_empate,
        -- SEM COALESCE (#42), e este é o ponto da mudança: com o zero forjado, a penalidade
        -- nunca punia um time do qual não sabíamos nada — a coluna afirmava "está completo".
        -- Agora ela chega NULL onde não sabemos. Não vira −15 (não sabemos que há desfalque,
        -- e inventá-lo puniria 99% do board): deixa de AFIRMAR a isenção. Quem consome sabe
        -- separar as duas coisas — a aritmética logo abaixo COALESCEa, e o contador de
        -- cegueira já marca a linha pela premissa que lê o mesmo insumo.
        (m.s_missing >= 1)                                                AS desfalque_proprio
    FROM metrics m
),

scored AS (
    SELECT
        f.*,
        (f.pts_mando > 0) AS mando,
        (
            12 * CAST(f.forca_mismatch       AS INT64)
          +  8 * CAST(f.superioridade_xg     AS INT64)
          +       f.pts_mando
          +  8 * CAST(f.desfalque_adversario AS INT64)
          +  6 * CAST(f.superioridade_tabela AS INT64)
          +  5 * CAST(f.forma                AS INT64)
          +  4 * CAST(f.h2h_favoravel        AS INT64)
        ) AS pts_premissas,
        (
            10 * CAST(f.pick_empate       AS INT64)
          -- COALESCE aqui, e não na origem (#42): o NULL de desfalque_proprio é informação
          -- na coluna e ruído na soma. Sem ele, TODA linha de empate zeraria as penalidades
          -- inteiras — no 'Draw' não há lado apostado, logo não há s_missing, logo o NULL é
          -- permanente e contaminaria os −10 do pick_empate.
          + 15 * CAST(COALESCE(f.desfalque_proprio, FALSE) AS INT64)
        ) AS penalidades_1x2_pts
    FROM flags f
),

-- Cegueira (#41, ADR 0003): quais premissas se aplicavam a esta linha, não acenderam, e não
-- acenderam por FALTA DE INSUMO — separadas das que foram avaliadas e não estavam lá. Gerada
-- do mapa futebol_insumos_premissa(), nunca escrita à mão. Depois de `scored` porque `mando`
-- só existe a partir dela.
cegueira AS (
    SELECT
        s.*,
        ARRAY(SELECT premissa FROM UNNEST([
        IF(COALESCE((outcome <> 'Draw')
           AND NOT COALESCE(forca_mismatch, FALSE)
           AND (s_gf_venue IS NULL OR o_ga_venue IS NULL), FALSE), 'forca_mismatch', NULL),
        IF(COALESCE((outcome <> 'Draw')
           AND NOT COALESCE(superioridade_xg, FALSE)
           AND (s_xg_for IS NULL OR o_xg_against IS NULL), FALSE), 'superioridade_xg', NULL),
        IF(COALESCE((outcome <> 'Draw')
           AND NOT COALESCE(mando, FALSE)
           AND (((s_is_home) AND pct_pts_home IS NULL) OR ((NOT s_is_home) AND aprov_fora IS NULL)), FALSE), 'mando', NULL),
        IF(COALESCE((outcome <> 'Draw')
           AND NOT COALESCE(desfalque_adversario, FALSE)
           AND (s_missing IS NULL OR o_missing IS NULL), FALSE), 'desfalque_adversario', NULL),
        IF(COALESCE((outcome <> 'Draw')
           AND NOT COALESCE(superioridade_tabela, FALSE)
           AND (s_rank IS NULL OR o_rank IS NULL OR s_ppg IS NULL OR o_ppg IS NULL), FALSE), 'superioridade_tabela', NULL),
        IF(COALESCE((outcome <> 'Draw')
           AND NOT COALESCE(forma, FALSE)
           AND (n_wins_last5 IS NULL), FALSE), 'forma', NULL),
        IF(COALESCE((outcome <> 'Draw')
           AND NOT COALESCE(h2h_favoravel, FALSE)
           AND (h2h_total IS NULL OR s_wins IS NULL), FALSE), 'h2h_favoravel', NULL)
    ]) AS premissa WHERE premissa IS NOT NULL) AS premissas_cegas
    FROM scored s
)

SELECT
    fixture_id,
    competition,
    season,
    outcome,
    -- flags (transparência/debug)
    forca_mismatch,
    superioridade_xg,
    mando,
    pts_mando,
    desfalque_adversario,
    superioridade_tabela,
    forma,
    h2h_favoravel,
    pick_empate,
    desfalque_proprio,
    s_missing,
    -- agregados
    pts_premissas,
    penalidades_1x2_pts,
    -- cegueira: a lista é o que torna o número auditável (e é dela que a Dupla Chance herda a
    -- cegueira das premissas do 1X2 que ela reusa).
    premissas_cegas,
    ARRAY_LENGTH(premissas_cegas) AS premissas_sem_dado,

    -- "por quê": premissas que dispararam, em linguagem de gente, ordenadas por peso.
    ARRAY(SELECT e FROM UNNEST([
        IF(forca_mismatch,
           FORMAT('marca %.1f gol/jogo %s e o adversário cede %.1f %s',
                  s_gf_venue, IF(s_is_home, 'em casa', 'fora'),
                  o_ga_venue, IF(s_is_home, 'fora', 'em casa')), NULL),
        IF(superioridade_xg,
           FORMAT('cria %.2f xG/jogo contra %.2f que o adversário costuma ceder',
                  s_xg_for, o_xg_against), NULL),
        IF(mando,
           IF(s_is_home,
              FORMAT('%.0f%% dos pontos como mandante', pct_pts_home),
              FORMAT('%.0f%% de aproveitamento como visitante', aprov_fora)), NULL),
        IF(desfalque_adversario,
           FORMAT('adversário com %d titular(es) importante(s) fora e time completo', o_missing), NULL),
        IF(superioridade_tabela, 'claramente superior na tabela', NULL),
        IF(forma, FORMAT('%d vitórias nos últimos 5 jogos', n_wins_last5), NULL),
        IF(h2h_favoravel,
           FORMAT('venceu %d dos últimos %d confrontos diretos', s_wins, h2h_total), NULL)
    ]) AS e WHERE e IS NOT NULL) AS evidencias,

    -- avisos: penalidades específicas do 1X2.
    ARRAY(SELECT a FROM UNNEST([
        IF(pick_empate, '⚠ empate é a saída mais difícil de prever (−10)', NULL),
        IF(desfalque_proprio,
           FORMAT('⚠ desfalcado: %d titular(es) importante(s) fora (−15)', s_missing), NULL)
    ]) AS a WHERE a IS NOT NULL) AS avisos,

    CURRENT_TIMESTAMP() AS dbt_loaded_at
FROM cegueira