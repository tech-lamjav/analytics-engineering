{#
    [F-2] O universo congelado da medição, conferido contra o número publicado.

    A [F] compara quatro células entre si. Isso só significa alguma coisa se as quatro medirem os
    MESMOS jogos, e a âncora desse "mesmos" é o recorte publicado no doc de resultados da Task
    [0.1]: 16/06/2026 a 04/08/2026, 169 jogos. Esta análise é a conferência dessa âncora — roda
    ANTES de materializar célula nenhuma, porque descobrir que o universo se mexeu depois de
    construir a camada de premissas é caro e tarde.

    Cinco variantes de propósito, e não só a congelada:

      A_sem_corte          o que a [0.1] rodou — todo jogo liquidado com odd, sem corte. Hoje ele
                           é MAIOR que o publicado, porque o tempo passou; a diferença entre A e
                           C é exatamente o que o congelamento remove.
      B_ate_0408_por_dia   o corte ingênuo, `DATE(kickoff) <= '2026-08-04'`. Está aqui porque
                           devolve **178** e não 169, e é essa diferença que prova que o teto da
                           [0.1] é um INSTANTE e não um dia: os 9 excedentes são os jogos de
                           04/08 com kickoff a partir das 16:00 UTC, que ainda não tinham sido
                           disputados quando a [0.1] executou.
      C_universo_congelado   o corte da medição, que é o que taskf_universo() emite.
      D_teto_alternativo   o MESMO corte com o teto na outra ponta do vão vazio (06:00 UTC em vez
                           de 12:00). Existe para mostrar que o teto não foi calibrado até o
                           número bater: entre ~02:00 e 16:00 UTC de 04/08 não há jogo nenhum na
                           base, então qualquer instante da faixa devolve os mesmos 169. C e D
                           idênticos é o que torna o corte robusto; se um dia divergirem, apareceu
                           jogo no vão e o teto precisa ser re-argumentado.
      E_estendido          o universo SECUNDÁRIO da spec (#58): o mesmo piso, sem teto nenhum.
                           Acrescentado porque a pergunta da Champions não tem amostra no
                           congelado — os únicos jogos dela no período são os 8 de 04/08 à noite,
                           que o teto remove. Ele é o predicado `estendido` de
                           macros/taskf_universos.sql, lido de lá e não redigitado aqui.

    ⚠️ E É A MESMA CONTA DO `A_sem_corte`, com uma diferença que importa: A não tem piso NEM teto e
    existe para mostrar o que o congelamento remove; E declara o piso e é o universo que a #58 de
    fato mede. Que os dois deem o mesmo número hoje é consequência de a coleta de odds ser
    forward-only e ter começado em 16/06 — o piso é no-op, como o cabeçalho do macro já registra.
    Se um dia divergirem, apareceu odd de jogo anterior a 16/06 na base.

    ⚠️ O QUE LIMITA O `E_estendido` NÃO É UMA DATA, É A CONSTRUÇÃO DOS FATOS. Rodado com
    `--target taskF`, ele alcança o que a ancestria daquele dataset contém — que é o mesmo
    `fact_odds_snapshot` que as quatro células leram. Rodado com `--target dev`, alcança produção,
    que anda. Os dois são legítimos e respondem perguntas diferentes; o que não se pode é comparar
    número de um com número do outro.

    E o piso: A e B devolvem `janela_ini = 2026-06-16` sem que ninguém peça, porque a coleta de
    odds é forward-only e começou nesse dia. O piso declarado é no-op — e fica declarado assim
    mesmo, para o corte não depender de um efeito colateral da coleta.

    `jogos` sai de `apostas`, e não de `fact_fixtures`: o universo do Teste 2 é o de jogos
    liquidados COM preço nos 5 mercados do Motor, já com o filtro de meia-linha. Contar jogo
    encerrado no período daria outro número, maior, que não é o publicado.

    Rodar com (o target escolhe contra qual dataset se confere — `dev` lê produção, que é onde os
    169 foram publicados; `taskF` confere a célula já materializada):

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target dev --select taskf_universo_congelado
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_universo_congelado.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)
#}

{%- set j = taskf_universo() %}

WITH {{ task01_base() }},

variantes AS (
    SELECT 'A_sem_corte' AS variante, fixture_id, kickoff_utc, competition, benchmark
    FROM apostas

    UNION ALL

    SELECT 'B_ate_0408_por_dia', fixture_id, kickoff_utc, competition, benchmark
    FROM apostas
    WHERE DATE(kickoff_utc) BETWEEN DATE('{{ j.ini }}') AND DATE('{{ j.fim }}')

    UNION ALL

    SELECT 'C_universo_congelado', fixture_id, kickoff_utc, competition, benchmark
    FROM apostas
    WHERE {{ taskf_universo_filtro() }}

    UNION ALL

    SELECT 'D_teto_alternativo', fixture_id, kickoff_utc, competition, benchmark
    FROM apostas
    WHERE kickoff_utc >= TIMESTAMP('{{ j.ini }}')
      AND kickoff_utc <  TIMESTAMP('2026-08-04 06:00:00')

    UNION ALL

    {# O predicado vem da macro dos universos, não de uma segunda escrita do mesmo intervalo: é
       o MESMO recorte que o Teste 2 grava sob o rótulo `estendido`, e duas escritas que precisam
       ficar iguais para sempre não ficam. NB: comentário sem traço nas pontas de propósito — o
       `{#-` comeria a quebra de linha e compilaria `UNION ALLSELECT`, que é o defeito que a #55
       encontrou em master (PR #48). #}
    SELECT 'E_estendido', fixture_id, kickoff_utc, competition, benchmark
    FROM apostas
    WHERE {{ taskf_universo_predicado('estendido') }}
)

SELECT
    variante,
    MIN(DATE(kickoff_utc))                            AS janela_ini,
    MAX(DATE(kickoff_utc))                            AS janela_fim,
    MAX(kickoff_utc)                                  AS ultimo_kickoff_utc,
    COUNT(DISTINCT fixture_id)                        AS jogos,
    {{ j.jogos_esperados }}                           AS jogos_esperados,
    COUNT(DISTINCT fixture_id) - {{ j.jogos_esperados }} AS delta_vs_publicado,
    COUNT(*)                                          AS linhas,
    COUNT(DISTINCT competition)                       AS competicoes,
    COUNTIF(benchmark = 'sharp')                      AS linhas_sharp,
    COUNTIF(benchmark = 'consenso')                   AS linhas_consenso,
    COUNTIF(benchmark = 'derivada')                   AS linhas_derivada
FROM variantes
GROUP BY variante
ORDER BY variante
