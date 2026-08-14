{{ config(
    materialized='table',
    description='S1 do Motor de Score — premissas de contexto do mercado RESULTADO (1X2). 3 linhas por fixture (outcome Home/Draw/Away). S = lado apostado, O = adversário. ⚠️ Task 0 (look-ahead): forca_mismatch/mando/superioridade_tabela/forma leem int_futebol_team_form_pit (point-in-time por fixture), NÃO mais fact_team_season_stats + standings_latest — que em 24/25 entregavam a temporada fechada e a tabela final a jogos da rodada 1. Cada premissa é um booleano que soma seu peso ao PTS_PREMISSAS (espelha §12.1 do épico MOTOR_SCORE_CONFIABILIDADE.md). Penalidades específicas: pick_empate (-10), desfalque_proprio (-15). Degradação graciosa: dado ausente -> premissa FALSE (Copa sem xG/injuries). evidencias[]/avisos[] = bullets legíveis pro front. O gate/edge/Score são aplicados no mart fact_value_opportunities. ⚠️ MEDIÇÃO (task [F], ADR 0007): o spine de xG aceita as DUAS vars da medição — pit_escopo (da_competicao|todas) e pit_recorte (temporada|ultimos_10, que troca o filtro de season por um teto de 10 partidas) —, cujos DEFAULTS reproduzem exatamente o comportamento descrito acima; no default o SQL compilado é idêntico ao de antes de as vars existirem. Produção nunca a passa; ela serve às células de medição, materializadas no dataset futebol_taskF. superioridade_tabela NÃO segue o eixo (rank/ppg vêm do team_form_pit, que os mantém competição-scoped em todas as células, ADR 0008), e o h2h_favoravel também não, por motivo oposto: o fact_h2h já cruza campeonatos hoje, e restringi-lo seria mudar premissa. Contador de cegueira (#41, ADR 0003): premissas_cegas[] e premissas_sem_dado dizem quais premissas APLICÁVEIS a cada linha não puderam ser avaliadas por falta de insumo — geradas do mapa futebol_insumos_premissa(), nunca escritas à mão. O score NÃO muda: a premissa cega já não acendia e continua não acendendo; o que muda é o board passar a dizer o que não levou em conta. Para isso, n_wins_last5 e h2h_total/s_wins perderam o COALESCE de entrada (a ausência chega NULL), e n_wins_last5 vira NULL sem histórico nenhum. Desfalque (#42): s_missing/o_missing perderam o COALESCE para zero e passam a ser NULL onde não perguntamos pelo jogo antes do apito (o registro vem de stg_futebol_injuries_coleta, o vazio registrado de data-engineering#33). O zero agora é merecido — contagem real do time OU registro de coleta pré-apito —, e com isso a cegueira deixa de ser CONDIÇÃO para desfalque_adversario acender e deixa de eximir a penalidade desfalque_proprio, que também chega NULL onde não se sabe (a aritmética das penalidades COALESCEa; a coluna não). Nenhuma linha da base muda: as 13 em que a premissa acende e as 73 em que a penalidade pesa têm todas registro de coleta pré-apito (medido 2026-08-14). Com isso o contador enxerga as 39 premissas.'
) }}
{#- EIXOS DE ESCOPO E RECORTE DA MEDIÇÃO DA TASK [F] (issue #49, ADR 0007) — produção nunca passa estas vars.

    Além do que vem do team_form_pit, este modelo tem UMA fonte de histórico competição-scoped
    própria: o spine de xG (CTE `xg`), que alimenta `superioridade_xg`. Ela responde ao mesmo
    eixo, senão a célula sai MISTURADA — `forca_mismatch` com histórico juntado e
    `superioridade_xg` sem —, e um número assim não responde a pergunta da spec.
    `superioridade_tabela` fica de fora por desenho: rank e ppg vêm do team_form_pit, que os
    mantém competição-scoped em todas as células (ADR 0008). O `fact_h2h` também fica de fora, e
    por motivo oposto: ele JÁ cruza campeonatos hoje, e restringi-lo seria mudar premissa.

    Valores aceitos, validação e o porquê do fail-closed em macros/taskf_eixos.sql. No default
    (`da_competicao`/`temporada`) o SQL compilado é IDÊNTICO ao de antes desta var.

    O eixo de RECORTE (`pit_recorte`) alcança a MESMA fonte desde a #54: sob `ultimos_10` o
    filtro de season sai e o spine passa a ler as N partidas mais recentes do time, atravessando
    a virada de temporada. Os dois eixos entram pelo mesmo FROM/JOIN, escrito uma vez logo acima
    do CTE. -#}
{%- set eixos              = taskf_eixos() %}
{%- set pit_escopo         = eixos.escopo %}
{%- set pit_recorte        = eixos.recorte %}
{%- set tamanho_do_recorte = eixos.tamanho_do_recorte %}

WITH fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season,
        home_team_id, away_team_id, kickoff_utc
    FROM {{ ref('fact_fixtures') }}
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
    FROM {{ ref('int_futebol_team_form_pit') }}
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
{#- O FROM/JOIN existe UMA vez e é renderizado nas duas formas do CTE `xg` (média direta no
    default, pares ranqueados sob recorte de contagem). É aqui que os DOIS eixos entram, e é por
    isso que ele não pode ser escrito duas vezes: duas cópias de um predicado de eixo não ficam
    iguais para sempre, e a divergência mediria célula misturada sem levantar nada. Mesma técnica
    do `agregados_pit` do int_futebol_team_form_pit. -#}
{%- set xg_from %}
    FROM fixture_team_spine sp
    JOIN {{ ref('fact_fixture_stats') }} st
        ON  st.team_id        = sp.team_id
        {%- if pit_recorte == 'temporada' %}
        AND st.season         = sp.season
        {%- endif %}
        {%- if pit_escopo == 'da_competicao' %}
        AND st.competition_id = sp.competition_id
        {%- endif %}
        AND st.date_utc       < DATE(sp.kickoff_utc)
    JOIN {{ ref('fact_fixture_stats') }} opp
        ON  opp.fixture_id = st.fixture_id
        AND opp.team_id   != st.team_id
{%- endset %}
{%- if pit_recorte == 'ultimos_10' %}
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
{{- xg_from }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sp.fixture_id, sp.team_id
        ORDER BY st.date_utc DESC, st.fixture_id DESC
    ) <= {{ tamanho_do_recorte }}
),
xg AS (
    SELECT
        fixture_id, team_id,
        AVG(xg_for)     AS xg_for_avg,
        AVG(xg_against) AS xg_against_avg
    FROM xg_pares
    GROUP BY fixture_id, team_id
),
{%- else %}
xg AS (
    SELECT
        sp.fixture_id, sp.team_id,
        AVG(st.expected_goals)  AS xg_for_avg,
        AVG(opp.expected_goals) AS xg_against_avg
{{- xg_from }}
    GROUP BY sp.fixture_id, sp.team_id
),
{%- endif %}

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
    FROM {{ ref('int_futebol_desfalques') }}
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
    FROM {{ ref('stg_futebol_injuries_coleta') }} c
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
    JOIN {{ ref('fact_h2h') }} h
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
        COALESCE(m.s_xg_for - m.o_xg_against >= 0.3, FALSE)                 AS superioridade_xg,
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
        {{ futebol_premissas_cegas('int_futebol_premissas_1x2') }} AS premissas_cegas
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
