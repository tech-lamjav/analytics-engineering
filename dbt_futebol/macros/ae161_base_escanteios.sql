{#- AE#161 (spec #157) — base de medição do handicap de escanteios (market_id 56).

    NÃO reusa task01_base() (issue #3): aquele macro faz JOIN FIXO com int_futebol_premissas_*,
    que não existe para escanteios, e a lista de mercados/catálogo é hardcoded pros 5 mercados
    pontuados. Esta base é paralela, parametrizada, e não escreve em nenhum mart/funil — só
    dbt_futebol/analyses/.

    Parâmetros:
      cutoff              — data (string 'YYYY-MM-DD') ou none. Congela o universo em
                             kickoff_utc <= cutoff. `none` = janela viva (todos os jogos
                             liquidados com preço até hoje), convenção do task01_teste2.sql
                             original.
      janela_fixa         — 'daily'|'t24h'|'t1h'|'t15m' ou none. `none` usa a janela CORRENTE
                             (futebol_devig_janela_corrente() — a mesma que o board usa hoje).
                             Um valor fixo trava a leitura numa janela só, para reproduzir a
                             simulação ad-hoc do Victor (que usou t24h fixo).
      gates_do_board       — TRUE aplica as 3 portas de preço do board desde 2026-09-10
                             (liquidez >= liquidez_min_casas, NOT outlier, faixa de odd
                             1,50-4,00) — o universo do Teste 2. FALSE aplica só liquidez
                             mínima (liquidez_min_casas, default 3) — o universo mais permissivo
                             que a simulação original do Victor usava (ela não tinha gates do
                             board porque eles não existiam em 10/09/2026).
      liquidez_min_casas   — override do piso de casas. Default: 4 sob gates_do_board=true
                             (mesmo var do board), 3 sob gates_do_board=false (o "mínimo de três
                             casas" que o Victor declarou).

    SEMPRE aplicados, nos dois modos: só linha MEIA (futebol_e_linha_meia — nunca linha cheia
    nem de quarto, AE#101/#113); melhor odd (best_odd); benchmark rotulado
    (pinnacle/consenso); liquidação pelo PAR COMPLEMENTAR na ótica do mandante (AE#158 — mesma
    regra do market_id 4); piso de amostra via int_futebol_team_corner_form_pit (AE#159,
    played_total_disponivel, mínimo dos dois times).

    Emite as CTEs `apostas` (grão de aposta, já recortada) e nada mais — quem precisar do
    catálogo de premissas usa o macro ae161_premissas_escanteios() por cima. -#}
{% macro ae161_base_escanteios(cutoff=none, janela_fixa=none, gates_do_board=true, liquidez_min_casas=none) %}

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

-- AE#162 — total de rodadas da fase de pontos corridos de cada (competition_id, season).
-- Informação de CALENDÁRIO (o chaveamento inteiro já existe em fact_fixtures antes da
-- temporada acabar — conferido: temporada em andamento tem o MESMO MAX(round) das já
-- encerradas), não medição — usar não é look-ahead, mesmo raciocínio do group_name em
-- int_futebol_team_form_pit.
total_rodadas AS (
    SELECT competition_id, season,
           MAX(CAST(REGEXP_EXTRACT(round, r'(\d+)$') AS INT64)) AS total_rodadas
    FROM {{ ref('fact_fixtures') }}
    WHERE round LIKE 'Regular Season%'
    GROUP BY 1, 2
),

-- AE#162 — zona de tabela do VISITANTE e reta final, na leitura de standings mais recente
-- ANTES do apito (nunca a mais recente disponível hoje — ver
-- reference_dbt_snapshot_idade_artefato). O histórico de standings só começa em 11/06/2026:
-- jogo mais antigo que isso não tem snapshot anterior e as duas colunas saem NULL
-- (degradação graciosa, documentada no pré-registro). `s.played_total` é a campanha do
-- visitante ATÉ aquele snapshot — mesma fonte que dá o rank/zona, sem join extra.
zona_visitante AS (
    SELECT
        j.fixture_id,
        {{ futebol_zona_tabela_em_disputa('s.rank_description') }}      AS zona_em_disputa,
        SAFE_DIVIDE(s.played_total, tr.total_rodadas) >= 0.80            AS reta_final
    FROM jogos_encerrados j
    JOIN {{ ref('fact_standings_snapshot') }} s
      ON  s.league_id       = j.competition_id
      AND s.season          = j.season
      AND s.team_id         = j.away_team_id
      AND s.snapshot_date   < DATE(j.kickoff_utc)
    LEFT JOIN total_rodadas tr
      ON  tr.competition_id = j.competition_id
      AND tr.season         = j.season
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY j.fixture_id ORDER BY s.snapshot_date DESC
    ) = 1
),

odds_56 AS (
    {%- if janela_fixa is not none %}
    SELECT *
    FROM {{ ref('int_futebol_odds_devig') }}
    WHERE market_id = 56
      AND janela_usada = '{{ janela_fixa }}'
    {%- else %}
    SELECT *
    FROM ({{ futebol_devig_janela_corrente() }})
    WHERE market_id = 56
    {%- endif %}
),

-- Resultado REAL do jogo (não PIT): o escanteio final de cada lado, p/ liquidar. 1 linha por
-- fixture com os dois lados pivotados — mesmo padrão de PARES_ESCANTEIO do script ad-hoc.
resultado_escanteios AS (
    SELECT
        fixture_id,
        MAX(IF(team_side = 'home', corner_kicks, NULL)) AS corners_home,
        MAX(IF(team_side = 'away', corner_kicks, NULL)) AS corners_away
    FROM {{ ref('fact_fixture_stats') }}
    GROUP BY fixture_id
),

pit_home AS (SELECT * FROM {{ ref('int_futebol_team_corner_form_pit') }}),
pit_away AS (SELECT * FROM {{ ref('int_futebol_team_corner_form_pit') }}),

apostas AS (
    SELECT
        o.fixture_id,
        o.outcome_side,
        o.line_value,
        o.best_odd,
        o.n_casas,
        o.prob_justa_fechamento,
        IF(o.valor_fonte = 'pinnacle', 'pinnacle', 'consenso') AS benchmark,
        j.competition,
        j.season,
        j.kickoff_utc,
        LEAST(COALESCE(ph.played_total_disponivel, 0), COALESCE(pa.played_total_disponivel, 0)) AS min_jogos,

        -- AE#162 — insumo da premissa "Decisão" (lado de baixo, Away). mata_mata é
        -- propriedade do JOGO (não depende de lado); reta_final/zona_em_disputa são do
        -- VISITANTE especificamente (ver pré-registro da issue #162).
        (j.round NOT LIKE 'Regular Season%'
         AND j.round NOT LIKE 'Group Stage%'
         AND j.round NOT LIKE 'League Stage%')                                         AS mata_mata,
        COALESCE(zv.reta_final, FALSE)                                                 AS reta_final_visitante,
        COALESCE(zv.zona_em_disputa, FALSE)                                            AS zona_em_disputa_visitante,

        -- Liquidação: PAR COMPLEMENTAR, line_value na ótica do MANDANTE (AE#158) — mesma
        -- fórmula algébrica de task01_liquidacao() p/ o market_id 4, com corner_kicks no
        -- lugar de goals.
        IF(o.outcome_side = 'Home',
           r.corners_home + o.line_value > r.corners_away,
           r.corners_away - o.line_value > r.corners_home)                            AS ganhou,

        -- Insumos PIT (AE#159), expostos p/ o catálogo de premissas montar em cima.
        ph.possession_avg10        AS h_posse,
        pa.possession_avg10        AS a_posse,
        ph.xg_avg10                AS h_xg,
        pa.xg_avg10                AS a_xg,
        ph.corners_for_avg10       AS h_corner_for,
        pa.corners_for_avg10       AS a_corner_for,
        ph.corners_against_avg10   AS h_corner_against,
        pa.corners_against_avg10   AS a_corner_against,
        ph.shots_insidebox_avg10   AS h_area,
        pa.shots_insidebox_avg10   AS a_area,
        ph.corners_for_avg_mando5  AS h_mando5,
        pa.corners_for_avg_mando5  AS a_mando5,
        -- Escanteio previsto do jogo, fórmula do ClickUp wdx6zf1tt8:
        -- (a_favor_mandante + sofridos_visitante + a_favor_visitante + sofridos_mandante) / 2
        SAFE_DIVIDE(ph.corners_for_avg10 + pa.corners_against_avg10
                  + pa.corners_for_avg10 + ph.corners_against_avg10, 2)                AS escanteio_previsto

    FROM odds_56 o
    JOIN jogos_encerrados j
      ON j.fixture_id = o.fixture_id
    JOIN resultado_escanteios r
      ON r.fixture_id = o.fixture_id
    LEFT JOIN pit_home ph
      ON ph.fixture_id = o.fixture_id AND ph.team_id = j.home_team_id
    LEFT JOIN pit_away pa
      ON pa.fixture_id = o.fixture_id AND pa.team_id = j.away_team_id
    LEFT JOIN zona_visitante zv
      ON zv.fixture_id = o.fixture_id
    WHERE o.best_odd                IS NOT NULL
      AND o.prob_justa_fechamento   IS NOT NULL   -- só linhas que o de-vig realmente emitiu (AE#158)
      AND r.corners_home IS NOT NULL AND r.corners_away IS NOT NULL  -- resultado real existe p/ liquidar
      AND {{ futebol_e_linha_meia('o.line_value') }}                 -- só meia linha (AE#101/#113)
      {%- if gates_do_board %}
      AND COALESCE(o.n_casas >= {{ _liq }}, FALSE)
      AND COALESCE(NOT o.pen_odd_outlier, FALSE)
      AND COALESCE(o.best_odd >= {{ var('faixa_odd_min', 1.50) }}
               AND o.best_odd <= {{ var('faixa_odd_max', 4.00) }}, FALSE)
      {%- else %}
      AND COALESCE(o.n_casas >= {{ _liq }}, FALSE)
      {%- endif %}
)

{% endmacro %}


{#- Catálogo do handicap de escanteios (ClickUp wdx6zf1tt8). Colunas por premissa: nome, peso
    do catálogo original, expressão SQL booleana (lida sobre as colunas que
    ae161_base_escanteios() expõe em `apostas`).

    "Decisão" (lado Away, AE#162) só entra em ae161_premissas_away() com
    incluir_decisao=true — o default (false) preserva o catálogo exatamente como a AE#161 o
    mediu, sem "Decisão", que dependia do #160 e ainda não existia naquele momento.

    "Força mais escanteio" e "Força escanteio no mando" aparecem nos DOIS lados com o MESMO
    nome — é a mesma premissa medida em cada lado (o catálogo original já documenta os dois
    ganhos lado a lado) — mas com limiar/direção PRÓPRIOS por lado: o corte do mando é
    assimétrico de propósito (6,4 em casa, 5,2 fora — o próprio ClickUp explica que mandante
    força mais escanteio por natureza, e corte único mediria a premissa negativa em casa). -#}
{% macro ae161_premissas_home() %}
    {{ return([
        {'premissa': 'domina_posse',           'peso': 12, 'sql': '(h_posse - a_posse) >= 5.8'},
        {'premissa': 'cria_mais_chance',       'peso': 12, 'sql': '(h_xg - a_xg) >= 0.34'},
        {'premissa': 'forca_mais_escanteio',   'peso': 9,  'sql': '(h_corner_for - a_corner_for) >= 1.0'},
        {'premissa': 'ataca_mais_area',        'peso': 6,  'sql': '(h_area - a_area) >= 1.6'},
        {'premissa': 'forca_escanteio_mando',  'peso': 6,  'sql': 'h_mando5 >= 6.4'},
        {'premissa': 'jogo_muito_escanteio',   'peso': 5,  'sql': 'escanteio_previsto >= 10.3'}
    ]) }}
{% endmacro %}

{% macro ae161_premissas_away(incluir_decisao=false) %}
    {%- set base = [
        {'premissa': 'jogo_pouco_escanteio',   'peso': 12, 'sql': 'escanteio_previsto <= 9.05'},
        {'premissa': 'forca_mais_escanteio',   'peso': 9,  'sql': '(a_corner_for - h_corner_for) >= 1.0'},
        {'premissa': 'forca_escanteio_mando',  'peso': 7,  'sql': 'a_mando5 >= 5.2'}
    ] -%}
    {%- if incluir_decisao -%}
        {%- set base = base + [
            {'premissa': 'decisao', 'peso': 4,
             'sql': '(mata_mata OR (reta_final_visitante AND zona_em_disputa_visitante))'}
        ] -%}
    {%- endif -%}
    {{ return(base) }}
{% endmacro %}
