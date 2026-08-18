{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DA ESCALAÇÃO CONFIRMADA (#38): toda escalação confirmada que existe na staging
-- tem que existir no fato, nos dois níveis.
--
-- É a guarda do modo de falha que a #38 consertou, e o ponto dela é que esse modo de falha
-- era MUDO. O dedup dos dois fatos era por (fixture, time) / (fixture, jogador), sem a fase:
-- a escalação "real", que só chega DEPOIS do apito, sobrescrevia a "confirmed" de ~T-30min.
-- 97% do que se sabia antes do jogo era apagado pelo que se soube depois — look-ahead
-- entrando pela porta do dedup — e nada ficava vermelho, porque a tabela continuava
-- populada, única no grão antigo e reconciliada com o spine. O único sintoma era a contagem
-- de fixtures com fase confirmada despencar de 279 na staging para 2 no fato.
--
-- Por isso a guarda compara CHAVE A CHAVE, e não contagem de linhas: contagem de linhas
-- fecharia por acidente sempre que uma fase substituísse a outra 1-para-1, que é exatamente
-- o que acontecia. Anti-join da staging confirmada contra o fato confirmado.
--
-- O que ela NÃO cobre, de propósito: a direção oposta (fixture do spine sem nenhuma linha no
-- fato) já é assert_per_fixture_coverage, e o dedup dentro da fase é o unit test em
-- _fact_fixture_lineups__unit_tests.yml — este é sobre a fase inteira sumir.
--
-- `motivo` separa as duas causas possíveis de uma chave sumir, porque o conserto é diferente:
-- perdida_no_dedup é regressão de código (o grão perdeu a fase de novo); fora_do_spine é
-- fixture ausente de fact_fixtures, cortada pelo INNER JOIN dos dois fatos — hoje 0 de 279,
-- e se aparecer é perda de jogo inteiro, a montante.
--
-- Nível jogador: o lado da staging aplica o mesmo `player_id IS NOT NULL` que o fato aplica.
-- Sem isso, os slots de escalação sem jogador (lixo conhecido da API) acusariam para sempre.

WITH spine AS (
    SELECT fixture_id FROM {{ ref('fact_fixtures') }}
),

-- ── Nível time ───────────────────────────────────────────────────────────────
stg_time AS (
    SELECT DISTINCT fixture_id, team_id
    FROM {{ ref('stg_futebol_fixture_lineups') }}
    WHERE lineup_phase = 'confirmed'
),

fato_time AS (
    SELECT DISTINCT fixture_id, team_id
    FROM {{ ref('fact_fixture_lineups') }}
    WHERE lineup_phase = 'confirmed'
),

faltando_time AS (
    SELECT
        'fact_fixture_lineups' AS fato,
        s.fixture_id,
        s.team_id              AS chave,
        CASE WHEN sp.fixture_id IS NULL THEN 'fora_do_spine' ELSE 'perdida_no_dedup' END AS motivo
    FROM stg_time s
    LEFT JOIN fato_time f ON f.fixture_id = s.fixture_id AND f.team_id = s.team_id
    LEFT JOIN spine sp    ON sp.fixture_id = s.fixture_id
    WHERE f.fixture_id IS NULL
),

-- ── Nível jogador ────────────────────────────────────────────────────────────
stg_jogador AS (
    SELECT DISTINCT fixture_id, player_id
    FROM {{ ref('stg_futebol_fixture_lineups_players') }}
    WHERE lineup_phase = 'confirmed'
      AND player_id IS NOT NULL  -- espelha o filtro do fato
),

fato_jogador AS (
    SELECT DISTINCT fixture_id, player_id
    FROM {{ ref('fact_fixture_lineups_players') }}
    WHERE lineup_phase = 'confirmed'
),

faltando_jogador AS (
    SELECT
        'fact_fixture_lineups_players' AS fato,
        s.fixture_id,
        s.player_id                    AS chave,
        CASE WHEN sp.fixture_id IS NULL THEN 'fora_do_spine' ELSE 'perdida_no_dedup' END AS motivo
    FROM stg_jogador s
    LEFT JOIN fato_jogador f ON f.fixture_id = s.fixture_id AND f.player_id = s.player_id
    LEFT JOIN spine sp       ON sp.fixture_id = s.fixture_id
    WHERE f.fixture_id IS NULL
)

SELECT * FROM faltando_time
UNION ALL
SELECT * FROM faltando_jogador
