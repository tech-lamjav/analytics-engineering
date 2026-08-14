{#
    [F-7] A TABELA DE DIAGNÓSTICO DE 180 DIAS DO TICKET, reproduzida da nossa base.

    O ticket de origem (ClickUp `wdx6zevnhy`, transcrito na issue #49) abre com uma tabela de
    quatro linhas — Copa do Brasil, Sudamericana, Copa do Mundo e Champions — e é dela que sai a
    tese inteira: "a escassez é artefato de escopo". Tudo o que as quatro células mediram depois
    se apoia nessa leitura. Se os 25,5 jogos da Copa do Brasil não saem da nossa base, nada do
    que veio depois merece crédito; se saem, o autor tem motivo para confiar no resto dos números.

    Esta análise NÃO LÊ CÉLULA NENHUMA — nem `int_futebol_team_form_pit`, nem a camada de
    premissas, nem `task01_base()`. Ela desce até `fact_fixtures` e reconstrói a contagem de
    partidas anteriores por conta própria, e isso é critério de aceite (#56): a reconciliação
    existe para conferir a máquina, e uma conferência que passasse pela máquina conferida não
    conferiria coisa alguma. A duplicação do idioma `team_log` é deliberada.

    ⚠️ AS DUAS COLUNAS DO TICKET NÃO CONTAM O MESMO TRECHO DO PASSADO — e é isso que explica a
    linha da Champions. "Jogos na própria competição" conta o histórico INTEIRO do time naquela
    competição, todas as temporadas, sem limite de tempo; "Jogos em tudo, 180 dias" conta todas as
    competições mas só nos 180 dias anteriores ao jogo. Sob um recorte comum, `tudo` ⊇ `própria` e
    a segunda coluna nunca poderia ser MENOR que a primeira — mas a Champions aparece com 4,0 e
    1,0. Não é erro de medição do autor nem falha de reprodução nossa: são dois recortes
    diferentes, e a inversão é a assinatura disso. A leitura que o ticket tira dali ("é pior do
    que a conta por competição sugere") continua de pé pelo lado do 1,0, que é real; o que não se
    sustenta é comparar os dois números entre si.

    A UNIDADE É O PAR (jogo, time), não o time distinto. O cabeçalho do ticket diz "times com < 5
    jogos", mas um time entra na conta uma vez por jogo que disputa, e é assim que a reprodução
    fecha. A variante `F` mede o outro jeito, e lá só 5 dos 16 campos continuam batendo.

    AS ÂNCORAS SÃO SÓ OS JOGOS ENCERRADOS do corte congelado. O ticket diz "contando só partidas
    encerradas" a respeito do que é contado; aplicar a mesma régua ao jogo-âncora é o que faz a
    Copa do Mundo sair 2,0/96% em vez de 2,1/94% — os 9 jogos de mata-mata decididos na
    prorrogação ou nos pênaltis ficam de fora por não terem `status_short = 'FT'`.

    O CORTE DE TEMPO DAS ÂNCORAS É O UNIVERSO CONGELADO (`taskf_universo()`), e o teto de 04/08
    12:00 UTC reproduz o instante em que o autor rodou: o ticket foi aberto às 22:52 UTC daquele
    dia, e entre ~02:00 e 16:00 UTC não há jogo nenhum na base — qualquer instante do vão devolve
    o mesmo conjunto. É o mesmo argumento de "instante, não dia" que a macro do universo já faz.

    ⚠️ Mas aqui o corte é aplicado a `fact_fixtures`, e NÃO ao universo de 169 jogos das células.
    São dois conjuntos diferentes de propósito: as células medem jogo liquidado COM preço nos 5
    mercados do Motor, e a Champions não tem um único jogo lá dentro (a #51 mediu isso). A tabela
    do ticket é sobre jogos, não sobre apostas — por isso a Champions aparece nesta análise e não
    nas células, e por isso o `jogos_esperados = 169` da macro não se aplica a nada aqui.

    AS SETE VARIANTES, e o que cada uma troca. Cada uma mexe em UMA coisa em relação à `A`, para
    que a diferença que ela produzir seja atribuível — é a mesma disciplina das variantes do
    taskf_universo_congelado.sql. Uma variante que mexesse em duas mediria a soma dos dois efeitos
    e não serviria de falsificação de nenhum dos dois:

      A_ticket                        a receita acima. É a que reproduz.
      B_fronteira_estrita_por_data    a fronteira dos 180 dias em data e ESTRITA (`>`). A única
                                      divergência da tabela inteira mora aqui.
      C_fronteira_inclusiva_por_data  a fronteira em data e INCLUSIVA (`>=`). Existe para provar
                                      que a granularidade não é a alavanca: `C` devolve os mesmos
                                      números da `A`, campo a campo. O que exclui a partida da
                                      fronteira é a ESTRITEZA da `B`, não o fato de ser data.
      D_ancoras_com_pen_aet           AET e PEN entram como ÂNCORA, e só como âncora. Falsifica o
                                      terceiro pedaço da receita: é o que a Copa do Mundo vira se
                                      o jogo-âncora não precisar ser `FT`.
      E_historico_com_pen_aet         AET e PEN entram no HISTÓRICO, e só nele. Mede o tamanho do
                                      que o `team_log` de todo o pipeline joga fora ao filtrar
                                      `status_short = 'FT'` — jogo decidido nos pênaltis não é
                                      `FT`, e nas copas de mata-mata isso não é resíduo.
      F_como_o_pit_conta              a contagem que o PIT de produção realmente faz: mesma
                                      competição E mesma temporada de um lado, todas as
                                      competições da mesma temporada do outro. É a ponte entre
                                      esta reconciliação e as células — mostra que a coluna 1 do
                                      ticket não é o que produção conta.
      G_por_time_distinto             a contagem da `A` com o time distinto no lugar do par
                                      (jogo, time). A unidade é um dos quatro pedaços da receita,
                                      e pedaço não medido é pedaço afirmado.

    A leitura literal de "partidas encerradas" — AET e PEN dos DOIS lados ao mesmo tempo — é a
    composição de `D` com `E`, e não tem variante própria justamente porque mexeria em duas coisas.

    Só a `A` tem gabarito para bater. As outras seis são medidas contra o MESMO gabarito de
    propósito: a divergência delas é o número que explica por que a receita é a que é.

    A partida que produz a única divergência sai nomeada em analyses/taskf_partida_da_fronteira.sql.

    Rodar com (o target é indiferente — `fact_fixtures` é a mesma tabela de produção nos dois, e
    esta análise não lê nada do dataset de medição):

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target dev --select taskf_reconciliacao_180d
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_reconciliacao_180d.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)
#}

WITH lados AS (
    -- Um par (jogo, time) por lado de cada jogo. Serve de âncora e de histórico ao mesmo tempo:
    -- o que separa um do outro é o predicado de tempo lá embaixo, não a origem.
    SELECT fixture_id, competition, competition_id, season, kickoff_utc, status_short,
           home_team_id AS team_id
    FROM {{ ref('fact_fixtures') }}
    UNION ALL
    SELECT fixture_id, competition, competition_id, season, kickoff_utc, status_short,
           away_team_id
    FROM {{ ref('fact_fixtures') }}
),

ancoras AS (
    SELECT 'A_ticket'                       AS variante, l.* FROM lados l
    WHERE {{ taskf_universo_filtro('l.') }} AND l.status_short = 'FT'
    UNION ALL
    SELECT 'B_fronteira_estrita_por_data',   l.* FROM lados l
    WHERE {{ taskf_universo_filtro('l.') }} AND l.status_short = 'FT'
    UNION ALL
    SELECT 'C_fronteira_inclusiva_por_data', l.* FROM lados l
    WHERE {{ taskf_universo_filtro('l.') }} AND l.status_short = 'FT'
    UNION ALL
    SELECT 'D_ancoras_com_pen_aet',          l.* FROM lados l
    WHERE {{ taskf_universo_filtro('l.') }} AND l.status_short IN ('FT', 'AET', 'PEN')
    UNION ALL
    SELECT 'E_historico_com_pen_aet',        l.* FROM lados l
    WHERE {{ taskf_universo_filtro('l.') }} AND l.status_short = 'FT'
    UNION ALL
    SELECT 'F_como_o_pit_conta',             l.* FROM lados l
    WHERE {{ taskf_universo_filtro('l.') }} AND l.status_short = 'FT'
),

pares AS (
    SELECT
        a.variante,
        a.competition,
        a.fixture_id,
        a.team_id,

        -- COLUNA 1 DO TICKET — "jogos na própria competição". Sem limite de tempo e sem limite de
        -- temporada em todas as variantes menos a F, que é como o PIT conta.
        COUNTIF(
            l.competition_id = a.competition_id
            AND (a.variante != 'F_como_o_pit_conta' OR l.season = a.season)
        ) AS propria,

        -- COLUNA 2 DO TICKET — "jogos em tudo, 180 dias". Qualquer competição do time. A
        -- fronteira dos 180 dias é o que separa A, B e C; na F não há fronteira de dias, e sim a
        -- temporada corrente, porque é essa a contagem que a célula `escopo` usa.
        COUNTIF(
            CASE a.variante
                WHEN 'B_fronteira_estrita_por_data' THEN
                    DATE(l.kickoff_utc) >  DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY)
                WHEN 'C_fronteira_inclusiva_por_data' THEN
                    DATE(l.kickoff_utc) >= DATE_SUB(DATE(a.kickoff_utc), INTERVAL 180 DAY)
                WHEN 'F_como_o_pit_conta' THEN
                    l.season = a.season
                ELSE
                    l.kickoff_utc >= TIMESTAMP_SUB(a.kickoff_utc, INTERVAL 180 DAY)
            END
        ) AS tudo

    FROM ancoras a
    LEFT JOIN lados l
        ON  l.team_id     = a.team_id
        AND l.kickoff_utc < a.kickoff_utc
        -- O histórico é `FT` em todas as variantes menos a E, onde AET e PEN entram — e entram
        -- SÓ aqui: a régua da âncora é outra linha, na CTE acima, e é a D que a solta.
        AND (l.status_short = 'FT'
             OR (a.variante = 'E_historico_com_pen_aet' AND l.status_short IN ('AET', 'PEN')))
    GROUP BY 1, 2, 3, 4
),

-- A variante G: a MESMA contagem da A, com a unidade trocada. Um time que joga três vezes no
-- corte entra uma vez só, com a média das suas três contagens.
por_time AS (
    SELECT p.competition, p.team_id,
           AVG(p.propria) AS propria,
           AVG(p.tudo)    AS tudo
    FROM pares p
    WHERE p.variante = 'A_ticket'
    GROUP BY 1, 2
),
jogos_ancora AS (
    SELECT competition, COUNT(DISTINCT fixture_id) AS jogos
    FROM pares
    WHERE variante = 'A_ticket'
    GROUP BY 1
),

-- O GABARITO: os 16 números publicados no ticket, digitados. Ficam aqui, e não na prosa do doc,
-- para a divergência ser alta — quem rodar a análise vê o delta, não precisa conferir de olho.
gabarito AS (
    SELECT * FROM UNNEST([
        STRUCT('copa_do_brasil'   AS competition, 10.2 AS propria_tkt, 25.5 AS tudo_tkt,
                                    19 AS p5_propria_tkt, 0 AS p5_tudo_tkt),
               ('sudamericana',     8.9, 12.5, 27,   0),
               ('copa_mundo',       2.0,  2.0, 96,  96),
               ('champions_league', 4.0,  1.0, 69, 100)
    ])
),

medido AS (
    SELECT
        p.variante,
        p.competition,
        COUNT(DISTINCT p.fixture_id)                        AS jogos,
        COUNT(*)                                            AS unidades,
        ROUND(AVG(p.propria), 1)                            AS propria,
        ROUND(AVG(p.tudo), 1)                               AS tudo,
        ROUND(100 * COUNTIF(p.propria < 5) / COUNT(*))      AS p5_propria,
        ROUND(100 * COUNTIF(p.tudo    < 5) / COUNT(*))      AS p5_tudo,
        -- As somas brutas saem junto porque são elas que tornam o resíduo legível: um delta de
        -- 0,1 numa média de 16 pares é UMA partida a mais ou a menos, e a média arredondada não
        -- deixa isso aparecer.
        SUM(p.propria)                                      AS soma_propria,
        SUM(p.tudo)                                         AS soma_tudo
    FROM pares p
    GROUP BY 1, 2

    UNION ALL

    SELECT
        'G_por_time_distinto',
        t.competition,
        j.jogos,
        COUNT(*),
        ROUND(AVG(t.propria), 1),
        ROUND(AVG(t.tudo), 1),
        ROUND(100 * COUNTIF(t.propria < 5) / COUNT(*)),
        ROUND(100 * COUNTIF(t.tudo    < 5) / COUNT(*)),
        -- Soma bruta não existe nesta unidade: somar média de time não conta partida nenhuma.
        CAST(NULL AS INT64),
        CAST(NULL AS INT64)
    FROM por_time t
    JOIN jogos_ancora j USING (competition)
    GROUP BY 1, 2, 3
)

SELECT
    m.variante,
    m.competition                          AS competicao,
    m.jogos,
    -- O denominador da variante: par (jogo, time) em A–F, time distinto na G.
    m.unidades,

    m.propria,      g.propria_tkt,    ROUND(m.propria - g.propria_tkt, 1)  AS d_propria,
    m.tudo,         g.tudo_tkt,       ROUND(m.tudo    - g.tudo_tkt,    1)  AS d_tudo,
    m.p5_propria,   g.p5_propria_tkt, m.p5_propria - g.p5_propria_tkt      AS d_p5_propria,
    m.p5_tudo,      g.p5_tudo_tkt,    m.p5_tudo    - g.p5_tudo_tkt         AS d_p5_tudo,

    m.soma_propria,
    m.soma_tudo,

    -- Quantos dos quatro campos da linha bateram. A tolerância é meia casa da última casa
    -- publicada — não é folga para acomodar divergência, é o que separa igualdade de ruído de
    -- ponto flutuante depois do ROUND.
    CAST(ABS(m.propria    - g.propria_tkt)    < 0.05 AS INT64)
  + CAST(ABS(m.tudo       - g.tudo_tkt)       < 0.05 AS INT64)
  + CAST(ABS(m.p5_propria - g.p5_propria_tkt) < 0.5  AS INT64)
  + CAST(ABS(m.p5_tudo    - g.p5_tudo_tkt)    < 0.5  AS INT64) AS campos_exatos

FROM medido m
JOIN gabarito g USING (competition)
ORDER BY m.variante, m.unidades DESC
