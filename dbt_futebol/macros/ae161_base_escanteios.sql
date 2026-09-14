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
    SELECT fixture_id, competition, season, home_team_id, away_team_id, kickoff_utc,
           goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      {%- if cutoff is not none %}
      AND DATE(kickoff_utc) <= DATE('{{ cutoff }}')
      {%- endif %}
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


{#- Catálogo do handicap de escanteios (ClickUp wdx6zf1tt8), MENOS "Decisão" (AE#162, depende
    do #160). Colunas por premissa: nome, peso do catálogo original, expressão SQL booleana
    (lida sobre as colunas que ae161_base_escanteios() expõe em `apostas`).

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

{% macro ae161_premissas_away() %}
    {{ return([
        {'premissa': 'jogo_pouco_escanteio',   'peso': 12, 'sql': 'escanteio_previsto <= 9.05'},
        {'premissa': 'forca_mais_escanteio',   'peso': 9,  'sql': '(a_corner_for - h_corner_for) >= 1.0'},
        {'premissa': 'forca_escanteio_mando',  'peso': 7,  'sql': 'a_mando5 >= 5.2'}
    ]) }}
{% endmacro %}
