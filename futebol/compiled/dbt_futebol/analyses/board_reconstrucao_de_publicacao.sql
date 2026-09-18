/*
    RECONSTRUÇÃO DO HORÁRIO DE PUBLICAÇÃO de um candidato no board (issues #120 / #121).

    Responde três perguntas sobre uma seleção de um jogo, com carimbo de tempo em BRT:

      1. QUANDO ela apareceu no painel pela primeira vez — e se isso foi antes ou depois do apito;
      2. se ela ficou CONTINUAMENTE disponível ou sumiu e voltou (cada reativação reinicia o
         "Disponível desde");
      3. o que o Motor disse em CADA janela de coleta, e por qual porta ela reprovava antes.

    ─────────────────────────────────────────────────────────────────────────────────────────────
    ⚠️ QUAL FONTE RESPONDE O QUÊ — e a lacuna de telemetria que a #121 mediu.

    O funil (`fact_value_funnel`) é append-only e congela no apito, e por isso parece a fonte
    óbvia para "quando isto passou pela primeira vez". **Ele não responde essa pergunta.** Medido
    em 2026-08-28 sobre a semana de 20 a 26/08: dos **7.660** candidatos com mais de uma janela,
    **7.660** — todos, sem exceção — têm um `gravado_em` ÚNICO compartilhado por todas as suas
    janelas. O `gravado_em` data a EXECUÇÃO que escreveu a linha, não a janela que ela descreve.

    O funil diz, portanto, **o que o Motor disse em cada janela**; não diz **quando ele disse**, e
    muito menos quando o assinante viu. Quem data a tela é o snapshot do board
    (`fact_value_opportunities_hist`), cujo `dbt_valid_from` é o instante da execução em que a
    versão nasceu.

    ⚠️ `janela_usada` NÃO É HORÁRIO DE NASCIMENTO. Ela é a janela de odds da versão VIVA naquele
    instante — a última pré-apito, quando lida do PIT. Uma oportunidade publicada em `t1h` e
    atualizada em `t15m` aparece no PIT como `t15m`, e confundir as duas coisas foi exatamente o
    que originou a #120. Quem diz a janela de DETECÇÃO é a coluna `janela_deteccao` (#40).

    ⚠️ O `hist` estreou em **27/07/2026**. Para chave anterior a essa data o `MIN(dbt_valid_from)`
    data a estreia do snapshot, não o nascimento da oportunidade — o mesmo artefato que produziu o
    pico falso registrado no `CONTEXT.md`. Este SQL emite `anterior_a_estreia_do_hist` para que a
    leitura não passe disso em silêncio.

    ─────────────────────────────────────────────────────────────────────────────────────────────
    COMO RODAR (do dbt_futebol/):

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target prod \
        --select board_reconstrucao_de_publicacao \
        --vars '{pub_fixture_id: 1570342, pub_market: goals_over_under, pub_outcome: Over, pub_line: 3.5}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/board_reconstrucao_de_publicacao.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    Os defaults são o caso da #121 (Valencia × Betis, Mais de 3,5 gols). `pub_line` aceita NULL
    para mercados sem linha (1X2, BTTS, Dupla Chance) — a comparação é NULL-safe.

    → RESULTADOS: `docs/TASKA_RESULTADOS.md`, seção "Quando o Valencia × Betis foi publicado".
*/WITH kickoff AS (
    SELECT fixture_id, kickoff_utc, status_short
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE fixture_id = 1570342
),

-- (A) O QUE O MOTOR DISSE, janela a janela. Sem horário — ver o aviso do cabeçalho.
por_janela AS (
    SELECT
        'A. veredito por janela'                       AS bloco,
        v.janela                                       AS chave,
        CAST(NULL AS STRING)                           AS de_brt,
        CAST(NULL AS STRING)                           AS ate_brt,
        CAST(NULL AS INT64)                            AS min_antes_do_apito,
        v.passou_no_gate,
        v.motivo_primario,
        v.best_odd, v.n_casas, ROUND(v.edge, 4) AS edge, v.score,
        v.valor_fonte,
        FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', v.gravado_em, 'America/Sao_Paulo') AS gravado_em_brt
    FROM `smartbetting-dados`.`futebol`.`fact_value_funnel` v
    WHERE v.fixture_id  = 1570342
      AND v.market      = 'goals_over_under'
      AND v.outcome     = 'Over'
      AND v.line_value IS NOT DISTINCT FROM 3.5
),

-- (B) O QUE O PAINEL MOSTROU, versão a versão. `dbt_valid_from` é o instante da execução.
versoes AS (
    SELECT
        h.dbt_valid_from,
        h.dbt_valid_to,
        h.janela_usada,
        h.janela_deteccao,
        h.best_odd, h.n_casas, h.edge, h.score, h.faixa,
        k.kickoff_utc,
        -- Uma REATIVAÇÃO é um buraco entre a morte de uma versão e o nascimento da seguinte.
        -- Versões contíguas (valid_to == valid_from da próxima) são ATUALIZAÇÃO, não republicação.
        LAG(h.dbt_valid_to) OVER (ORDER BY h.dbt_valid_from) AS fim_da_anterior
    FROM `smartbetting-dados.futebol.fact_value_opportunities_hist` h
    CROSS JOIN kickoff k
    WHERE h.fixture_id  = 1570342
      AND h.market      = 'goals_over_under'
      AND h.outcome     = 'Over'
      AND h.line_value IS NOT DISTINCT FROM 3.5
),

no_painel AS (
    SELECT
        'B. versao no painel'                          AS bloco,
        CONCAT(janela_usada, ' (deteccao: ', COALESCE(janela_deteccao, '—'), ')') AS chave,
        FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', dbt_valid_from, 'America/Sao_Paulo') AS de_brt,
        FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', dbt_valid_to,   'America/Sao_Paulo') AS ate_brt,
        TIMESTAMP_DIFF(kickoff_utc, dbt_valid_from, MINUTE) AS min_antes_do_apito,
        TRUE                                           AS passou_no_gate,
        CASE
            WHEN fim_da_anterior IS NULL                     THEN 'primeira publicacao'
            WHEN fim_da_anterior = dbt_valid_from            THEN 'atualizacao (contigua)'
            ELSE CONCAT('REATIVACAO apos ',
                        CAST(TIMESTAMP_DIFF(dbt_valid_from, fim_da_anterior, MINUTE) AS STRING),
                        ' min fora do painel')
        END                                            AS motivo_primario,
        best_odd, n_casas, ROUND(edge, 4) AS edge, score,
        faixa                                          AS valor_fonte,
        CAST(NULL AS STRING)                           AS gravado_em_brt
    FROM versoes
),

-- (C) O VEREDITO. Publicação a partir do apito é inválida; antes dele é válida, mesmo em t15m.
veredito AS (
    SELECT
        'C. veredito'                                  AS bloco,
        CASE
            WHEN (SELECT COUNT(*) FROM versoes) = 0 THEN 'NUNCA PUBLICADA'
            WHEN (SELECT MIN(dbt_valid_from) FROM versoes)
                 >= (SELECT kickoff_utc FROM kickoff) THEN 'INVALIDA: primeira publicacao no apito ou depois'
            ELSE 'VALIDA: publicada antes do apito'
        END                                            AS chave,
        FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S',
            (SELECT MIN(dbt_valid_from) FROM versoes), 'America/Sao_Paulo') AS de_brt,
        FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S',
            (SELECT kickoff_utc FROM kickoff), 'America/Sao_Paulo')         AS ate_brt,
        TIMESTAMP_DIFF((SELECT kickoff_utc FROM kickoff),
                       (SELECT MIN(dbt_valid_from) FROM versoes), MINUTE)   AS min_antes_do_apito,
        (SELECT COUNTIF(fim_da_anterior IS NOT NULL AND fim_da_anterior <> dbt_valid_from)
         FROM versoes) = 0                             AS passou_no_gate,
        CASE
            WHEN (SELECT MIN(dbt_valid_from) FROM versoes)
                 < TIMESTAMP('2026-07-27') THEN 'anterior_a_estreia_do_hist: o horario data o snapshot, nao a oportunidade'
            WHEN (SELECT COUNTIF(fim_da_anterior IS NOT NULL AND fim_da_anterior <> dbt_valid_from)
                  FROM versoes) = 0 THEN 'disponibilidade continua, sem reativacao'
            ELSE 'houve reativacao — "Disponivel desde" reinicia na ultima'
        END                                            AS motivo_primario,
        CAST(NULL AS FLOAT64) AS best_odd, CAST(NULL AS INT64) AS n_casas,
        CAST(NULL AS FLOAT64) AS edge,     CAST(NULL AS INT64) AS score,
        (SELECT status_short FROM kickoff)             AS valor_fonte,
        CAST(NULL AS STRING)                           AS gravado_em_brt
)

SELECT * FROM por_janela
UNION ALL SELECT * FROM no_painel
UNION ALL SELECT * FROM veredito
ORDER BY bloco, de_brt NULLS FIRST, chave