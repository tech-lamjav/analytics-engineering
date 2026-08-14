/*
    [F-10] O ENTREGÁVEL DA TASK [F]: as 39 linhas que o ticket de origem pediu, uma por premissa,
    no benchmark preferido de cada mercado — mais o anexo com as linhas de benchmark não-preferido,
    marcadas como não usadas para peso.

    ────────────────────────────────────────────────────────────────────────────────
    AS QUATRO COLUNAS DO TICKET, E DE ONDE CADA UMA SAI

      1. de onde puxa o histórico            `fonte`, `predicado`     declaração (macro)
      2. se a janela é limitada à competição  `escopo_hoje`            declaração (macro)
      3. se dá para juntar, e o que impede    `juntavel`,`impedimento` declaração (macro)
      4. o que o número vira                  as colunas `_hoje`/`_junto`   MEDIÇÃO

    Mais a quebra por FAMÍLIA de competição, que a spec #49 pede como coluna adicional.

    As três primeiras são leitura de código e moram em macros/taskf_fontes_de_historico.sql, com
    a validação de cobertura em tempo de compilação. A quarta sai da tabela acumulativa das quatro
    células (futebol_taskF.taskf_teste2), no par que responde à pergunta literal do ticket —
    "juntar os campeonatos" é o eixo de ESCOPO:

        `base`   escopo na competição do jogo   = o que roda hoje
        `escopo` escopo em todas as competições = o histórico junto

    O 2×2 completo (com o eixo de recorte) e a atribuição por eixo já estão publicados nas seções
    das #53 e #54 do docs/TASKF_RESULTADOS.md; esta análise não os repete.

    ⚠️ ESTA ANÁLISE NÃO MEDE NADA — ELA LÊ. Nenhuma célula é reconstruída aqui, e não deve ser:
    as quatro saíram da mesma execução (#58) e um rebuild hoje produziria um lote novo, quebrando
    a invariante que torna o 2×2 comparável. `dbt compile` + `bq query`, e nada de `dbt build`.

    ────────────────────────────────────────────────────────────────────────────────
    A DECLARAÇÃO É CONFRONTADA COM A MEDIÇÃO, e é isso que separa esta tabela de uma opinião
    bem formatada. Duas conferências, ambas na saída:

      `cobertura`     a declaração e a medição cobrem o MESMO conjunto de premissas. A macro já
                      confere isso contra futebol_insumos_premissa() ao compilar; aqui a
                      contraparte é o que a medição REALMENTE produziu, que é outra coisa — uma
                      premissa que não acende nenhuma vez some do taskf_teste2 (o `HAVING` dele)
                      e sairia como `SEM_MEDICAO`, não como linha faltando.

      `confere`       quem está declarado como NÃO juntável tem de sair IMÓVEL no piso 0, e quem
                      está declarado juntável tem de se MEXER. É o que pega declaração errada:
                      nenhuma checagem de nome alcançaria uma linha que diz "não dá para juntar"
                      sobre uma premissa cujo número muda.

    ⚠️ IMÓVEL É NO PISO 0, e só. Nos pisos maiores até as premissas de tabela mudam, porque o
    `min_jogos` segue a célula — é a seção *Consequences* da ADR 0008, e cobrar igualdade nos
    demais pisos acusaria de defeito o comportamento que a ADR promete.

    ────────────────────────────────────────────────────────────────────────────────
    ⚠️ A QUEBRA POR FAMÍLIA É DEGENERADA NESTA JANELA, E ISSO É CONTEÚDO, NÃO FALHA. A janela
    congelada (16/06 a 04/08) pega o meio da virada de temporada europeia: as ligas split-year
    ainda não tinham começado e a Champions só aparece em 04/08 à noite, depois do teto. O
    resultado é um universo 100% ano-calendário. A coluna sai assim mesmo, com o número ao lado,
    porque `sem amostra` e `efeito nulo` são coisas diferentes e a segunda seria uma conclusão
    falsa sobre as europeias. A regra é a mesma da analyses/taskf_familia_e_mecanismo.sql.

    O universo da família sai do task01_base() sobre a camada MATERIALIZADA agora — que é a
    última célula que rodou —, enquanto o resto da tabela sai do carimbo. Por isso a coluna
    `confere_universo` compara os dois: se a materialização atual não for do mesmo lote que
    produziu a medição, o número de jogos denuncia.

    COMO RODAR (do dbt_futebol/):

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_entregavel
      bq query --use_legacy_sql=false --project_id=smartbetting-dados --max_rows=200 \
        < target/compiled/dbt_futebol/analyses/taskf_entregavel.sql

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento. O
    `--max_rows` fica explícito por margem, não por necessidade de hoje: são 39 linhas mais 21 de
    anexo, abaixo do corte silencioso de 100 — mas o anexo cresce a cada benchmark novo, e o corte
    não avisa quando morde.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set fontes = taskf_fontes_de_historico() -%}
{#- A tabela de medição é lida por `source()`, como todo o resto do dataset de medição
    (CODING_STANDARDS.md: "Relations only via ref() / source()"). -#}
{%- set medicao = source('futebol_taskF', 'taskf_teste2') -%}

{#- O universo é o PRIMÁRIO e é fixo aqui, sem var: o entregável é a tabela do universo congelado
    da [0.1], que é contra o qual o ticket contesta os números. O efeito de EXCLUIR jogos (Copa do
    Mundo, fase classificatória da Champions) é outra pergunta, e ela tem análise própria desde a
    #58 — analyses/taskf_exclusao.sql. -#}
{#- Validado pela mesma macro que os predicados usam, mesmo sendo literal: o dia em que um nome de
    universo for renomeado, isto quebra alto em vez de filtrar a tabela por um valor que não existe
    mais — que devolveria zero linha e pareceria "a medição não tem estas premissas". -#}
{%- set universo  = taskf_universo_valido('completo') -%}
{#- Os nomes das duas células saem da macro que os define, e são CONFERIDOS: um nome que não
    existe vira Undefined, que o Jinja renderiza como string vazia — e `WHERE celula = ''`
    devolve zero linha, que nesta tabela se parece com "a medição não tem esta premissa". Aconteceu
    na primeira execução desta análise, com uma chave escrita com `_` no lugar do `|`. -#}
{%- set nomes_de_celula = taskf_nomes_de_celula() -%}
{%- set cel_hoje  = nomes_de_celula['da_competicao|temporada'] | default('', true) -%}
{%- set cel_junta = nomes_de_celula['todas|temporada']         | default('', true) -%}
{%- if cel_hoje not in nomes_de_celula.values() or cel_junta not in nomes_de_celula.values() -%}
    {{ exceptions.raise_compiler_error(
        "célula não resolvida a partir de taskf_nomes_de_celula(): hoje='" ~ cel_hoje
        ~ "', junto='" ~ cel_junta ~ "'. Chaves aceitas: "
        ~ nomes_de_celula.keys() | join(' | ')) }}
{%- endif -%}
{#- "Mexeu no piso 0" é o mesmo veredito que a analyses/taskf_delta_celulas.sql emite sobre a mesma
    linha, então os quatro campos saem da macro que os declara — e não de uma segunda lista aqui,
    que faria as duas análises discordarem em silêncio. Aqui os nomes são lidos direto da tabela
    gravada; lá eles passam pelo alias local. -#}
{%- set campos_piso0 = taskf_campos_do_piso0() -%}

WITH {{ task01_base() }},

{{ taskf_familia_competicao() }},

{#- ── A declaração, transcrita para SQL ──────────────────────────────────────────────
    As aspas simples são escapadas na transcrição: um apóstrofo num texto de `ressalva` fecharia
    o literal e quebraria a query com erro de sintaxe a 200 linhas do problema. -#}
declaracao AS (
    SELECT * FROM UNNEST([
        STRUCT<mercado STRING, premissa STRING, fonte STRING, predicado STRING,
               escopo_hoje STRING, juntavel STRING, impedimento STRING, ressalva STRING>
        {%- for f in fontes %}
        ('{{ f.mercado | replace("'", "''") }}', '{{ f.premissa | replace("'", "''") }}',
         '{{ f.fonte | replace("'", "''") }}', '{{ f.predicado | replace("'", "''") }}',
         '{{ f.escopo_hoje }}', '{{ f.juntavel }}',
         '{{ f.impedimento | replace("'", "''") }}',
         '{{ f.ressalva | replace("'", "''") }}'){{ "," if not loop.last }}
        {%- endfor %}
    ])
),

{#- ── A quebra por família ────────────────────────────────────────────────────────── -#}
{#- O predicado sai do MESMO nome de universo que filtra a tabela de medição acima. Escrever
    `taskf_universo_filtro()` direto daria o mesmo SQL hoje e deixaria as duas metades livres para
    divergir amanhã — a quebra por família passaria a descrever outro conjunto de jogos que o dos
    números ao lado. -#}
apostas_congeladas AS (
    SELECT * FROM apostas
    WHERE {{ taskf_universo_predicado(universo) }}
),

familia_do_universo AS (
    SELECT
        f.familia,
        COUNT(DISTINCT a.fixture_id) AS jogos
    FROM apostas_congeladas AS a
    JOIN familia_competicao AS f USING (competition)
    GROUP BY f.familia
),

{#- Uma linha só, para entrar por CROSS JOIN em todas as premissas. A família é propriedade do
    UNIVERSO, e não da premissa: as 39 são medidas sobre os mesmos jogos. -#}
familia_resumo AS (
    SELECT
        COALESCE(SUM(IF(familia = 'ano_calendario', jogos, 0)), 0) AS jogos_ano_calendario,
        COALESCE(SUM(IF(familia = 'split_year',     jogos, 0)), 0) AS jogos_split_year,
        COALESCE(SUM(jogos), 0)                                    AS jogos_materializados
    FROM familia_do_universo
),

{#- ── A medição ──────────────────────────────────────────────────────────────────── -#}
hoje AS (
    SELECT * FROM {{ medicao }}
    WHERE celula = '{{ cel_hoje }}' AND universo = '{{ universo }}'
),

junto AS (
    SELECT * FROM {{ medicao }}
    WHERE celula = '{{ cel_junta }}' AND universo = '{{ universo }}'
),

{#- O lote inteiro, não só as duas células lidas: se alguém re-mediu UMA célula depois da #58, as
    quatro deixam de ser comparáveis e o 2×2 já não é um 2×2 — mesmo que as duas lidas aqui
    tenham vindo juntas. É a conferência de leitura da mesma coisa que a Costura B cobra por
    execução. -#}
lote AS (
    SELECT
        COUNT(DISTINCT git_sha)                       AS n_git_sha,
        COUNT(DISTINCT FORMAT('%t', odds_loaded_at))  AS n_odds_loaded_at,
        COUNT(DISTINCT CONCAT(celula, '|', universo)) AS n_grupos,
        MAX(git_sha)                                  AS git_sha,
        MAX(odds_loaded_at)                           AS odds_loaded_at
    FROM {{ medicao }}
),

{#- FULL OUTER nos dois níveis: entre as células (premissa que existe numa e não na outra) e
    entre declaração e medição. Linha que sumiria em silêncio é achado, não ruído. -#}
medido AS (
    SELECT
        COALESCE(h.mercado, j.mercado)     AS mercado,
        COALESCE(h.premissa, j.premissa)   AS premissa,
        COALESCE(h.benchmark, j.benchmark) AS benchmark,
        COALESCE(h.usado_para_peso, j.usado_para_peso) AS usado_para_peso,
        h.celula IS NULL AS so_no_junto,
        j.celula IS NULL AS so_no_hoje,
        h.jogos_no_universo AS jogos_no_universo,
        h.janela_ini, h.janela_fim,
        h.medido_em AS medido_em_hoje, j.medido_em AS medido_em_junto,
        ({% for campo in campos_piso0 -%}
         IF(h.{{ campo }} IS DISTINCT FROM j.{{ campo }}, 1, 0){{ " + " if not loop.last }}
         {%- endfor %})                    AS campos_piso0_mudados,
        h.n_p0  AS n_p0_hoje,  j.n_p0  AS n_p0_junto,
        h.n_p5  AS n_p5_hoje,  j.n_p5  AS n_p5_junto,
        h.diferenca_p0 AS dif_p0_hoje, j.diferenca_p0 AS dif_p0_junto,
        h.diferenca_p5 AS dif_p5_hoje, j.diferenca_p5 AS dif_p5_junto,
        h.peso_p5 AS peso_p5_hoje, j.peso_p5 AS peso_p5_junto,
        h.jogos_medios_disp AS jogos_hoje, j.jogos_medios_disp AS jogos_junto,
        h.pct_amostra_curta AS curta_hoje, j.pct_amostra_curta AS curta_junto
    FROM hoje AS h
    FULL OUTER JOIN junto AS j USING (mercado, premissa, benchmark)
),

juntado AS (
    SELECT
        COALESCE(m.mercado, d.mercado)   AS mercado,
        COALESCE(m.premissa, d.premissa) AS premissa,
        m.* EXCEPT (mercado, premissa),
        d.* EXCEPT (mercado, premissa),
        d.premissa IS NULL AS sem_declaracao,
        m.premissa IS NULL AS sem_medicao
    FROM medido AS m
    FULL OUTER JOIN declaracao AS d USING (mercado, premissa)
)

SELECT
    IF(COALESCE(j.usado_para_peso, TRUE), 'principal', 'anexo')  AS bloco,
    j.mercado,
    j.premissa,
    j.benchmark,
    j.usado_para_peso,

    -- COLUNA 1 do ticket: de onde puxa o histórico.
    j.fonte,
    j.predicado,
    -- COLUNA 2: se a janela é limitada à competição do jogo.
    j.escopo_hoje,
    -- COLUNA 3: se dá para juntar, e o que impede quando não dá.
    j.juntavel,
    j.impedimento,
    j.ressalva,

    -- COLUNA 4: o que o número vira. `hoje` = célula `base`; `junto` = célula `escopo`.
    j.n_p0_hoje,   j.n_p0_junto,
    j.dif_p0_hoje, j.dif_p0_junto,
    ROUND(j.dif_p0_junto - j.dif_p0_hoje, 1)      AS delta_dif_p0,
    j.n_p5_hoje,   j.n_p5_junto,
    j.dif_p5_hoje, j.dif_p5_junto,
    ROUND(j.dif_p5_junto - j.dif_p5_hoje, 1)      AS delta_dif_p5,
    j.peso_p5_hoje, j.peso_p5_junto,
    j.jogos_hoje,  j.jogos_junto,
    ROUND(j.jogos_junto - j.jogos_hoje, 1)        AS delta_jogos,
    j.curta_hoje,  j.curta_junto,
    ROUND(j.curta_junto - j.curta_hoje, 1)        AS delta_curta,

    -- COLUNA ADICIONAL: a quebra por família de competição. Ver o cabeçalho — nesta janela ela é
    -- degenerada, e o número ao lado é o que impede de ler isso como efeito nulo nas europeias.
    FORMAT('ano_calendario %d (%.1f%%) · split_year %d%s',
           fr.jogos_ano_calendario,
           SAFE_DIVIDE(fr.jogos_ano_calendario, fr.jogos_materializados) * 100,
           fr.jogos_split_year,
           IF(fr.jogos_split_year = 0, ' — SEM AMOSTRA', ''))                AS familia,
    fr.jogos_ano_calendario,
    fr.jogos_split_year,

    -- As duas conferências. Ver o cabeçalho.
    CASE
        WHEN j.sem_declaracao THEN 'SEM_DECLARACAO'
        WHEN j.sem_medicao    THEN 'SEM_MEDICAO'
        ELSE                       'CONFERE'
    END                                                                       AS cobertura,
    CASE
        WHEN j.so_no_hoje OR j.so_no_junto     THEN 'SEM_CONTRAPARTE'
        WHEN j.campos_piso0_mudados = 0        THEN 'IMOVEL_NO_PISO0'
        ELSE                                        'MUDOU'
    END                                                                       AS veredito_medicao,
    CASE
        WHEN j.sem_declaracao OR j.sem_medicao
          OR j.so_no_hoje OR j.so_no_junto     THEN 'NAO_COMPARAVEL'
        WHEN (j.juntavel = 'sim') = (j.campos_piso0_mudados > 0)
                                               THEN 'CONFERE'
        ELSE                                        'DIVERGE'
    END                                                                       AS confere,

    -- Carimbo. O lote é o da #58 e esta análise não o move; as colunas existem para que quem ler
    -- a tabela saiba de qual medição ela saiu sem ter de acreditar no doc.
    j.jogos_no_universo,
    fr.jogos_materializados,
    IF(j.jogos_no_universo = fr.jogos_materializados, 'CONFERE',
       FORMAT('DIVERGE (medido %d, materializado %d)',
              j.jogos_no_universo, fr.jogos_materializados))                  AS confere_universo,
    j.janela_ini,
    j.janela_fim,
    j.medido_em_hoje,
    j.medido_em_junto,
    l.git_sha,
    l.odds_loaded_at,
    IF(l.n_git_sha = 1 AND l.n_odds_loaded_at = 1,
       FORMAT('HOMOGENEO (%d grupos)', l.n_grupos),
       FORMAT('MISTURADO (%d shas, %d odds_loaded_at)', l.n_git_sha, l.n_odds_loaded_at))
                                                                              AS lote
FROM juntado AS j
CROSS JOIN familia_resumo AS fr
CROSS JOIN lote AS l
{#- `benchmark` entra na ordenação porque é parte do grão: sem ele, as duas linhas de uma premissa
    do Gols (sharp e consenso) saem em ordem indefinida entre execuções, e a comparação linha a
    linha de duas rodadas passaria a acusar diferença onde não há.
    ⚠️ Este comentário fecha SEM o traço: com ele, o Jinja come a quebra de linha e cola o
    ORDER BY no CROSS JOIN acima. Foi assim que o comentário da #37 quebrou o task01_base()
    (commit b535130), e foi assim que este ORDER BY quebrou na primeira tentativa.
    ⚠️ E o texto de um comentário não pode conter a sequência que o fecha — descrevê-la em
    palavras é o jeito de falar dela aqui dentro; escrevê-la encerra o comentário no meio e
    despeja o resto como SQL.
 #}
ORDER BY bloco, j.mercado, j.premissa, j.benchmark
