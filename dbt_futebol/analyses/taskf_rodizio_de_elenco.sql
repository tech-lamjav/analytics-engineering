/*
    [F-8] RODÍZIO DE ELENCO — o segundo confundidor do merge, com número em vez de opinião.

    O QUE ELE AMEAÇA. A célula `escopo` empresta ao histórico de um time as partidas que ele jogou
    em outra competição. Se o time entra em campo na copa com OUTRO elenco — poupando titulares
    para o campeonato —, essas partidas emprestadas descrevem um time que não vai jogar o jogo
    sobre o qual a premissa decide. O ganho de amostra seria real e a informação, não. O ticket de
    origem registrou a ressalva sem número; a spec #49 (user story 23) pediu o número.

    A MEDIDA. Para cada time, os jogos dele são postos em ordem de kickoff e cada par de jogos
    CONSECUTIVOS vira uma observação: quantos dos 11 titulares se repetiram. O par é classificado
    pelo tipo das duas competições (`dim_leagues.league_type`, derivado do catálogo):

      liga_liga   os dois jogos são de pontos corridos           → é o CONTROLE
      liga_copa   um de cada — é a pergunta do ticket            → é o TRATAMENTO
      copa_copa   os dois de copa

    ⚠️ SEM O CONTROLE, O NÚMERO DO TRATAMENTO NÃO QUER DIZER NADA. "7 dos 11 titulares se
    repetiram entre a liga e a copa" só é rodízio se entre dois jogos DE LIGA se repetirem 11 — e
    não se repetem: lesão, suspensão e desgaste mexem no XI o tempo todo. O que responde à
    pergunta do ticket é a DIFERENÇA entre os dois estratos, e é por isso que o controle é medido
    aqui dentro e não citado de memória.

    ⚠️ E O CONTROLE TEM UM CONFUNDIDOR PRÓPRIO: CALENDÁRIO. Par liga↔copa costuma ser jogo de
    meio de semana seguido de jogo de fim de semana, e par liga↔liga costuma ter uma semana
    inteira no meio. Rodízio por congestionamento e rodízio por prioridade de competição são
    coisas diferentes, e a segunda é a do ticket. Por isso a saída tem o nível
    `estrato_x_dias`, que corta os dois estratos pela distância entre os jogos: se a diferença
    entre `liga_copa` e `liga_liga` sobreviver DENTRO da mesma faixa de dias, ela não é
    calendário.

    ⚠️ A PREMISSA DO CRITÉRIO DE ACEITE É FALSA, E ISSO É RESULTADO. O ticket afirma que "a
    cobertura de lineups é de 100% em todas as competições". Não é — e falha exatamente onde o
    próprio ticket manda olhar, as fases iniciais da Copa do Brasil. O nível `cobertura` mede isso
    por competição, e nenhum lado sem XI utilizável entra num par: ele é contado e descartado, não
    completado. XI utilizável = exatamente 11 titulares na fase `real`.

    ⚠️ POR QUE A FASE `real`, E NÃO A ESCALAÇÃO INTEIRA. O `fact_fixture_lineups_players` dedupa
    por (fixture_id, player_id) com latest-wins, e não por (fixture_id, team_id, fase). Quando a
    escalação `confirmed` (~T-30min) e a `real` (pós-jogo) discordam sobre um jogador, as duas
    sobrevivem — uma por jogador — e o time aparece com 12 ou 13 "titulares". Medido sobre 2026:
    92 lados fora de 11 sem o filtro, contra 34 com ele. Os 34 que sobram são falha de coleta, não
    artefato de dedup, e caem no `cobertura`.

    ────────────────────────────────────────────────────────────────────────────────
    O UNIVERSO. Os times são os do universo congelado da [F] (a mesma macro do resto da task), e
    os jogos são os que a célula `escopo` teria para emprestar: mesma temporada das âncoras,
    kickoff antes do teto congelado, encerrados em `FT` — o mesmo filtro do
    `int_futebol_team_form_pit`, para o elenco medido ser o dos jogos que de fato entram na média.

    QUATRO NÍVEIS NA MESMA SAÍDA, com a coluna `nivel` separando os grãos:

      cobertura       por (competição, escopo). `escopo = pool` são os lados que esta medição usa;
                      `escopo = temporada` são TODOS os lados encerrados da temporada dentro do
                      teto, e é ali que a afirmação de cobertura do ticket é conferida.
      total           por estrato, todos os times juntos. É a linha do veredito.
      estrato_x_dias  por (estrato, faixa de dias entre os dois jogos). O controle do calendário.
      time            por (time, estrato), só para os times que TÊM par liga↔copa — são os times
                      sobre os quais a pergunta do ticket existe. Quantos ficaram de fora por não
                      ter nenhum sai na linha `total`, em `times_sem_par_liga_copa`.

    Somar linhas de níveis diferentes conta o mesmo par mais de uma vez — filtre `nivel` sempre.

    COMO RODAR (do dbt_futebol/):

      # uma vez, se dim_leagues/dim_teams ainda não estiverem no dataset de medição
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt run --target taskF \
        --select dim_leagues stg_futebol_leagues dim_teams stg_futebol_teams

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_rodizio_de_elenco
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_rodizio_de_elenco.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set faixas_de_dias = [
    ('ate_3',     'dias_entre <= 3'),
    ('4_a_5',     'dias_entre BETWEEN 4 AND 5'),
    ('6_a_7',     'dias_entre BETWEEN 6 AND 7'),
    ('8_ou_mais', 'dias_entre >= 8')
] -%}

WITH {{ task01_base() }},

apostas_congeladas AS (
    SELECT * FROM apostas
    WHERE {{ taskf_universo_filtro() }}
),

universo AS (
    SELECT DISTINCT fixture_id FROM apostas_congeladas
),

fixtures AS (
    SELECT
        fixture_id, competition, competition_id, season, kickoff_utc,
        status_short, home_team_id, away_team_id, goals_home, goals_away
    FROM {{ ref('fact_fixtures') }}
),

tipo_competicao AS (
    SELECT DISTINCT league_id AS competition_id, league_type
    FROM {{ ref('dim_leagues') }}
),

{# Os times do universo congelado, e a temporada deles — as duas coisas que amarram esta medição
   ao mesmo recorte do resto da [F]. -#}
times_do_universo AS (
    SELECT DISTINCT lado AS team_id, f.season
    FROM fixtures AS f
    JOIN universo USING (fixture_id)
    CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
),

{# O pool: os jogos que a célula `escopo` teria para emprestar. Mesmo filtro de encerramento do
   int_futebol_team_form_pit (`FT`), porque o elenco que interessa é o dos jogos que entram na
   média — jogo decidido na prorrogação ou nos pênaltis não entra em histórico nenhum hoje
   (issue #71) e por isso também não entra aqui. -#}
pool AS (
    SELECT
        t.team_id,
        f.fixture_id,
        f.competition,
        f.kickoff_utc,
        tc.league_type
    FROM times_do_universo AS t
    JOIN fixtures AS f
      ON  f.season = t.season
      AND t.team_id IN (f.home_team_id, f.away_team_id)
    JOIN tipo_competicao AS tc
      ON tc.competition_id = f.competition_id
    WHERE f.status_short = 'FT'
      AND f.goals_home IS NOT NULL
      AND f.goals_away IS NOT NULL
      AND f.kickoff_utc < TIMESTAMP('{{ taskf_universo().teto_utc }}')
),

{# O XI titular. Ver o cabeçalho para a fase `real`: sem ela o dedup por jogador deixa passar
   time com 12 e 13 titulares. -#}
xi AS (
    SELECT
        fixture_id,
        team_id,
        ARRAY_AGG(player_id) AS jogadores,
        COUNT(*)             AS n_titulares
    FROM {{ ref('fact_fixture_lineups_players') }}
    WHERE is_starter
      AND lineup_phase = 'real'
    GROUP BY fixture_id, team_id
),

{# Todos os lados encerrados da temporada dentro do teto, INCLUSIVE os de times que não estão no
   universo — é o escopo em que a afirmação do ticket ("cobertura de 100% em todas as
   competições") pode ser conferida. O pool sozinho não a falsificaria: ele só tem os times do
   universo, e o adversário de Série C das fases iniciais da Copa do Brasil, que é justamente
   quem não tem escalação coletada, não está lá. -#}
lados_da_temporada AS (
    SELECT f.fixture_id, f.competition, lado AS team_id
    FROM fixtures AS f
    CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
    WHERE f.status_short = 'FT'
      AND f.goals_home IS NOT NULL
      AND f.goals_away IS NOT NULL
      AND f.kickoff_utc < TIMESTAMP('{{ taskf_universo().teto_utc }}')
      AND f.season IN (SELECT DISTINCT season FROM times_do_universo)
),

{%- set metricas_de_cobertura %}
        COUNT(*)                                                  AS lados,
        COUNTIF(x.n_titulares = 11)                               AS lados_com_xi,
        COUNTIF(x.fixture_id IS NULL)                             AS lados_sem_lineup,
        COUNTIF(x.fixture_id IS NOT NULL AND x.n_titulares != 11) AS lados_xi_incompleto
{%- endset %}

cobertura AS (
    SELECT
        p.competition,
        'pool' AS escopo,
        {{ metricas_de_cobertura }}
    FROM pool AS p
    LEFT JOIN xi AS x
           ON  x.fixture_id = p.fixture_id
          AND  x.team_id    = p.team_id
    GROUP BY p.competition

    UNION ALL

    SELECT
        p.competition,
        'temporada',
        {{ metricas_de_cobertura }}
    FROM lados_da_temporada AS p
    LEFT JOIN xi AS x
           ON  x.fixture_id = p.fixture_id
          AND  x.team_id    = p.team_id
    GROUP BY p.competition
),

{# Cada jogo olha para o ANTERIOR do mesmo time. O par se forma sobre o pool INTEIRO, e não só
   sobre os jogos com XI utilizável: parear pulando o jogo sem escalação criaria par entre jogos
   distantes com cara de consecutivos. O par sem XI dos dois lados é contado e descartado. -#}
sequencia AS (
    SELECT
        team_id,
        fixture_id,
        kickoff_utc,
        league_type,
        LAG(fixture_id)  OVER (PARTITION BY team_id ORDER BY kickoff_utc) AS fixture_anterior,
        LAG(kickoff_utc) OVER (PARTITION BY team_id ORDER BY kickoff_utc) AS kickoff_anterior,
        LAG(league_type) OVER (PARTITION BY team_id ORDER BY kickoff_utc) AS tipo_anterior
    FROM pool
),

pares AS (
    SELECT
        s.team_id,
        CASE
            WHEN s.league_type = 'League' AND s.tipo_anterior = 'League' THEN 'liga_liga'
            WHEN s.league_type = 'Cup'    AND s.tipo_anterior = 'Cup'    THEN 'copa_copa'
            ELSE                                                             'liga_copa'
        END                                                       AS estrato,
        TIMESTAMP_DIFF(s.kickoff_utc, s.kickoff_anterior, DAY)    AS dias_entre,
        xa.n_titulares = 11 AND xb.n_titulares = 11               AS utilizavel,
        (SELECT COUNT(*) FROM UNNEST(xa.jogadores) AS j
          WHERE j IN UNNEST(xb.jogadores))                        AS sobreposicao
    FROM sequencia AS s
    LEFT JOIN xi AS xa
           ON  xa.fixture_id = s.fixture_id
          AND  xa.team_id    = s.team_id
    LEFT JOIN xi AS xb
           ON  xb.fixture_id = s.fixture_anterior
          AND  xb.team_id    = s.team_id
    WHERE s.fixture_anterior IS NOT NULL
),

{# A lista de métricas existe UMA vez e é renderizada nos três níveis que compartilham o grão de
   par. `pares_descartados` fica ao lado de `pares` de propósito: um estrato cuja cobertura de
   escalação é ruim tem de mostrar isso na mesma linha em que mostra a média. -#}
{%- set metricas_de_par %}
        COUNT(*)                                                        AS pares_no_estrato,
        COUNTIF(utilizavel)                                             AS pares,
        COUNTIF(NOT utilizavel)                                         AS pares_descartados,
        COUNT(DISTINCT IF(utilizavel, team_id, NULL))                   AS times,
        ROUND(AVG(IF(utilizavel, sobreposicao, NULL)), 2)               AS sobreposicao_media,
        ROUND(AVG(IF(utilizavel, sobreposicao, NULL)) / 11 * 100, 1)    AS pct_sobreposicao,
        {{ taskf_mediana('IF(utilizavel, sobreposicao, NULL)', casas=0) }} AS sobreposicao_mediana,
        MIN(IF(utilizavel, sobreposicao, NULL))                         AS sobreposicao_min,
        ROUND(AVG(IF(utilizavel, dias_entre, NULL)), 1)                 AS dias_entre_medio
{%- endset %}

por_estrato AS (
    SELECT estrato, {{ metricas_de_par }}
    FROM pares
    GROUP BY estrato
),

por_estrato_dias AS (
    SELECT
        estrato,
        CASE
        {%- for nome, predicado in faixas_de_dias %}
            WHEN {{ predicado }} THEN '{{ nome }}'
        {%- endfor %}
        END AS faixa_de_dias,
        {{ metricas_de_par }}
    FROM pares
    GROUP BY estrato, faixa_de_dias
),

{# Só os times que TÊM par liga↔copa: são aqueles sobre os quais a pergunta do ticket existe.
   Quem não tem nenhum não é um time sem rodízio, é um time que não joga as duas coisas — e
   misturar os dois casos numa média por time responderia outra pergunta. -#}
times_com_par_misto AS (
    SELECT DISTINCT team_id
    FROM pares
    WHERE estrato = 'liga_copa' AND utilizavel
),

por_time AS (
    SELECT p.team_id, p.estrato, {{ metricas_de_par }}
    FROM pares AS p
    JOIN times_com_par_misto USING (team_id)
    GROUP BY p.team_id, p.estrato
),

empilhado AS (
    SELECT
        'cobertura'           AS nivel,
        0                     AS nivel_ord,
        competition           AS chave,
        escopo                AS chave2,
        lados,
        lados_com_xi,
        lados_sem_lineup,
        lados_xi_incompleto,
        ROUND(SAFE_DIVIDE(lados_com_xi, lados) * 100, 1) AS pct_com_xi,
        CAST(NULL AS INT64)   AS pares_no_estrato,
        CAST(NULL AS INT64)   AS pares,
        CAST(NULL AS INT64)   AS pares_descartados,
        CAST(NULL AS INT64)   AS times,
        CAST(NULL AS FLOAT64) AS sobreposicao_media,
        CAST(NULL AS FLOAT64) AS pct_sobreposicao,
        CAST(NULL AS INT64)   AS sobreposicao_mediana,
        CAST(NULL AS INT64)   AS sobreposicao_min,
        CAST(NULL AS FLOAT64) AS dias_entre_medio,
        CAST(NULL AS INT64)   AS times_sem_par_liga_copa
    FROM cobertura

    UNION ALL

    SELECT
        'total', 1, estrato, CAST(NULL AS STRING),
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        pares_no_estrato, pares, pares_descartados, times,
        sobreposicao_media, pct_sobreposicao, sobreposicao_mediana, sobreposicao_min,
        dias_entre_medio,
        (SELECT COUNT(DISTINCT team_id) FROM pares
          WHERE team_id NOT IN (SELECT team_id FROM times_com_par_misto))
    FROM por_estrato

    UNION ALL

    SELECT
        'estrato_x_dias', 2, estrato, faixa_de_dias,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        pares_no_estrato, pares, pares_descartados, times,
        sobreposicao_media, pct_sobreposicao, sobreposicao_mediana, sobreposicao_min,
        dias_entre_medio,
        CAST(NULL AS INT64)
    FROM por_estrato_dias

    UNION ALL

    SELECT
        'time', 3, COALESCE(t.team_name, FORMAT('team_id=%d', p.team_id)), p.estrato,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS FLOAT64),
        p.pares_no_estrato, p.pares, p.pares_descartados, p.times,
        p.sobreposicao_media, p.pct_sobreposicao, p.sobreposicao_mediana, p.sobreposicao_min,
        p.dias_entre_medio,
        CAST(NULL AS INT64)
    FROM por_time AS p
    LEFT JOIN {{ ref('dim_teams') }} AS t USING (team_id)
)

SELECT *
FROM empilhado
ORDER BY nivel_ord, chave, chave2
