{#- AE#183 (spec #179) — base de medição do Total de escanteios (market_id 45).

    Espelha ae161_base_escanteios.sql (Handicap, market_id 56, #157/#161), mas com uma
    diferença estrutural que o Handicap não tinha: o mercado 45 é cotado em ESCADA (~16
    linhas/jogo, 6,5 a 13,5) e só a LINHA PRINCIPAL — a de odd mais próxima de 2,00, por
    jogo e por lado (Over/Under) — entra em qualquer medição (CONTEXT.md, "Linha
    principal"; `prop-play-predictor` docs/futebol-metodologia-escanteios-total.md,
    2026-09-13: 6.512 linhas de escada vs 812 linha-principal nos mesmos 406 jogos).

    ORDEM: gates de preço PRIMEIRO (linha meia + liquidez + — sob gates_do_board — outlier
    e faixa de odd), seleção da linha principal DEPOIS, sobre o que sobrou. Não o
    contrário. Confirmado lendo `prop-play-predictor` commit b89fadb
    scripts/futebol-escanteios-total.mjs (a implementação real da simulação original, não
    só a prosa do documento): a query `odds()` de lá aplica `collection_window='t24h'`,
    meia linha e `count(distinct bookmaker_id) >= 3` na MESMA query que depois agrupa e
    escolhe `min(abs(odd-2))` por (fixture_id, lado). Selecionar a principal ANTES dos
    gates e só then dropar quem falha o gate teria jogo/lado ficando SEM oportunidade toda
    vez que a linha mais perto de 2,00 por acaso tivesse pouca liquidez, mesmo havendo uma
    segunda linha (odd 1,90 ou 2,15, digamos) publicável — isso não é o que o produto
    fofoca: o produto publica uma linha por jogo/lado ENTRE AS PUBLICÁVEIS, não a mais
    perto de 2,00 do universo bruto. Ver comentário de pré-registro da issue #183 para a
    reconciliação com a leitura inicial de CONTEXT.md (que trata "qual linha" e "qual
    gate" como eixos ortogonais sem declarar a ordem — a ordem entra aqui, e é esta).

    Parâmetros — mesma semântica de ae161_base_escanteios:
      cutoff              — 'YYYY-MM-DD' ou none (janela viva).
      janela_fixa         — 'daily'|'t24h'|'t1h'|'t15m' ou none (none = corrente).
                             A reprodução da simulação original usa 't24h' fixo (é o que
                             scripts/futebol-escanteios-total.mjs lê).
      gates_do_board       — TRUE: liquidez>=liquidez_min_casas + NOT outlier + odd
                             1,50-4,00 (as 3 portas do board desde 2026-09-10). FALSE:
                             só liquidez (o "mínimo de três casas" do script original —
                             ele não tinha outlier nem faixa de odd, não existiam ainda).
      liquidez_min_casas   — override. Default: 4 sob gates_do_board=true (mesmo var do
                             board), 3 sob gates_do_board=false (script original:
                             `count(distinct bookmaker_id) >= 3`).

    SEMPRE aplicados: só linha MEIA (futebol_e_linha_meia — mesma porta AE#101/#113;
    confirmado por query que o mercado 45 NÃO é só meia — a escada tem linhas cheias e de
    quarto também, resto-de-quarto 0/1/3 somam ~46% das 145,7 mil linhas cruas); melhor
    odd (best_odd); benchmark rotulado (pinnacle/consenso — cobertura da Pinnacle aqui é
    bem mais fina que no 56: ~15% das linhas t24h contra a maioria no Handicap, ver
    pré-registro); piso de amostra via int_futebol_team_corner_form_pit (AE#159/#181,
    played_total_disponivel, mínimo dos dois times, min_jogos>=10 — "jogo com menos de 10
    partidas anteriores no histórico fica de fora", seção 2 do documento de metodologia).

    Liquidação: TOTAL de escanteios do jogo (corners_home+corners_away, de
    fact_fixture_stats via self-join por fixture_id, não da média PIT) contra a linha
    escolhida. Over ganha se total > linha; Under ganha se total < linha. Linha meia
    garante que nunca empata (nunca push) — não precisa de terceiro estado.

    Emite as CTEs `apostas` (grão de aposta, já recortada na linha principal) e nada
    mais — quem precisar do catálogo de premissas usa ae183_premissas_escanteios_total()
    por cima. -#}
{% macro ae183_base_escanteios_total(cutoff=none, janela_fixa=none, gates_do_board=true, liquidez_min_casas=none) %}

{%- set _liq = liquidez_min_casas if liquidez_min_casas is not none else (4 if gates_do_board else 3) -%}

jogos_encerrados AS (
    SELECT fixture_id, competition, competition_id, season, round, home_team_id, away_team_id,
           kickoff_utc, goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      {%- if cutoff is not none %}
      AND DATE(kickoff_utc) <= DATE('{{ cutoff }}')
      {%- endif %}
),

-- Fase de pontos corridos de cada (competition_id, season) — mesma CTE de
-- ae161_base_escanteios/AE#162, reaproveitada aqui para reta_final. `total_rodadas` é
-- informação de CALENDÁRIO (existe antes do fim da temporada), não medição.
total_rodadas AS (
    SELECT competition_id, season,
           MAX(CAST(REGEXP_EXTRACT(round, r'(\d+)$') AS INT64)) AS total_rodadas
    FROM {{ ref('fact_fixtures') }}
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
        FROM {{ ref('fact_fixture_stats') }}
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
    FROM {{ ref('fact_fixture_stats') }}
    GROUP BY fixture_id
),

odds_45 AS (
    {%- if janela_fixa is not none %}
    SELECT *
    FROM {{ ref('int_futebol_odds_devig') }}
    WHERE market_id = 45
      AND janela_usada = '{{ janela_fixa }}'
    {%- else %}
    SELECT *
    FROM ({{ futebol_devig_janela_corrente() }})
    WHERE market_id = 45
    {%- endif %}
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
      AND {{ futebol_e_linha_meia('line_value') }}
      AND COALESCE(n_casas >= {{ _liq }}, FALSE)
      {%- if gates_do_board %}
      AND COALESCE(NOT pen_odd_outlier, FALSE)
      AND COALESCE(best_odd >= {{ var('faixa_odd_min', 1.50) }}
               AND best_odd <= {{ var('faixa_odd_max', 4.00) }}, FALSE)
      {%- endif %}
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

pit_home AS (SELECT * FROM {{ ref('int_futebol_team_corner_form_pit') }}),
pit_away AS (SELECT * FROM {{ ref('int_futebol_team_corner_form_pit') }}),

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

{% endmacro %}
