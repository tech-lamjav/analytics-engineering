/*
    [F-5] AS DUAS CONTAGENS DE AMOSTRA, CONFERIDAS — e as invariantes que o eixo de RECORTE traz.

    O critério de aceite da #54 diz "sob janela de contagem, o `usado` satura no tamanho da janela
    e o `disponível` não — VERIFICADO, NÃO ASSUMIDO". Esta análise é a verificação. Ela também
    fecha, para o eixo de recorte, o mesmo buraco que a analyses/taskf_monotonicidade_escopo.sql
    fecha para o eixo de escopo — aquela lê os literais `base`/`escopo` e não alcança as duas
    células novas.

    ────────────────────────────────────────────────────────────────────────────────
    QUATRO BLOCOS, QUATRO PERGUNTAS DIFERENTES. Cada linha da saída traz o seu veredito.

    `saturacao` — uma linha por célula. A identidade que define as duas contagens:

        recorte `temporada`   usado = disponível          (não há teto: tudo que existe é usado)
        recorte `ultimos_10`  usado = LEAST(disponível, N)

      Nas células com teto, `pares_saturados` (disponível > usado) tem de ser MAIOR QUE ZERO: é a
      guarda de não-vacuidade. Zero saturação numa célula rotulada `ultimos_10` não quer dizer
      "ninguém tinha mais de N partidas" — com dezenas de times de 20+ jogos na base, quer dizer
      que o dado gravado sob esse rótulo é de outra célula, porque o carimbo rodou fora de ordem.
      É o mesmo modo de falha que o `MESMO_CONTEUDO_NAS_DUAS` da análise de escopo pega.

    `piso` — uma linha por célula, sobre os jogos AVALIADOS do universo congelado (os 169, e não
      todos os fixtures da janela — ver o CTE `fixtures_do_universo`). Cortar no disponível e
      cortar no usado dão o MESMO conjunto de jogos, em todos os pisos varridos. É consequência da identidade acima (para piso <= N,
      `LEAST(d, N) >= piso` ⟺ `d >= piso`), mas o cabeçalho do Teste 2 afirma isso ao leitor e
      afirmação sem número é o que esta task existe para não fazer. Se um dia a varredura ganhar
      um piso MAIOR que N, este bloco fica vermelho — e aí a escolha de cortar no disponível
      deixa de ser inócua e passa a ser a única correta.

    `monotonicidade` — uma linha por par de células. Os quatro pares do 2x2 em que soltar uma
      dimensão só pode ACRESCENTAR partidas anteriores:

        base    → recorte   (solta a temporada, mantém a competição)
        escopo  → ambos     (solta a temporada, com a competição já solta)
        base    → escopo    (solta a competição, mantém a temporada — a da #53, refeita)
        recorte → ambos     (solta a competição, com a temporada já solta)

      ⚠️ A comparação é sobre o DISPONÍVEL, e tem de ser. No usado ela seria falsa por desenho: um
      time com 25 jogos na temporada tem `base` = 25 e `recorte` usado = 10, e isso é o teto
      funcionando, não perda de histórico. Medir monotonicidade na contagem que satura acusaria
      violação em cima do próprio mecanismo que se quis medir.

    `chaves` — uma linha só. O conjunto de pares (jogo, time) é IDÊNTICO nas quatro células. Os
      eixos mexem no histórico que cada par carrega, nunca em quais pares existem; divergência
      aqui é fan-out ou perda de linha, e as guardas de grão dos modelos pegam só o primeiro.

    ────────────────────────────────────────────────────────────────────────────────
    ⚠️ ESTA ANÁLISE NÃO CHAMA taskf_celula(). Ela lê os quatro nomes da tabela de carimbos, pelo
    mesmo motivo da análise de escopo: é uma comparação ENTRE células e não pertence a nenhuma
    delas. Depender das vars da linha de comando seria exatamente o acoplamento que ela audita.
    O que ela lê de macro é o tamanho do recorte e a lista de pisos — constantes, não vars, e as
    MESMAS que os modelos e o Teste 2 leem.

    POR QUE ANÁLISE E NÃO TESTE SINGULAR: idem. Um teste dbt roda dentro da execução de UMA
    célula e as outras três ainda não existem. As invariantes sobre as quatro juntas são a Costura
    B (#55), por decisão da spec.

    COMO RODAR (do dbt_futebol/), depois de as QUATRO células terem sido carimbadas:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
        --select taskf_saturacao_recorte
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_saturacao_recorte.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    ⚠️ O QUE ELA NÃO FAZ: comparar o número das premissas entre células. Isso é o
    analyses/taskf_delta_celulas.sql, que aceita qualquer par dos quatro nomes. Aqui só se
    verifica que as contagens que aquele número usa significam a mesma coisa nas quatro.

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set carimbos = source('futebol_taskF', 'taskf_pit_por_celula') -%}
{%- set n        = taskf_eixos().tamanho_do_recorte -%}
{%- set pisos    = taskf_pisos() -%}
{#- Os pares em que soltar uma dimensão só pode acrescentar. Escritos como (menor, maior). -#}
{%- set comparacoes = [
    ('base',    'recorte'),
    ('escopo',  'ambos'),
    ('base',    'escopo'),
    ('recorte', 'ambos')
] -%}

WITH {{ task01_base() }},

{#- Os jogos AVALIADOS do universo congelado — os 169 —, e não todos os fixtures da janela. O
    carimbo guarda o PIT inteiro de propósito (fan-out e perda de linha são defeitos do mecanismo
    e não se limitam à janela), mas o bloco `piso` conta JOGOS e tem de contar os mesmos jogos que
    o Teste 2, senão os números não conversam com a tabela publicada. Mesma construção da
    analyses/taskf_familia_e_mecanismo.sql.

    Ler o universo da célula que está materializada é seguro: o conjunto de fixtures avaliados não
    depende do PIT (ele entra por LEFT JOIN, só para o min_jogos), e ser idêntico nas quatro é a
    primeira invariante da Costura B. -#}
fixtures_do_universo AS (
    SELECT DISTINCT fixture_id
    FROM apostas
    WHERE {{ taskf_universo_filtro() }}
),

cel AS (
    SELECT
        celula,
        pit_recorte,
        fixture_id,
        team_id,
        competition,
        kickoff_utc,
        played_total            AS usado,
        played_total_disponivel AS disp,
        medido_em,
        git_sha
    FROM {{ carimbos }}
),

-- ── saturacao ───────────────────────────────────────────────────────────────────────────────
saturacao AS (
    SELECT
        celula,
        ANY_VALUE(pit_recorte)                                       AS pit_recorte,
        COUNT(*)                                                     AS pares,
        MAX(usado)                                                   AS max_usado,
        MAX(disp)                                                    AS max_disp,
        COUNTIF(disp > usado)                                        AS pares_saturados,
        COUNTIF(disp > {{ n }})                                      AS pares_acima_do_teto,
        {# `pit_recorte` é coluna de linha, não agrupada — dentro do argumento de um agregado
            isso é legal, e aninhar ANY_VALUE dentro de COUNTIF não seria. -#}
        COUNTIF(usado != IF(pit_recorte = 'ultimos_10',
                            LEAST(disp, {{ n }}), disp))             AS quebra_da_identidade,
        ROUND(AVG(usado), 2)                                         AS usado_medio,
        ROUND(AVG(disp),  2)                                         AS disp_medio,
        MIN(medido_em)                                               AS medido_em,
        ANY_VALUE(git_sha)                                           AS git_sha
    FROM cel
    GROUP BY celula
),

-- ── piso ────────────────────────────────────────────────────────────────────────────────────
{# O piso é propriedade do JOGO: o menor played_total entre os dois times, que é o que o
    task01_base() calcula. Aqui ele sai do MIN sobre as duas linhas do par — e o recorte do
    universo congelado entra porque é sobre ele que os números do Teste 2 são lidos. -#}
por_jogo AS (
    SELECT
        celula,
        fixture_id,
        MIN(usado) AS min_usado,
        MIN(disp)  AS min_disp
    FROM cel
    JOIN fixtures_do_universo USING (fixture_id)
    GROUP BY celula, fixture_id
),

piso AS (
    SELECT
        celula,
        COUNT(*) AS jogos
        {%- for p in pisos %},
        COUNTIF(min_disp  >= {{ p }}) AS jogos_disp_p{{ p }},
        COUNTIF(min_usado >= {{ p }}) AS jogos_usado_p{{ p }}
        {%- endfor %},
        ({% for p in pisos %}IF(COUNTIF(min_disp >= {{ p }}) != COUNTIF(min_usado >= {{ p }}), 1, 0)
          {{ "+ " if not loop.last }}{% endfor %}) AS pisos_divergentes
    FROM por_jogo
    GROUP BY celula
),

-- ── monotonicidade ──────────────────────────────────────────────────────────────────────────
{%- for menor, maior in comparacoes %}
mono_{{ menor }}_{{ maior }} AS (
    SELECT
        '{{ menor }} -> {{ maior }}'                       AS item,
        COUNTIF(a.disp IS NOT NULL)                        AS pares_esq,
        COUNTIF(b.disp IS NOT NULL)                        AS pares_dir,
        COUNTIF(a.disp IS NULL OR b.disp IS NULL)          AS chaves_divergentes,
        COUNTIF(b.disp < a.disp)                           AS violacoes,
        COUNTIF(b.disp > a.disp)                           AS pares_com_ganho,
        ROUND(AVG(IF(b.disp > a.disp, b.disp - a.disp, NULL)), 2) AS ganho_medio_quando_ganha,
        MAX(b.disp - a.disp)                               AS ganho_max,
        ARRAY_AGG(
            IF(b.disp < a.disp,
               TO_JSON_STRING(STRUCT(a.fixture_id, a.team_id, a.competition,
                                     a.disp AS disp_esq, b.disp AS disp_dir)),
               NULL)
            IGNORE NULLS LIMIT 3
        )                                                  AS exemplos
    FROM (SELECT * FROM cel WHERE celula = '{{ menor }}') AS a
    FULL OUTER JOIN (SELECT * FROM cel WHERE celula = '{{ maior }}') AS b
        USING (fixture_id, team_id)
),
{%- endfor %}

-- ── chaves ──────────────────────────────────────────────────────────────────────────────────
chaves AS (
    SELECT
        COUNT(DISTINCT celula)                                     AS celulas,
        COUNT(*)                                                   AS linhas,
        COUNT(DISTINCT FORMAT('%d|%d', fixture_id, team_id))       AS pares_distintos,
        MIN(pares_por_celula)                                      AS min_pares_por_celula,
        MAX(pares_por_celula)                                      AS max_pares_por_celula
    FROM (
        SELECT celula, fixture_id, team_id,
               COUNT(*) OVER (PARTITION BY celula) AS pares_por_celula
        FROM cel
    )
)

SELECT 1 AS ordem, 'saturacao' AS bloco, celula AS item,
    CASE
        WHEN quebra_da_identidade > 0                             THEN 'IDENTIDADE_QUEBRADA'
        WHEN pit_recorte = 'ultimos_10' AND max_usado > {{ n }}   THEN 'USADO_ACIMA_DO_TETO'
        WHEN pit_recorte = 'ultimos_10' AND pares_saturados = 0   THEN 'SEM_SATURACAO_NENHUMA'
        WHEN pit_recorte = 'ultimos_10' AND max_disp <= {{ n }}   THEN 'DISPONIVEL_TAMBEM_SATUROU'
        WHEN pit_recorte = 'temporada'  AND pares_saturados > 0   THEN 'TETO_ONDE_NAO_DEVIA'
        ELSE                                                           'OK'
    END AS veredito,
    pares AS n_esq, pares_saturados AS n_dir, quebra_da_identidade AS divergencias,
    TO_JSON_STRING(STRUCT(pit_recorte, max_usado, max_disp, pares_acima_do_teto,
                          usado_medio, disp_medio, medido_em, git_sha)) AS numeros
FROM saturacao

UNION ALL

SELECT 2, 'piso', celula,
    IF(pisos_divergentes = 0, 'OK', 'PISO_CORTA_DIFERENTE'),
    jogos, jogos_disp_p5, pisos_divergentes,
    TO_JSON_STRING(STRUCT(
        {%- for p in pisos %}
        jogos_disp_p{{ p }}, jogos_usado_p{{ p }}{{ "," if not loop.last }}
        {%- endfor %}
    ))
FROM piso

{%- for menor, maior in comparacoes %}

UNION ALL

SELECT 3, 'monotonicidade', item,
    CASE
        WHEN chaves_divergentes > 0 THEN 'CHAVES_DIVERGENTES'
        WHEN violacoes > 0          THEN 'VIOLACAO_DE_MONOTONICIDADE'
        WHEN pares_com_ganho = 0    THEN 'MESMO_CONTEUDO_NAS_DUAS'
        ELSE                             'OK'
    END,
    pares_esq, pares_dir, violacoes,
    TO_JSON_STRING(STRUCT(chaves_divergentes, pares_com_ganho, ganho_medio_quando_ganha,
                          ganho_max, exemplos))
FROM mono_{{ menor }}_{{ maior }}
{%- endfor %}

UNION ALL

SELECT 4, 'chaves', 'as quatro celulas',
    CASE
        WHEN celulas < 4                                   THEN 'FALTA_CELULA'
        WHEN min_pares_por_celula != max_pares_por_celula  THEN 'CONTAGEM_DIFERENTE_ENTRE_CELULAS'
        WHEN pares_distintos != min_pares_por_celula       THEN 'CONJUNTO_DE_PARES_DIFERENTE'
        ELSE                                                    'OK'
    END,
    pares_distintos, linhas, IF(pares_distintos * celulas = linhas, 0, 1),
    TO_JSON_STRING(STRUCT(celulas, min_pares_por_celula, max_pares_por_celula))
FROM chaves

ORDER BY ordem, item
