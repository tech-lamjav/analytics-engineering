/*
    [F-2] O TESTE 2 da task [F] — o mesmo do [0.1], sobre o universo congelado, com coluna de
    célula. É a saída que a Costura B (#55) vai testar e de onde saem as 39 linhas do entregável.

        diferença = média(acerto | premissa acesa) − média(prob justa | premissa acesa)

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE ESTA ANÁLISE É UM SCRIPT DDL, E NÃO UM MODELO dbt

    Um modelo segue o target, e o target default é `dev`, que aponta para o dataset de PRODUÇÃO
    (`futebol`) — o mesmo que `prod`. Um `dbt build` distraído publicaria medição no board. O
    destino aqui está escrito no SQL, fixo em `futebol_taskF`, e por isso não tem como escorregar.
    Mesmo argumento e mesmo padrão do analyses/taskf_congela_baseline.sql. Ver ADR 0007.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE A AGREGAÇÃO É UMA CÓPIA DO analyses/task01_teste2.sql

    Copiar código costuma ser o erro que a ADR 0007 recusou nos modelos de premissas — lá a cópia
    derivaria da produção em silêncio. Aqui a assimetria é outra: o original não é código vivo, é
    o REGISTRO CONGELADO de uma task encerrada ([0.1], PR #11), e ninguém o edita. O que a cópia
    precisa reproduzir é um cálculo parado, não um que anda.

    E a cópia não é acreditada, é verificada: a reconciliação da célula `base` contra os números
    publicados (analyses/taskf_reconciliacao_01.sql) é exatamente o teste de que ela computa a
    mesma coisa — nos mesmos dados para os quais foi copiada. Extrair a agregação para um macro
    compartilhado teria o custo oposto e maior: mexer no artefato que produziu os números de
    referência, com o risco de reconciliar a medição contra um bug meu.

    ────────────────────────────────────────────────────────────────────────────────
    O QUE MUDA EM RELAÇÃO AO ORIGINAL — seis coisas, e só seis:

    1. UNIVERSO CONGELADO. `apostas` é recortada por taskf_universo_filtro(). O original rodou sem
       corte (a janela dele é o instante da execução). Ver macros/taskf_universo.sql: o teto é um
       INSTANTE, não um dia, e é isso que devolve os 169 publicados em vez de 178.
    2. COLUNA DE CÉLULA, mais os dois eixos ao lado dela e o carimbo de quando/de-qual-commit.
       O rótulo é DERIVADO dos eixos por taskf_celula() — nunca digitado. Uma célula não tem como
       ser gravada com o nome de outra.
    3. PISO 3 acrescentado à varredura, que no original é [0, 5, 10]. É o que a spec #49 pede
       ("piso varrido em [0, 3, 5, 10] ... para distinguir achado de escolha de corte"). Entra
       agora porque é este ticket que define o formato da tabela, e mudar formato depois da #55
       ter testes em cima dele custa mais. A reconciliação compara só 0/5/10, que é o que a [0.1]
       publicou.
    4. AS DUAS CONTAGENS DE AMOSTRA (#54), `jogos_medios_disp` e `jogos_medios_usado`. Ver a
       seção abaixo — é a mudança que faz o piso significar a mesma coisa nas quatro células.
    5. O CARIMBO DA CONSTRUÇÃO DOS FATOS (#55), `odds_loaded_at`. Ver a CTE `fatos`: é ele que
       tira "as quatro rodaram na mesma execução" da disciplina e põe na linha, onde a Costura B
       consegue cobrar.
    6. A COLUNA DE UNIVERSO (#58). O recorte do item 1 deixa de ser único: cada célula emite uma
       linha por (universo, mercado, premissa, benchmark), com os universos de
       macros/taskf_universos.sql. Ver a seção abaixo.

    ────────────────────────────────────────────────────────────────────────────────
    OS QUATRO UNIVERSOS, E POR QUE ELES SAEM DO MESMO INSERT (#58)

    A #58 fecha duas perguntas que são sobre QUAIS JOGOS ENTRAM NA CONTA, e não sobre o histórico
    que cada jogo carrega: a Copa do Mundo deve sair da base de medição? E a fase classificatória
    da Champions? As duas só se respondem medindo COM e SEM.

    O universo é, portanto, um TERCEIRO EIXO — ortogonal à célula. As definições e o argumento de
    cada variante estão em macros/taskf_universos.sql; aqui importa uma consequência de
    engenharia: **os quatro universos de uma célula saem do MESMO INSERT**. Se `completo` e
    `sem_copa_mundo` fossem duas execuções, a diferença entre elas carregaria dentro de si uma
    reconstrução dos modelos — e a #55 mediu que uma reconstrução move 5 campos em 7.200 sozinha.
    Como a comparação COM/SEM é exatamente o entregável, esse ruído entraria no lugar da resposta.

    Emitidos juntos, os quatro compartilham `medido_em`, `git_sha` e `odds_loaded_at` por
    construção (`CURRENT_TIMESTAMP()` é estável dentro de um statement no BigQuery), e a única
    coisa que difere entre eles é o conjunto de jogos — que é a pergunta.

    ⚠️ `jogos_no_universo`, `linhas_no_universo`, `janela_ini` e `janela_fim` passam a ser POR
    UNIVERSO. Quem ler a tabela sem filtrar universo verá quatro valores para cada um deles e
    quatro linhas por premissa — é por isso que TODO consumidor recorta o universo que quer, e a
    Costura B cobra a invariante de universo dentro de cada um deles em vez de sobre a tabela
    inteira.

    ────────────────────────────────────────────────────────────────────────────────
    AS DUAS CONTAGENS DE AMOSTRA, E QUAL DELAS O PISO CORTA (#54)

    `min_jogos` é o MENOR número de partidas anteriores entre os dois times do jogo. Sob recorte
    de contagem ele se desdobra em dois números diferentes:

      DISPONÍVEL  quantas partidas anteriores EXISTEM no escopo da célula, sem teto.
      USADO       quantas de fato alimentaram as médias — sob `ultimos_10` ele satura em 10.

    Nas células de recorte `temporada` (`base` e `escopo`) os dois são o MESMO número por
    construção: sem teto, tudo que existe é usado. Só `recorte` e `ambos` os separam.

    O PISO CORTA O DISPONÍVEL. O motivo é comparabilidade entre células: o usado não passa de 10
    sob janela de contagem, então um piso sobre ele estaria cortando uma quantidade que tem teto
    numa célula e não tem na outra — e "piso 10" passaria a querer dizer duas coisas diferentes
    em duas colunas da mesma tabela. O disponível é a mesma pergunta nas quatro ("quanto passado
    este jogo tem"), e é ela que a spec #49 manda cortar.

    ⚠️ Para os pisos varridos aqui o corte dá no MESMO conjunto de linhas nos dois: como
    `usado = LEAST(disponível, 10)`, para qualquer piso <= 10 vale `usado >= piso` ⟺
    `disponível >= piso`. Isso é consequência, não coincidência, e está MEDIDO em
    analyses/taskf_saturacao_recorte.sql — não é hipótese em que a tabela se apoia. Quem divergir
    de fato é `jogos_medios`, que é média e não corte, e por isso ele sai nas duas versões.

    `pct_amostra_curta` (< 5) segue o disponível, pela mesma regra do piso — e pela identidade
    acima ele daria o mesmo número no usado nesta configuração.

    Fora isso a agregação é a do original, incluindo o grão (mercado, premissa, BENCHMARK) — as
    linhas de consenso do Handicap e do Gols continuam saindo marcadas `usado_para_peso = false`,
    porque o ROI delas é muito pior que o das sharp e essa diferença é sobre QUAIS jogos a
    Pinnacle escolhe precificar, não sobre o benchmark.

    ────────────────────────────────────────────────────────────────────────────────
    ACUMULATIVA POR CÉLULA. A tabela é criada uma vez e cada execução substitui SÓ a sua célula
    (DELETE + INSERT). As quatro convivem, que é o que a Costura B precisa. O schema é escrito
    por extenso de propósito: ele é o contrato que as células seguintes têm de cumprir, e um
    INSERT de formato diferente falha alto em vez de alargar a tabela em silêncio.

    ⚠️ E É POR ISSO QUE MUDAR O SCHEMA EXIGE DROPAR A TABELA. `CREATE TABLE IF NOT EXISTS` não
    acrescenta coluna a uma tabela que já existe: com o schema novo, o INSERT de lista explícita
    falha na primeira célula. Aconteceu três vezes — a #54 (as duas contagens de amostra), a #55
    (o `odds_loaded_at`) e a #58 (a coluna de universo) —, e nas três a tabela foi dropada antes da
    primeira célula, o que só é
    seguro porque as quatro são re-medidas na mesma execução, que é o que a spec exige de qualquer
    jeito. Se um ticket futuro mudar o schema de novo, é o mesmo passo, e ele NÃO é rotina: dropar
    sem re-medir as quatro deixa a tabela com células de formatos diferentes de execuções
    diferentes.

    ⚠️ `medido_em` e `odds_loaded_at` existem porque a spec exige que as quatro células rodem na
    MESMA EXECUÇÃO — o baseline não é reaproveitado justamente porque `linha_subindo`/
    `linha_descendo` leem odds ao vivo e viram sozinhas entre builds. Com os dois carimbos, "mesma
    execução" é conferível na tabela; sem eles, é confiança. A forma verificável que a #51 definiu
    é `fact_odds_snapshot.dbt_loaded_at` ANTERIOR aos quatro `medido_em` — porque o que de fato
    importa é que as quatro tenham lido a MESMA construção dos fatos, o que é mais forte do que os
    quatro carimbos serem próximos entre si.

    A #55 levou isso um passo adiante: o `dbt_loaded_at` é gravado NA LINHA de cada célula, em vez
    de conferido ao vivo depois. Lido ao vivo ele decai — um rebuild posterior no dataset de
    medição deixaria a conferência vermelha sem que as quatro tivessem deixado de ser comparáveis
    —, e a guarda passaria a depender do target com que roda. Carimbado, ele responde a pergunta
    certa ("as quatro leram a mesma construção?") para sempre. Ver a CTE `fatos`.

    ────────────────────────────────────────────────────────────────────────────────
    COMO RODAR (do dbt_futebol/) — EM FASES, e a separação não é economia, é correção.

    FASE 0, só quando o schema de uma das duas tabelas acumulativas muda (foi o caso na #54, na
    #55 e na #58). Dropar só a que mudou de formato basta — a outra é reescrita célula a célula pelo
    DELETE + INSERT da fase 2, e a fase 2 roda inteira nas quatro de qualquer forma, então as duas
    terminam carregando a mesma execução:

      bq rm -f -t smartbetting-dados:futebol_taskF.taskf_teste2
      bq rm -f -t smartbetting-dados:futebol_taskF.taskf_pit_por_celula

    FASE 1, uma vez só para as quatro células: a ancestria inteira, que é o que popula o dataset
    de medição. Com `--target taskF` todo `ref()` resolve para futebol_taskF, então os fatos têm
    de existir lá antes.

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
        --select +int_futebol_premissas_1x2 +int_futebol_premissas_ou +int_futebol_premissas_ah \
                 +int_futebol_premissas_btts +int_futebol_premissas_dc +int_futebol_corroboracao

    FASE 2, uma vez POR CÉLULA, TRÊS PASSOS NA ORDEM: build → carimbo do PIT → Teste 2, os três
    com as MESMAS `--vars`. O build toca só os nós que respondem às vars — o PIT e os cinco
    modelos de premissas. Nada de `+`.

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
        --select int_futebol_team_form_pit int_futebol_premissas_1x2 int_futebol_premissas_ou \
                 int_futebol_premissas_ah int_futebol_premissas_btts int_futebol_premissas_dc \
        --vars '{pit_escopo: todas}'        # a célula; ausente = base

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_pit_por_celula \
        --vars '{taskf_git_sha: '"$(git rev-parse --short HEAD)"', pit_escopo: todas}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_pit_por_celula.sql

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_teste2 \
        --vars '{taskf_git_sha: '"$(git rev-parse --short HEAD)"', pit_escopo: todas}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_teste2.sql

    FASE 3, uma vez DEPOIS DAS QUATRO: a Costura B (#55), que é o portão. Enquanto ela não
    estiver verde, as quatro células são quatro medições, e não um 2×2 comparável:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt test --target taskF --select tag:costura_b

    As três guardas leem SÓ a tabela acumulativa (por `source()`), não penduram em modelo nenhum
    e por isso não entram nas fases 1 e 2 de carona.

    ⚠️ O CARIMBO DO PIT vem DEPOIS do build da mesma célula, sempre. O rótulo dele sai das vars em
    tempo de compilação e o dado sai do que está materializado: fora de ordem, uma célula é
    gravada com o nome de outra. Ver o cabeçalho de analyses/taskf_pit_por_celula.sql.

    ⚠️ NÃO use `+` na fase 2. O `+` reconstrói o `fact_odds_snapshot` a partir do NDJSON da landing
    a cada célula, e aí as quatro deixam de ler a mesma construção dos fatos. O argumento que
    sustenta a comparação entre células — um viés comum às quatro cancela — vale exatamente
    porque elas leem UMA construção. Reconstruir por célula reinjeta entre elas a mesma variação
    de 2 linhas que a reconciliação da `base` encontrou, e aí ela deixa de cancelar e passa a ser
    lida como efeito de escopo. É também um rescan completo do NDJSON por célula, sem ganho.

    ⚠️ Nas células fora do default, UMA guarda fica vermelha por desenho: a Costura A, que é
    default-only por definição — o que ela afirma é justamente "o default reproduz produção". Ela
    é a única exclusão que a medição precisa. Ver o cabeçalho de
    tests/assert_taskf_pit_default_igual_baseline.sql:

      --exclude assert_taskf_pit_default_igual_baseline

    ⚠️ Esta receita já mandou excluir também o `assert_pit_first_game_has_no_history`. NÃO EXCLUA
    MAIS (#52): a partição dele passou a seguir os eixos da célula, ele é verde nas quatro, e
    excluí-lo faz a célula rodar sem guarda de look-ahead — o defeito (Task 0) que contaminou a
    medição que a [F] existe para refazer.

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/

{%- set c      = taskf_celula() -%}
{%- set j      = taskf_universo() -%}
{%- set pisos  = taskf_pisos() -%}
{%- set tabela = 'smartbetting-dados.futebol_taskF.taskf_teste2' -%}

{#- Uma lista, três usos: o DDL, a lista de colunas do INSERT e a ordem da projeção. Escrita duas
    vezes, ela derivaria — e um INSERT posicional com colunas trocadas de lugar não dá erro, dá
    número errado. -#}
{%- set colunas = [
    'celula STRING', 'pit_escopo STRING', 'pit_recorte STRING', 'universo STRING',
    'medido_em TIMESTAMP', 'git_sha STRING', 'odds_loaded_at TIMESTAMP',
    'janela_ini DATE', 'janela_fim DATE',
    'jogos_no_universo INT64', 'linhas_no_universo INT64',
    'mercado STRING', 'premissa STRING', 'benchmark STRING', 'usado_para_peso BOOL',
    'fator_encolhimento FLOAT64',
    'jogos_medios_disp FLOAT64', 'jogos_medios_usado FLOAT64', 'pct_amostra_curta FLOAT64'
] -%}
{%- for piso in pisos -%}
    {%- set _ = colunas.extend([
        'n_p' ~ piso ~ ' INT64',
        'a_odd_dava_p' ~ piso ~ ' FLOAT64',
        'aconteceu_p' ~ piso ~ ' FLOAT64',
        'diferenca_p' ~ piso ~ ' FLOAT64',
        'peso_p' ~ piso ~ ' FLOAT64'
    ]) -%}
{%- endfor -%}
{%- set _ = colunas.append('peso_p0_k0 FLOAT64') -%}
{%- set nomes_colunas = [] -%}
{%- for col in colunas -%}
    {%- set _ = nomes_colunas.append(col.split(' ')[0]) -%}
{%- endfor -%}


CREATE TABLE IF NOT EXISTS `{{ tabela }}` (
    {{ colunas | join(',\n    ') }}
);


DELETE FROM `{{ tabela }}` WHERE celula = '{{ c.nome }}';


INSERT INTO `{{ tabela }}` ({{ nomes_colunas | join(', ') }})

WITH {{ task01_base() }},

{#- A CONTAGEM USADA, no mesmo formato em que o task01_base() calcula a disponível: o MENOR
    entre os dois times, porque as premissas comparam os dois, e 0 quando não há linha no PIT.

    ⚠️ ESTE CTE JÁ CALCULOU A DISPONÍVEL, e passou a calcular a USADA na #91. A inversão é
    consequência do ADR 0010: o `min_jogos` do task01_base() virou a contagem DISPONÍVEL, então
    quem sobra para ser calculado aqui é a outra. O seam não mudou de lugar nem de motivo — o
    macro é o artefato que produziu os números publicados da [0.1] e não é tocado por esta
    medição, mesmo argumento que pôs o recorte do universo congelado nesta análise e não num
    parâmetro novo dele. A conta é a mesma, sobre a mesma tabela; o que muda é a coluna lida.

    A usada é sempre `played_total`, sem ramo por célula: sob `ultimos_10` ela já vem saturada no
    teto pelo próprio modelo, e sob `temporada` não existe teto, então ela É a disponível. É por
    isso que a Costura B cobra as duas iguais numa célula e divergentes na outra — e é o que
    dispensa aqui o ramo por coluna que o task01_base() precisa ter. -#}
pit_usado AS (
    SELECT
        j.fixture_id,
        LEAST(COALESCE(h.played_total, 0),
              COALESCE(a.played_total, 0)) AS min_jogos_usado
    FROM jogos_encerrados AS j
    LEFT JOIN {{ ref('int_futebol_team_form_pit') }} AS h
           ON h.fixture_id = j.fixture_id
          AND h.team_id    = j.home_team_id
    LEFT JOIN {{ ref('int_futebol_team_form_pit') }} AS a
           ON a.fixture_id = j.fixture_id
          AND a.team_id    = j.away_team_id
),

{#- AS APOSTAS COM O QUE OS UNIVERSOS PRECISAM LER. Sem recorte nenhum aqui: o recorte é o eixo
    de universo e acontece no CTE seguinte, uma vez por variante.

    `round` entra por join com o fact_fixtures porque `apostas` não o carrega, e o predicado da
    fase classificatória da Champions é escrito por semântica de fase (ver
    macros/taskf_universos.sql). É o mesmo seam do `pit_disponivel` acima e pelo mesmo motivo: o
    task01_base() é o artefato que produziu os números publicados da [0.1] e não é tocado por esta
    medição.

    O COALESCE do `round` não é decoração. Sem ele, um fixture de Champions com `round` nulo
    tornaria `NOT (competition = ... AND round LIKE ...)` nulo, e a linha sumiria do universo
    `estendido_sem_champions_classif` calada — some do lado SEM, que é exatamente onde ninguém
    procuraria. Com string vazia, ela cai do lado certo (não é classificatória por rótulo) e
    aparece na contagem. Nas linhas fora da Champions o predicado já é FALSE pelo primeiro termo,
    então nada depende do rótulo. -#}
apostas_marcadas AS (
    SELECT
        a.*,
        COALESCE(f.round, '')                  AS round,
        {#- O `min_jogos` que vem do task01_base() é o DISPONÍVEL desde a #91 (ADR 0010): ele sai
            do played_total_disponivel do PIT sob recorte de contagem, e do played_total sob
            `temporada`, onde as duas coincidem. Ganha aqui um nome que diz isso — o `a.*` acima
            mantém o original, então as duas formas convivem no CTE e só a nomeada chega à
            tabela, que assim não tem coluna cujo sentido depende da célula que se está lendo. -#}
        a.min_jogos                            AS min_jogos_disponivel,
        COALESCE(u.min_jogos_usado, 0)         AS min_jogos_usado
    FROM apostas AS a
    LEFT JOIN pit_usado AS u
           ON u.fixture_id = a.fixture_id
    LEFT JOIN {{ ref('fact_fixtures') }} AS f
           ON f.fixture_id = a.fixture_id
),

{#- OS UNIVERSOS, um recorte por variante, todos na mesma passada. Ver macros/taskf_universos.sql
    para o que cada um responde. A lista vem da macro e nunca é digitada aqui: um universo que
    existisse no predicado e não na lista (ou o contrário) produziria coluna vazia numa tabela
    que já tem quatro dimensões, que é o tipo de buraco que ninguém encontra olhando. -#}
apostas_universos AS (
    {%- for u in taskf_universos() %}
    SELECT '{{ u.nome }}' AS universo, a.*
    FROM apostas_marcadas AS a
    WHERE {{ taskf_universo_predicado(u.nome, 'a.') }}
    {%- if not loop.last %}
    UNION ALL
    {%- endif %}
    {%- endfor %}
),

{#- Uma passada, grão (mercado, premissa, benchmark). Só as linhas em que a premissa ACENDEU
    entram nas médias — é essa a definição do Teste 2.

    O PISO DE AMOSTRA — sobre o DISPONÍVEL, ver o cabeçalho — entra como COLUNA, não como execução
    separada, porque o encolhimento (`k`) e o piso tratam eixos DIFERENTES: `k` trata `n` pequeno (a premissa acendeu poucas vezes), o
    piso trata jogo sem histórico. `clean_sheets_altos` tem n=105 (grande, o encolhimento mal
    encosta) e 77% das linhas em jogo com menos de 5 partidas disputadas — a assinatura exata do
    artefato que matou os +9,7% da Task [0]. Ver os dois lado a lado é o ponto. -#}
agregado AS (
    SELECT
        a.universo,
        a.market_id,
        pl.premissa,
        a.benchmark,
        AVG(IF(pl.acesa, a.min_jogos_disponivel, NULL))          AS jogos_medios_disp,
        AVG(IF(pl.acesa, a.min_jogos_usado, NULL))               AS jogos_medios_usado,
        AVG(IF(pl.acesa, IF(a.min_jogos_disponivel < 5, 1.0, 0.0), NULL)) AS frac_curta
        {%- for piso in pisos %},
        COUNTIF(pl.acesa AND a.min_jogos_disponivel >= {{ piso }}) AS n_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= {{ piso }},
               a.prob_justa_fechamento, NULL))                   AS p_odd_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= {{ piso }},
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_{{ piso }}
        {%- endfor %}
    FROM apostas_universos AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    GROUP BY a.universo, a.market_id, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
),

{#- POR UNIVERSO, e não uma linha só: cada universo tem o seu corte, então tem a sua contagem de
    jogos e as suas duas pontas de janela. É o que deixa a Costura B cobrar a invariante de
    universo DENTRO de cada um deles. -#}
janela AS (
    SELECT
        universo,
        MIN(DATE(kickoff_utc))     AS janela_ini,
        MAX(DATE(kickoff_utc))     AS janela_fim,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*)                   AS linhas_no_universo
    FROM apostas_universos
    GROUP BY universo
),

{#- QUAL CONSTRUÇÃO DOS FATOS ESTA CÉLULA LEU (#55). O `fact_odds_snapshot` é `materialized:
    table` e carimba `CURRENT_TIMESTAMP()` em `dbt_loaded_at`, então o valor é o mesmo em toda a
    tabela e identifica o build que a produziu.

    Por que ele entra na LINHA da célula, e não é conferido depois contra a tabela viva: o que a
    Costura B (#55) precisa afirmar é que as quatro células leram a MESMA construção dos fatos, e
    isso é propriedade das quatro linhas no instante em que foram medidas. Lido ao vivo, o mesmo
    número decai — um rebuild posterior no dataset de medição deixaria a conferência vermelha sem
    que as quatro tivessem deixado de ser comparáveis entre si. Carimbado, ele fica verdadeiro
    para sempre e, junto com `medido_em`, fecha a forma verificável que a #51 definiu.

    E há um efeito de grafo, que é o motivo de a coluna existir em vez de o teste ler o
    `fact_odds_snapshot` por `ref()`: com o carimbo, as três guardas da Costura B leem SÓ
    `source('futebol_taskF', ...)` e não penduram em modelo nenhum — então elas não são
    arrastadas para dentro dos builds das fases 1 e 2 por seleção indireta, e a Costura A segue
    sendo a única exclusão que a medição precisa. -#}
fatos AS (
    SELECT MAX(dbt_loaded_at) AS odds_loaded_at
    FROM {{ ref('fact_odds_snapshot') }}
),

{#- `preferido` calculado UMA vez, não repetido em cada coluna que depende dele. -#}
rotulado AS (
    SELECT
        g.*,
        CASE g.market_id
            {%- for mid, m in task01_markets().items() %}
            WHEN {{ mid }} THEN '{{ m.nome }}'
            {%- endfor %}
        END AS mercado,
        g.benchmark = CASE g.market_id
                          WHEN 12 THEN 'derivada'
                          WHEN 8  THEN 'consenso'
                          ELSE         'sharp'
                      END AS preferido
    FROM agregado AS g
)

SELECT
    '{{ c.nome }}'                                          AS celula,
    '{{ c.escopo }}'                                        AS pit_escopo,
    '{{ c.recorte }}'                                       AS pit_recorte,
    r.universo,
    CURRENT_TIMESTAMP()                                     AS medido_em,
    '{{ var("taskf_git_sha", "desconhecido") }}'            AS git_sha,
    -- A construção dos fatos que esta célula leu; ver a CTE `fatos`. É o que deixa "as quatro
    -- rodaram na mesma execução" ser conferível na tabela em vez de acreditado.
    f.odds_loaded_at,
    j.janela_ini,
    j.janela_fim,
    j.jogos_no_universo,
    j.linhas_no_universo,
    r.mercado,
    r.premissa,
    r.benchmark,
    r.preferido                                             AS usado_para_peso,
    -- Fator de encolhimento aplicado ao peso: n/(n+50). Exposto em vez de um flag binário de "n
    -- suficiente" porque o corte seria arbitrário e este número já diz exatamente quanto da
    -- medição sobreviveu. `desfalque_adversario` (n=7) fica em 0,12: qualquer sinal que ela
    -- tivesse seria 88% descartado por falta de amostra, e isso é diferente de "medimos e deu
    -- ruim".
    ROUND(SAFE_DIVIDE(r.n_0, r.n_0 + 50), 2)                AS fator_encolhimento,
    -- As duas contagens; ver o cabeçalho. Nas células de recorte `temporada` elas são iguais
    -- por construção, e é isso que as torna comparáveis com as duas em que não são.
    ROUND(r.jogos_medios_disp, 1)                           AS jogos_medios_disp,
    ROUND(r.jogos_medios_usado, 1)                          AS jogos_medios_usado,
    ROUND(r.frac_curta * 100, 1)                            AS pct_amostra_curta
    {%- for piso in pisos %},
    r.n_{{ piso }}                                          AS n_p{{ piso }},
    ROUND(r.p_odd_{{ piso }}  * 100, 1)                     AS a_odd_dava_p{{ piso }},
    ROUND(r.p_real_{{ piso }} * 100, 1)                     AS aconteceu_p{{ piso }},
    ROUND((r.p_real_{{ piso }} - r.p_odd_{{ piso }}) * 100, 1) AS diferenca_p{{ piso }},
    -- peso = max(diferença, 0) × n/(n+k), k=50. Ganho negativo vira ZERO, não peso negativo: com
    -- esta amostra, −5 é indistinguível de ruído.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_{{ piso }} - r.p_odd_{{ piso }}) * 100, 0)
             * SAFE_DIVIDE(r.n_{{ piso }}, r.n_{{ piso }} + 50), 2),
       NULL)                                                AS peso_p{{ piso }}
    {%- endfor %},
    -- Sensibilidade: peso sem encolhimento nenhum, no piso 0. Mostra o quanto o k=50 está
    -- segurando.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_0 - r.p_odd_0) * 100, 0), 2),
       NULL)                                                AS peso_p0_k0
FROM rotulado AS r
JOIN janela AS j ON j.universo = r.universo
CROSS JOIN fatos AS f
