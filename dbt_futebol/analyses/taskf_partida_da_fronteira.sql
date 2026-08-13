{#
    [F-7] A PARTIDA QUE PRODUZ A ÚNICA DIVERGÊNCIA da reconciliação, nomeada.

    A `taskf_reconciliacao_180d.sql` reproduz 15 dos 16 campos da tabela do ticket. O décimo sexto
    — "Copa do Brasil, jogos em tudo em 180 dias" — sai 25,6 contra os 25,5 publicados, e a
    diferença inteira é UMA partida contada a mais (409 contra 408, em 16 pares).

    Esta análise mostra qual. Ela lista todo par (jogo-âncora, partida do histórico) em que as
    duas réguas de fronteira discordam: a inclusiva por instante, que a reconciliação usa, e a
    estrita por data, que devolve o número publicado. Discordar aqui é o mesmo que estar na
    fronteira — a partida entra numa contagem e não na outra.

    Existe porque a explicação da divergência é o entregável da #56 ("qualquer divergência é
    explicada, não silenciada"), e uma explicação que só existe na prosa do doc não é conferível.
    Duas linhas na saída — uma por régua discordante em cada sentido — e o `distancia_da_fronteira`
    diz de quanto: hoje, meia hora.

    Mesmo corte e mesmas âncoras da reconciliação (`taskf_universo()`, âncoras `FT`), pelo mesmo
    motivo: uma partida de fronteira medida sobre outro conjunto de âncoras não é a partida que
    produziu o resíduo.

    Rodar com:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target dev --select taskf_partida_da_fronteira
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_partida_da_fronteira.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)
#}

WITH lados AS (
    -- `mandante`/`visitante` seguem o jogo, e não o lado da linha: a partida sai impressa na
    -- ordem em que foi disputada, não na ordem em que o UNION a produziu.
    SELECT fixture_id, competition, competition_id, kickoff_utc, status_short,
           home_team_id AS team_id, home_team_name AS team_name,
           home_team_name AS mandante, away_team_name AS visitante
    FROM {{ ref('fact_fixtures') }}
    UNION ALL
    SELECT fixture_id, competition, competition_id, kickoff_utc, status_short,
           away_team_id, away_team_name,
           home_team_name, away_team_name
    FROM {{ ref('fact_fixtures') }}
),

ancoras AS (
    SELECT * FROM lados l
    WHERE {{ taskf_universo_filtro('l.') }} AND l.status_short = 'FT'
)

SELECT
    a.competition                                        AS competicao_da_ancora,
    a.fixture_id                                         AS ancora_fixture_id,
    a.team_name                                          AS time,
    FORMAT_TIMESTAMP('%F %H:%M', a.kickoff_utc)          AS ancora_kickoff_utc,
    FORMAT_TIMESTAMP('%F %H:%M',
        TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY))  AS fronteira_utc,

    h.fixture_id                                         AS partida_fixture_id,
    h.competition                                        AS partida_competicao,
    h.mandante || ' × ' || h.visitante                   AS partida,
    FORMAT_TIMESTAMP('%F %H:%M', h.kickoff_utc)          AS partida_kickoff_utc,

    -- De quanto ela está dentro (positivo) ou fora (negativo) da fronteira por instante.
    TIMESTAMP_DIFF(h.kickoff_utc,
        TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY), MINUTE) AS distancia_da_fronteira_min,

    -- Qual régua conta esta partida. As duas colunas discordam por construção: só aparecem aqui
    -- as linhas em que discordam.
    h.kickoff_utc >= TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY)          AS conta_por_instante,
    DATE(h.kickoff_utc) >  DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY)   AS conta_por_data_estrita

FROM ancoras a
JOIN lados h
    ON  h.team_id        = a.team_id
    AND h.kickoff_utc    < a.kickoff_utc
    AND h.status_short   = 'FT'
WHERE (h.kickoff_utc >= TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY))
   != (DATE(h.kickoff_utc) > DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY))
ORDER BY a.kickoff_utc, h.kickoff_utc
