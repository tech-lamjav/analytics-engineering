{#
    Impressão digital do INSUMO do int_futebol_team_form_pit, por (competition_id, season).

    Existe para que a Costura A (task [F], issue #49, ADR 0007) possa ser exata sem ser frágil.
    O insumo do modelo é vivo — fixture novo, resultado que entra, jogo remarcado —, e nada disso
    é regressão, mas tudo isso muda a saída. A guarda então compara só as partições cujo insumo é
    idêntico ao do congelamento, e nelas exige igualdade linha a linha, sem folga.

    O recorte por (competition_id, season) é sólido porque no caminho DEFAULT a linha de uma
    âncora em (C,S) é função só dos fixtures de (C,S) e das standings de (C,S): os dois joins do
    modelo são escopados pelos dois campos. Sob pit_escopo=todas isso deixa de valer — e é aí que
    a guarda deve mesmo falhar, porque a var saiu do default.

    ⚠️ ESTA DEFINIÇÃO É CONTRATO CONGELADO. Ela é usada nos dois lados da comparação: uma vez em
    analyses/taskf_congela_baseline.sql, que gravou futebol_taskF.baseline_pit_fingerprint, e a
    cada execução em tests/assert_taskf_pit_default_igual_baseline.sql. Mudar o que entra no
    FARM_FINGERPRINT muda os valores e faz NENHUMA partição casar contra o baseline já gravado —
    a guarda não fica vermelha, fica VAZIA, que é pior. Por isso as duas pontas leem daqui e não
    de cópias: cópia que precisa ficar idêntica para sempre não fica. Se um dia for mesmo preciso
    mudar, o baseline tem de ser recongelado no mesmo commit — decisão de quem revisa, não passo
    de rotina.

    Emite UMA CTE no escopo do chamador, `fp_insumo_pit`, com uma linha por (competition_id,
    season) e as colunas n_fixtures / fp_fixtures / n_grupos / fp_standings. Uma CTE do chamador
    com esse nome a sombreia em silêncio.

    Uso:

        WITH {{ taskf_fingerprint_insumo_pit() }},
        casadas AS (SELECT ... FROM fp_insumo_pit JOIN baseline_pit_fingerprint USING (...))
#}

{% macro taskf_fingerprint_insumo_pit() %}

fp_fixtures_pit AS (
    SELECT
        competition_id,
        season,
        COUNT(*) AS n_fixtures,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
            fixture_id, competition, home_team_id, away_team_id,
            kickoff_utc, status_short, goals_home, goals_away
        )))) AS fp_fixtures
    FROM {{ ref('fact_fixtures') }}
    GROUP BY competition_id, season
),

-- Mesmo QUALIFY do modelo: o insumo que ele de fato lê, e não a tabela crua. O snapshot ganha
-- uma linha por dia por time, então digitalizar o cru mudaria todo dia e jogaria todas as
-- competições fora da comparação — a guarda passaria em branco.
fp_team_group_pit AS (
    SELECT league_id AS competition_id, season, team_id, group_name
    FROM {{ ref('fact_standings_snapshot') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY league_id, season, team_id
        ORDER BY CASE WHEN group_name LIKE '%third-placed%' THEN 1 ELSE 0 END,
                 snapshot_date DESC
    ) = 1
),

fp_standings_pit AS (
    SELECT
        competition_id,
        season,
        COUNT(*) AS n_grupos,
        BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(team_id, group_name)))) AS fp_standings
    FROM fp_team_group_pit
    GROUP BY competition_id, season
),

fp_insumo_pit AS (
    SELECT
        f.competition_id,
        f.season,
        f.n_fixtures,
        f.fp_fixtures,
        COALESCE(s.n_grupos, 0) AS n_grupos,
        s.fp_standings
    FROM fp_fixtures_pit f
    LEFT JOIN fp_standings_pit s USING (competition_id, season)
)

{% endmacro %}
