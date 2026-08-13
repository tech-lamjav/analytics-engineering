/*
    [F-8] FORÇA DO ADVERSÁRIO — o primeiro dos dois confundidores do merge, medido em vez de
    registrado.

    O QUE ELE AMEAÇA. A célula `escopo` aumenta a amostra emprestando ao histórico de um time as
    partidas que ele jogou em OUTRA competição da mesma temporada. Se essas partidas emprestadas
    forem contra adversários de nível diferente, o ganho de amostra vem junto com um viés de
    nível: a média que decide se a aposta é boa passa a misturar jogo de Brasileirão com jogo de
    fase inicial de Copa do Brasil, e a premissa acende por um passado que descreve outro
    campeonato. É o confundidor que o ticket de origem não menciona e que a spec #49 acrescentou
    (user stories 21 e 22).

    O QUE ESTA ANÁLISE MEDE, e onde:

      (a) de ONDE vem cada partida emprestada — a competição de origem, por competição-âncora;
      (b) QUEM era o adversário naquela partida, em quatro categorias EXCLUDENTES e sem imputação:
          `na_base_com_ppg`, `na_base_sem_ppg`, `fora_da_base` e `selecao`;
      (c) o `ppg` PIT do adversário quando ele existe, nativo contra emprestado, e ao lado dele o
          `ppg` de LIGA do mesmo adversário — o mesmo número na mesma unidade, seja qual for a
          competição da partida;
      (d) a LIGA a que o adversário pertence, que é a única medida de nível que a base permite;
      (e) os gols pró/contra do próprio time nas duas origens — o canal por onde o viés chega às
          médias que as premissas leem.

    ⚠️ O QUE `ppg` ALCANÇA, E O QUE NÃO — E O `ppg_referencia` EXISTE PARA ISSO SER CONFERIDO, NÃO
    ACREDITADO. `ppg` é pontos por jogo DENTRO da competição. Numa competição de PONTOS CORRIDOS a
    média dele é quase constante por construção (o campeonato distribui 3 pontos por jogo decidido
    e 2 por empate), e medido é isso mesmo: 1,364 no Brasileirão e 1,333 na Série B. Ali `ppg` mede
    posição RELATIVA — se o adversário é de cima ou de baixo da tabela DELE — e é cego a diferença
    de NÍVEL entre competições.

    Em competição de MATA-MATA ele não mede nem isso. Quem perde é eliminado e para de jogar, então
    a população que chega à rodada seguinte é a dos que venceram: a média de `ppg` da Copa do Brasil
    é **2,609**, contra 1,438 da Libertadores (que tem fase de grupos e por isso volta a se
    comportar como liga). `ppg` alto numa copa de mata-mata é sobrevivência, não força. Comparar
    `ppg` de copa com `ppg` de liga como se fossem a mesma régua é o erro que esta análise existe
    para não cometer — o nível sai da COMPOSIÇÃO (de qual competição a partida veio, `nivel =
    'fonte'`) e do tamanho das categorias sem número, nunca do `ppg_medio` sozinho.

    ⚠️ `fora_da_base` NÃO É IMPUTADO. Um time está na base quando alguma competição de PONTOS
    CORRIDOS da coleta o alcança (`dim_leagues.league_type = 'League'`, derivado do dado e não de
    uma lista digitada). Não coletamos Série C nem D, então o adversário das fases iniciais da
    Copa do Brasil é invisível — e a medição mostrou que o buraco é maior do que a spec supôs: o
    clube sul-americano de Libertadores e de Sudamericana também está fora, porque não coletamos as
    ligas nacionais dele. Não há `ppg` de nenhum dos dois em lugar nenhum, e inventar um — média da
    competição, percentil, o que for — trocaria o achado por um número. A categoria fica explícita
    e o tamanho dela é o resultado.

    As outras duas categorias sem `ppg` são OUTRAS COISAS, e por isso não se juntam à primeira:

      `na_base_sem_ppg`  o adversário existe na base, mas naquele instante ainda não tinha partida
                         anterior na competição daquele jogo (rodada 1), então o PIT dele é NULL
                         por degradação graciosa. É ausência de passado, não ausência de coleta.
      `selecao`          adversário de Copa do Mundo. Seleção não tem liga a coletar — a ausência
                         é o formato do futebol de seleções, não um limite nosso.

    ⚠️ E É POR ISSO QUE EXISTE O NÍVEL `liga_do_adversario`, QUE É ONDE A RESPOSTA MORA. Nenhum
    `ppg` enxerga NÍVEL: o do PIT é relativo à competição da partida, e o `ppg_liga_medio` é
    relativo à liga do adversário — um time de Série B com 1,40 não vale o mesmo que um de Série A
    com 1,40. O que é observável sem inventar rating é a LIGA a que o adversário pertence, e é
    exatamente a variável do medo da spec ("emprestar jogos de uma competição mais forte para
    outra mais fraca"). Esse nível conta quantas partidas de cada origem foram contra time de cada
    liga, e o `gols_pro_medio`/`gols_contra_medio` ao lado mostra o que aquilo faz com a média que
    as premissas leem.

    ────────────────────────────────────────────────────────────────────────────────
    SEIS NÍVEIS NA MESMA SAÍDA, com a coluna `nivel` separando os grãos. Somar linhas de níveis
    diferentes conta a mesma partida mais de uma vez — filtre `nivel` sempre.

      conferencia         1 linha. A reconstrução aqui bate com o que o MODELO gravou?
      total               por `origem`, o universo inteiro.
      competicao          por (competição-âncora, `origem`).
      fonte               por (competição-âncora, competição da partida emprestada). Só emprestadas.
      liga_do_adversario  por (competição-âncora, liga do adversário, `origem`).
      ppg_referencia      por competição: a média de `ppg` de todo o PIT dela. É a régua de leitura
                          dos `ppg_medio` acima, não uma medição do universo.

    As colunas não querem dizer a mesma coisa nos seis níveis, e a legenda é esta:

      nível               chave / chave2                  partidas          adv_com_ppg
      ──────────────────  ──────────────────────────────  ────────────────  ──────────────────
      conferencia         —                               —                 —
      total               'TODAS'                         partidas do hist. adversários com ppg
      competicao          competição-âncora               idem              idem
      fonte               âncora / competição de origem   idem              idem
      liga_do_adversario  âncora / liga do adversário     idem              idem
      ppg_referencia      competição                      linhas do PIT     linhas do PIT com ppg

    `pares_batem_base`, `pares_batem_escopo` e `veredito` só existem no nível `conferencia`;
    `ppg_min`/`ppg_max` só no `ppg_referencia`. `jogos_no_universo` é o universo congelado inteiro
    na `conferencia` (o gabarito) e, nos demais níveis, as âncoras que têm pelo menos uma partida
    naquele estrato — os dois números diferem, e é assim que se enxerga quanto do universo o
    estrato alcança.

    ⚠️ O RÓTULO `fora_da_base` DO NÍVEL `liga_do_adversario` NÃO É A MESMA CONTAGEM DA COLUNA
    `adv_fora_da_base`, e a diferença é informação. A coluna é por BASE INTEIRA (o time tem liga
    em alguma temporada?); o rótulo é por TEMPORADA (o time tem liga NAQUELA temporada?). Medido:
    583 partidas com o rótulo contra 573 na coluna — 10 em 4.021, e são adversários que têm liga
    na base mas não em 2026. São 40 times nessa situação, quase todos rebaixados ou promovidos
    entre o backfill de 24/25 e agora (Amazonas, Brusque, Ferroviária, Burnley, Empoli...).

    ⚠️ POR QUE HÁ UMA CONFERÊNCIA, E POR QUE ELA É A PRIMEIRA LINHA. Esta análise RECONSTRÓI o
    join de histórico do int_futebol_team_form_pit em vez de ler um agregado pronto — precisa da
    partida individual, e o carimbo guarda só a contagem. Reconstrução é cópia, e cópia deriva do
    original em silêncio: bastaria esquecer o `l.season = a.season` para o número sair maior e com
    cara de certo. Então a reconstrução é cobrada contra o carimbo das células (`base` e `escopo`,
    #53), par a par: as partidas `nativa` têm de ser exatamente o `played_total` da `base`, e o
    total (nativa + emprestada) exatamente o da `escopo`. Se a linha `conferencia` não sair
    `EXATA`, nada abaixo dela significa o que diz.

    ⚠️ ESTA ANÁLISE NÃO DEPENDE DA CÉLULA MATERIALIZADA, e isso é escolha, não sorte. Ela lê três
    coisas do dataset: o UNIVERSO (invariante entre células — é a primeira invariante da Costura
    B, #55), o `ppg` do PIT (invariante por construção — a tabela do campeonato é sempre
    competição+temporada, ADR 0008; medido: 1.916 de 1.916 pares idênticos entre a produção e a
    célula `ambos`) e o CARIMBO, que tem as quatro células gravadas lado a lado. O `jogos_no_universo`
    sai na saída para ser conferido contra os {{ taskf_universo().jogos_esperados }} do gabarito.

    COMO RODAR (do dbt_futebol/), com o carimbo das células `base` e `escopo` já gravado:

      # dim_leagues e dim_teams não estavam no dataset de medição — a ancestria das células não
      # passa por elas. Uma vez só, e sem risco de tocar célula: nenhum dos seis nós de premissas
      # as referencia.
      DBT_PROFILES_DIR=.. ../.venv/bin/dbt run --target taskF \
        --select dim_leagues stg_futebol_leagues dim_teams stg_futebol_teams

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_forca_do_adversario
      bq query --use_legacy_sql=false --max_rows=100000 --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_forca_do_adversario.sql

    ⚠️ DUAS ARMADILHAS DO `bq query`, as duas silenciosas. O SQL como ARGUMENTO trava nesta
    máquina (sempre por redirecionamento). E o `--max_rows` PRECISA estar lá: o default é 100
    linhas e ele TRUNCA sem avisar — a saída sai com cara de completa, e a linha que falta é
    exatamente a do fim da ordenação. Custou uma contagem errada de times durante a própria #57.

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{#- O carimbo é lido por `source()`, como todo o resto do dataset de medição. Só a ESCRITA dele
    (analyses/taskf_pit_por_celula.sql) é literal, e por um motivo específico da ADR 0007 — o
    destino não pode seguir o `--target`. -#}
{%- set carimbos = source('futebol_taskF', 'taskf_pit_por_celula') -%}

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

{#- Tipo da competição, DERIVADO do catálogo e não de uma lista de slugs digitada: a Onda 2
    acrescentou cinco ligas em três semanas, e uma lista digitada envelheceria calada — a liga
    nova cairia no lado errado da fronteira liga/copa e o número sairia com cara de certo. Grão
    (league_id): `dim_leagues` tem uma linha por (league_id, season_year) e o tipo não muda entre
    temporadas. -#}
tipo_competicao AS (
    SELECT DISTINCT league_id AS competition_id, league_type
    FROM {{ ref('dim_leagues') }}
),

{#- NA BASE = alcançado por alguma competição de pontos corridos da coleta. É a definição de
    "temos como saber quanto esse time vale": um time de Série C aparece na nossa base APENAS
    pelos jogos de Copa do Brasil dele, e ali o passado que existe é o da própria copa. -#}
times_na_base AS (
    SELECT DISTINCT lados.team_id
    FROM (
        SELECT home_team_id AS team_id, competition_id FROM fixtures
        UNION ALL
        SELECT away_team_id,            competition_id FROM fixtures
    ) AS lados
    JOIN tipo_competicao AS t
      ON  t.competition_id = lados.competition_id
     AND  t.league_type    = 'League'
),

{#- Mesmo `team_log` do int_futebol_team_form_pit — 1 linha por (time, jogo encerrado), agora com
    o adversário ao lado. O filtro é o do modelo, `status_short = 'FT'`: jogo decidido na
    prorrogação ou nos pênaltis não entra no histórico de ninguém hoje (issue #71), e reproduzir
    o modelo é o ponto. -#}
team_log AS (
    SELECT competition_id, competition, season, kickoff_utc, fixture_id,
           home_team_id AS team_id, away_team_id AS oponente_id,
           goals_home   AS gf,      goals_away   AS ga
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
    UNION ALL
    SELECT competition_id, competition, season, kickoff_utc, fixture_id,
           away_team_id,            home_team_id,
           goals_away,              goals_home
    FROM fixtures
    WHERE status_short = 'FT' AND goals_home IS NOT NULL AND goals_away IS NOT NULL
),

{#- As âncoras: os dois lados de cada jogo do universo congelado. É o mesmo grão (jogo, time) do
    carimbo, e é nele que a conferência casa. -#}
ancoras AS (
    SELECT
        f.fixture_id, f.competition, f.competition_id, f.season, f.kickoff_utc,
        lado AS team_id
    FROM fixtures AS f
    JOIN universo USING (fixture_id)
    CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
),

{#- O histórico que a célula `escopo` enxerga: partidas anteriores do time na MESMA temporada, em
    QUALQUER competição. `origem` separa o que a `base` já contava do que o merge acrescenta. -#}
historico AS (
    SELECT
        a.fixture_id     AS ancora_fixture_id,
        a.competition    AS ancora_competition,
        a.team_id,
        l.fixture_id     AS hist_fixture_id,
        l.competition    AS hist_competition,
        l.kickoff_utc    AS hist_kickoff_utc,
        l.season         AS hist_season,
        l.oponente_id,
        l.gf,
        l.ga,
        IF(l.competition_id = a.competition_id, 'nativa', 'emprestada') AS origem
    FROM ancoras AS a
    JOIN team_log AS l
      ON  l.team_id     = a.team_id
      AND l.season      = a.season
      AND l.kickoff_utc < a.kickoff_utc
),

{# A LIGA a que o adversário pertence naquela temporada — a única medida de NÍVEL que esta base
   permite sem inventar um rating. Nem o `ppg` do PIT nem o `ppg` de liga enxergam nível: os dois
   são relativos ao campeonato em que foram calculados, e um time de Série B com 1,40 não vale o
   mesmo que um de Série A com 1,40. Já a liga do adversário é observável e é exatamente o que a
   spec teme ("emprestar jogos de uma competição mais forte para outra mais fraca"). Quando o
   adversário não tem liga nenhuma na coleta, o rótulo é a própria ausência. -#}
liga_do_adversario AS (
    SELECT team_id, season, liga
    FROM (
        SELECT
            lado          AS team_id,
            f.season,
            f.competition AS liga,
            COUNT(*)      AS n_jogos
        FROM fixtures AS f
        CROSS JOIN UNNEST([f.home_team_id, f.away_team_id]) AS lado
        JOIN tipo_competicao AS tc
          ON  tc.competition_id = f.competition_id
         AND  tc.league_type    = 'League'
        GROUP BY lado, f.season, f.competition
    )
    {#- Um clube joga uma liga nacional por temporada; o desempate por contagem existe só para o
        caso de a base passar a ter duas (uma liga regional, um playoff cadastrado à parte) e não
        escolher em silêncio. -#}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY team_id, season ORDER BY n_jogos DESC, liga
    ) = 1
),

{# O `ppg` DE LIGA do adversário: pontos por jogo dele em competição de PONTOS CORRIDOS, contando
   só o que já tinha acontecido quando aquela partida foi jogada.

   Existe porque o `ppg` do PIT não é comparável entre competições — numa copa de mata-mata ele é
   sobrevivência (2,609 na Copa do Brasil contra 1,364 no Brasileirão). Este aqui está sempre na
   mesma unidade, seja qual for a competição da partida, e é ele que responde de fato "o
   adversário era forte?". Ele é NULL exatamente para quem está `fora_da_base` ou é `selecao` —
   não por acaso: é a mesma ausência, agora em forma de número que falta. -#}
adv_ppg_de_liga AS (
    SELECT
        h.ancora_fixture_id,
        h.team_id,
        h.hist_fixture_id,
        SAFE_DIVIDE(
            SUM(CASE WHEN l.gf > l.ga THEN 3 WHEN l.gf = l.ga THEN 1 ELSE 0 END),
            COUNT(*)
        ) AS ppg_liga
    FROM historico AS h
    JOIN team_log AS l
      ON  l.team_id     = h.oponente_id
      AND l.season      = h.hist_season
      AND l.kickoff_utc < h.hist_kickoff_utc
    JOIN tipo_competicao AS tc
      ON  tc.competition_id = l.competition_id
     AND  tc.league_type    = 'League'
    GROUP BY h.ancora_fixture_id, h.team_id, h.hist_fixture_id
),

{#- O adversário daquela partida, classificado. O `ppg` sai do PIT do próprio jogo histórico —
    ponto no tempo de verdade, e não a tabela de hoje: é o que o adversário valia quando a
    partida foi jogada.

    A ORDEM DO `CASE` É A CLASSIFICAÇÃO. `selecao` vem primeiro porque seleção não é clube sem
    liga: ela não tem liga a coletar. Jogar as duas ausências na mesma categoria daria a impressão
    de que a Copa do Mundo tem o mesmo buraco da Copa do Brasil, e são coisas diferentes — uma é
    limite da coleta, a outra é o formato do futebol de seleções. Medido: `national = TRUE` em
    `dim_teams` é exatamente o conjunto dos 48 times que só aparecem em `copa_mundo`. -#}
historico_classificado AS (
    SELECT
        h.*,
        p.ppg      AS adv_ppg,
        pl.ppg_liga AS adv_ppg_liga,
        COALESCE(la.liga, IF(dt.national, 'selecao', 'fora_da_base')) AS adv_liga,
        CASE
            WHEN dt.national       THEN 'selecao'
            WHEN b.team_id IS NULL THEN 'fora_da_base'
            WHEN p.ppg     IS NULL THEN 'na_base_sem_ppg'
            ELSE                        'na_base_com_ppg'
        END AS categoria_adversario
    FROM historico AS h
    LEFT JOIN times_na_base AS b
           ON b.team_id = h.oponente_id
    LEFT JOIN {{ ref('dim_teams') }} AS dt
           ON dt.team_id = h.oponente_id
    LEFT JOIN {{ ref('int_futebol_team_form_pit') }} AS p
           ON  p.fixture_id = h.hist_fixture_id
          AND  p.team_id    = h.oponente_id
    LEFT JOIN adv_ppg_de_liga AS pl
           ON  pl.ancora_fixture_id = h.ancora_fixture_id
          AND  pl.team_id           = h.team_id
          AND  pl.hist_fixture_id   = h.hist_fixture_id
    LEFT JOIN liga_do_adversario AS la
           ON  la.team_id = h.oponente_id
          AND  la.season  = h.hist_season
),

-- ─────────────────────────── conferência contra o carimbo ───────────────────────────

{# LEFT JOIN de propósito: par sem NENHUMA partida anterior não aparece em `historico`, e no
    carimbo ele existe com played_total = 0. Cortá-lo aqui tiraria da conferência exatamente os
    pares que a degradação graciosa produz. -#}
contagem_reconstruida AS (
    SELECT
        a.fixture_id,
        a.team_id,
        COUNTIF(h.origem = 'nativa') AS n_nativa,
        COUNT(h.origem)              AS n_total
    FROM ancoras AS a
    LEFT JOIN historico AS h
           ON  h.ancora_fixture_id = a.fixture_id
          AND  h.team_id           = a.team_id
    GROUP BY a.fixture_id, a.team_id
),

conferencia AS (
    SELECT
        {#- O gabarito do universo congelado sai daqui, e não das linhas de histórico: um jogo
            cujos DOIS lados estreiam na temporada não tem partida anterior nenhuma e some dos
            níveis abaixo. Conferir 169 contra a contagem de histórico daria falso alarme. -#}
        (SELECT COUNT(DISTINCT fixture_id) FROM ancoras) AS jogos_no_universo,
        COUNT(*)                                  AS pares,
        COUNTIF(c.n_nativa = b.played_total)      AS pares_batem_base,
        COUNTIF(c.n_total  = e.played_total)      AS pares_batem_escopo
    FROM contagem_reconstruida AS c
    JOIN (SELECT fixture_id, team_id, played_total FROM {{ carimbos }} WHERE celula = 'base')   AS b
      USING (fixture_id, team_id)
    JOIN (SELECT fixture_id, team_id, played_total FROM {{ carimbos }} WHERE celula = 'escopo') AS e
      USING (fixture_id, team_id)
),

-- ─────────────────────────── os agregados ───────────────────────────

{# A lista de métricas existe UMA vez e é renderizada nos três níveis que compartilham o grão de
    partida. Escrita três vezes, ela derivaria — e a divergência entre um rollup e o detalhe dele
    não dá erro, dá número errado. -#}
{%- set metricas_de_partida %}
        COUNT(*)                                                             AS partidas,
        COUNT(DISTINCT FORMAT('%d-%d', ancora_fixture_id, team_id))          AS pares,
        COUNT(DISTINCT ancora_fixture_id)                                    AS jogos_no_universo,
        COUNTIF(categoria_adversario = 'na_base_com_ppg')                    AS adv_com_ppg,
        COUNTIF(categoria_adversario = 'na_base_sem_ppg')                    AS adv_sem_ppg,
        COUNTIF(categoria_adversario = 'fora_da_base')                       AS adv_fora_da_base,
        COUNTIF(categoria_adversario = 'selecao')                            AS adv_selecao,
        COUNTIF(adv_ppg_liga IS NOT NULL)                                    AS adv_com_ppg_liga,
        ROUND(AVG(adv_ppg), 3)                                               AS ppg_medio,
        {{ taskf_mediana('adv_ppg') }}                                       AS ppg_mediana,
        ROUND(AVG(adv_ppg_liga), 3)                                          AS ppg_liga_medio,
        {#- SUM/COUNT, e não AVG, pelo mesmo motivo do analyses/taskf_rodizio_de_elenco.sql: gols
            são INT64, a soma é exata e a média fica determinística. Os dois `ppg_*` acima seguem
            em AVG porque o somando já é FLOAT64 e não há soma exata a recuperar — nas três
            execuções desta análise eles não se mexeram, mas a garantia ali é mais fraca. -#}
        ROUND(SAFE_DIVIDE(SUM(gf), COUNT(*)), 3)                             AS gols_pro_medio,
        ROUND(SAFE_DIVIDE(SUM(ga), COUNT(*)), 3)                             AS gols_contra_medio
{%- endset %}

por_total AS (
    SELECT origem, {{ metricas_de_partida }}
    FROM historico_classificado
    GROUP BY ROLLUP(origem)
),

{# O `HAVING` descarta o total geral do ROLLUP — `por_total` já o emite, e o BigQuery não aceita
    ROLLUP ao lado de outro elemento de agrupamento, então a subtotal por competição tem de vir
    do ROLLUP das duas colunas. -#}
por_competicao AS (
    SELECT ancora_competition, origem, {{ metricas_de_partida }}
    FROM historico_classificado
    GROUP BY ROLLUP(ancora_competition, origem)
    HAVING ancora_competition IS NOT NULL
),

por_fonte AS (
    SELECT ancora_competition, hist_competition, {{ metricas_de_partida }}
    FROM historico_classificado
    WHERE origem = 'emprestada'
    GROUP BY ancora_competition, hist_competition
),

por_liga_do_adversario AS (
    SELECT ancora_competition, origem, adv_liga, {{ metricas_de_partida }}
    FROM historico_classificado
    GROUP BY ancora_competition, origem, adv_liga
),

{#- A RÉGUA DE LEITURA do `ppg`, e não uma medição do universo: a média de `ppg` de cada
    competição sobre TODAS as linhas do PIT dela em que a tabela já existe. É o número que mostra
    que `ppg` é normalizado dentro da competição — se ele der ~1,4 em toda parte, comparar `ppg`
    entre competições não mede nível, mede posição relativa. -#}
ppg_referencia AS (
    SELECT
        p.competition,
        COUNT(*)                        AS linhas_do_pit,
        COUNTIF(p.ppg IS NOT NULL)      AS linhas_com_ppg,
        ROUND(AVG(p.ppg), 3)            AS ppg_medio,
        ROUND(MIN(p.ppg), 3)            AS ppg_min,
        ROUND(MAX(p.ppg), 3)            AS ppg_max
    FROM {{ ref('int_futebol_team_form_pit') }} AS p
    {# A temporada sai das próprias âncoras, e não de um literal: o universo congelado é de uma
        temporada só hoje, mas quem estender a janela não deveria ter de lembrar de um segundo
        lugar para trocar o ano. O teto é o mesmo do universo — a régua tem de ser lida sobre o
        mesmo passado que o resto da análise mede. -#}
    WHERE p.season IN (SELECT DISTINCT season FROM ancoras)
      AND p.kickoff_utc < TIMESTAMP('{{ taskf_universo().teto_utc }}')
    GROUP BY p.competition
),

-- ─────────────────────────── empilhamento ───────────────────────────

{# Os NULL são CASTADOS: sem o cast o literal entra como INT64 e a união com uma coluna STRING
    falha por falta de supertipo comum. -#}
empilhado AS (
    SELECT
        'conferencia'         AS nivel,
        0                     AS nivel_ord,
        CAST(NULL AS STRING)  AS chave,
        CAST(NULL AS STRING)  AS chave2,
        CAST(NULL AS STRING)  AS origem,
        CAST(NULL AS INT64)   AS partidas,
        pares,
        jogos_no_universo,
        CAST(NULL AS INT64)   AS adv_com_ppg,
        CAST(NULL AS INT64)   AS adv_sem_ppg,
        CAST(NULL AS INT64)   AS adv_fora_da_base,
        CAST(NULL AS INT64)   AS adv_selecao,
        CAST(NULL AS INT64)   AS adv_com_ppg_liga,
        CAST(NULL AS FLOAT64) AS ppg_medio,
        CAST(NULL AS FLOAT64) AS ppg_mediana,
        CAST(NULL AS FLOAT64) AS ppg_liga_medio,
        CAST(NULL AS FLOAT64) AS ppg_min,
        CAST(NULL AS FLOAT64) AS ppg_max,
        CAST(NULL AS FLOAT64) AS gols_pro_medio,
        CAST(NULL AS FLOAT64) AS gols_contra_medio,
        pares_batem_base,
        pares_batem_escopo,
        IF(pares = pares_batem_base AND pares = pares_batem_escopo,
           'EXATA',
           'DIVERGENTE — nada abaixo desta linha significa o que diz') AS veredito
    FROM conferencia

    UNION ALL

    SELECT
        'total', 1, 'TODAS', CAST(NULL AS STRING), COALESCE(origem, 'TODAS'),
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_total

    UNION ALL

    SELECT
        'competicao', 2, ancora_competition, CAST(NULL AS STRING), COALESCE(origem, 'TODAS'),
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_competicao

    UNION ALL

    SELECT
        'fonte', 3, ancora_competition, hist_competition, 'emprestada',
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_fonte

    UNION ALL

    SELECT
        'liga_do_adversario', 4, ancora_competition, adv_liga, origem,
        partidas, pares, jogos_no_universo,
        adv_com_ppg, adv_sem_ppg, adv_fora_da_base, adv_selecao, adv_com_ppg_liga,
        ppg_medio, ppg_mediana, ppg_liga_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        gols_pro_medio, gols_contra_medio,
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM por_liga_do_adversario

    UNION ALL

    SELECT
        'ppg_referencia', 5, competition, CAST(NULL AS STRING), CAST(NULL AS STRING),
        linhas_do_pit, CAST(NULL AS INT64), CAST(NULL AS INT64),
        linhas_com_ppg, CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
        CAST(NULL AS INT64),
        ppg_medio, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), ppg_min, ppg_max,
        CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64),
        CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS STRING)
    FROM ppg_referencia
)

SELECT
    nivel,
    chave,
    chave2,
    origem,
    partidas,
    pares,
    jogos_no_universo,
    adv_com_ppg,
    adv_sem_ppg,
    adv_fora_da_base,
    adv_selecao,
    adv_com_ppg_liga,
    ROUND(SAFE_DIVIDE(adv_fora_da_base, partidas) * 100, 1) AS pct_fora_da_base,
    ROUND(SAFE_DIVIDE(adv_selecao,      partidas) * 100, 1) AS pct_selecao,
    ppg_medio,
    ppg_mediana,
    ppg_liga_medio,
    ppg_min,
    ppg_max,
    gols_pro_medio,
    gols_contra_medio,
    pares_batem_base,
    pares_batem_escopo,
    veredito
FROM empilhado
ORDER BY nivel_ord, chave, chave2, origem
