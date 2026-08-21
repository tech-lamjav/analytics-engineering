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
*/CREATE TABLE IF NOT EXISTS `smartbetting-dados.futebol_taskF.taskf_teste2` (
    celula STRING,
    pit_escopo STRING,
    pit_recorte STRING,
    universo STRING,
    medido_em TIMESTAMP,
    git_sha STRING,
    odds_loaded_at TIMESTAMP,
    janela_ini DATE,
    janela_fim DATE,
    jogos_no_universo INT64,
    linhas_no_universo INT64,
    mercado STRING,
    premissa STRING,
    benchmark STRING,
    usado_para_peso BOOL,
    fator_encolhimento FLOAT64,
    jogos_medios_disp FLOAT64,
    jogos_medios_usado FLOAT64,
    pct_amostra_curta FLOAT64,
    n_p0 INT64,
    a_odd_dava_p0 FLOAT64,
    aconteceu_p0 FLOAT64,
    diferenca_p0 FLOAT64,
    peso_p0 FLOAT64,
    n_p3 INT64,
    a_odd_dava_p3 FLOAT64,
    aconteceu_p3 FLOAT64,
    diferenca_p3 FLOAT64,
    peso_p3 FLOAT64,
    n_p5 INT64,
    a_odd_dava_p5 FLOAT64,
    aconteceu_p5 FLOAT64,
    diferenca_p5 FLOAT64,
    peso_p5 FLOAT64,
    n_p10 INT64,
    a_odd_dava_p10 FLOAT64,
    aconteceu_p10 FLOAT64,
    diferenca_p10 FLOAT64,
    peso_p10 FLOAT64,
    peso_p0_k0 FLOAT64
);


DELETE FROM `smartbetting-dados.futebol_taskF.taskf_teste2` WHERE celula = 'base';


INSERT INTO `smartbetting-dados.futebol_taskF.taskf_teste2` (celula, pit_escopo, pit_recorte, universo, medido_em, git_sha, odds_loaded_at, janela_ini, janela_fim, jogos_no_universo, linhas_no_universo, mercado, premissa, benchmark, usado_para_peso, fator_encolhimento, jogos_medios_disp, jogos_medios_usado, pct_amostra_curta, n_p0, a_odd_dava_p0, aconteceu_p0, diferenca_p0, peso_p0, n_p3, a_odd_dava_p3, aconteceu_p3, diferenca_p3, peso_p3, n_p5, a_odd_dava_p5, aconteceu_p5, diferenca_p5, peso_p5, n_p10, a_odd_dava_p10, aconteceu_p10, diferenca_p10, peso_p10, peso_p0_k0)

WITH jogos_encerrados AS (
    SELECT
        fixture_id,
        competition,
        season,
        home_team_id,
        away_team_id,
        kickoff_utc,
        goals_home,
        goals_away
    FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
),odds AS (
    SELECT
        fixture_id,
        market_id,
        outcome_side,
        line_value,
        best_odd,
        edge,
        n_casas,
        n_outcomes_valor,
        prob_justa_fechamento,
        valor_fonte,
        penalidades_globais_pts,
        CASE
            WHEN market_id = 12           THEN 'derivada'
            WHEN valor_fonte = 'pinnacle' THEN 'sharp'
            ELSE valor_fonte
        END AS benchmark,
        -- ⚠️ Conjunto de saídas INCOMPLETO: só um lado da linha foi precificado. O
        -- de-vig de consenso normaliza sobre o conjunto, então com um único outcome ele
        -- devolve prob_justa = 1,0 — certeza — e o edge vira `odd − 1`. Uma odd de 150
        -- aparece como "edge de 14.900%".
        --
        -- Medido no universo de análise: 172 linhas, TODAS consenso, 2 vitórias em 172,
        -- ROI −35,5%. É o pior lugar possível para um erro de sinal — o Motor diz valor
        -- máximo onde o acerto real é 1,2%.
        --
        -- PRODUÇÃO NUNCA FOI AFETADA: o gate do mart exige conjunto Pinnacle completo e
        -- prob justa não-nula. (Correção factual: o gate de liquidez é n_casas >= 3, não
        -- >= 4 — a proteção efetiva vinha do gate de COMPLETUDE, não do de liquidez.)
        --
        -- ⚠️ CORRIGIDO NA ORIGEM em 2026-08-05 (spec #22). O de-vig passou a exigir conjunto
        -- de saídas completo para emitir: as linhas degeneradas agora saem daqui pelo filtro
        -- de edge não-nulo que já existe, porque não têm mais edge. Este flag NÃO foi
        -- removido, mas TROCOU DE PAPEL — de "exposto para reproduzir o publicado" para
        -- TESTEMUNHA: se voltar a ser verdadeiro em alguma linha, a correção regrediu.
        -- Mantido também para que a próxima análise VEJA que esta exclusão existe, em vez
        -- de herdá-la em silêncio.
        COALESCE(n_outcomes_valor < 2, TRUE) AS conjunto_incompleto
    FROM (SELECT * EXCEPT (janela_prioridade, janela_e_corrente)
    FROM (SELECT
        d.* EXCEPT (_janela_prioridade, _line_key),
        d._janela_prioridade AS janela_prioridade,
        d._janela_prioridade = MAX(d._janela_prioridade) OVER (
            PARTITION BY d.fixture_id, d.market_id, d._line_key
        ) AS janela_e_corrente
    FROM (
        SELECT
            *,
            CASE janela_usada
        WHEN 't15m'  THEN 4   -- fechamento
        WHEN 't1h'   THEN 3
        WHEN 't24h'  THEN 2
        WHEN 'daily' THEN 1   -- varredura diária, até 7 dias do apito
        ELSE 0
    END AS _janela_prioridade,
            COALESCE(CAST(line_value AS STRING), 'NONE')    AS _line_key
        FROM `smartbetting-dados`.`futebol`.`int_futebol_odds_devig`
    ) d)
    WHERE janela_e_corrente)
),prem_long AS (
    SELECT
        1 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2` AS p
    CROSS JOIN UNNEST([
        STRUCT('forca_mismatch' AS premissa, p.forca_mismatch AS acesa),
        STRUCT('superioridade_xg' AS premissa, p.superioridade_xg AS acesa),
        STRUCT('mando' AS premissa, p.mando AS acesa),
        STRUCT('desfalque_adversario' AS premissa, p.desfalque_adversario AS acesa),
        STRUCT('superioridade_tabela' AS premissa, p.superioridade_tabela AS acesa),
        STRUCT('forma' AS premissa, p.forma AS acesa),
        STRUCT('h2h_favoravel' AS premissa, p.h2h_favoravel AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        5 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        p.line_value AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou` AS p
    CROSS JOIN UNNEST([
        STRUCT('ataque_combinado' AS premissa, p.ataque_combinado AS acesa),
        STRUCT('defesas_vazaveis' AS premissa, p.defesas_vazaveis AS acesa),
        STRUCT('xg_combinado_alto' AS premissa, p.xg_combinado_alto AS acesa),
        STRUCT('ritmo_alto' AS premissa, p.ritmo_alto AS acesa),
        STRUCT('ambos_vazam' AS premissa, p.ambos_vazam AS acesa),
        STRUCT('historico_over' AS premissa, p.historico_over AS acesa),
        STRUCT('linha_subindo' AS premissa, p.linha_subindo AS acesa),
        STRUCT('defesas_firmes' AS premissa, p.defesas_firmes AS acesa),
        STRUCT('clean_sheets_altos' AS premissa, p.clean_sheets_altos AS acesa),
        STRUCT('xg_baixo_combinado' AS premissa, p.xg_baixo_combinado AS acesa),
        STRUCT('ataques_fracos' AS premissa, p.ataques_fracos AS acesa),
        STRUCT('historico_under' AS premissa, p.historico_under AS acesa),
        STRUCT('linha_descendo' AS premissa, p.linha_descendo AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        4 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        p.line_value AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah` AS p
    CROSS JOIN UNNEST([
        STRUCT('supremacia' AS premissa, p.supremacia AS acesa),
        STRUCT('tende_golear' AS premissa, p.tende_golear AS acesa),
        STRUCT('adversario_fragil_fora' AS premissa, p.adversario_fragil_fora AS acesa),
        STRUCT('mando_forte' AS premissa, p.mando_forte AS acesa),
        STRUCT('sem_rodizio' AS premissa, p.sem_rodizio AS acesa),
        STRUCT('raramente_perde_por_2' AS premissa, p.raramente_perde_por_2 AS acesa),
        STRUCT('defesa_fora_solida' AS premissa, p.defesa_fora_solida AS acesa),
        STRUCT('favorito_irregular' AS premissa, p.favorito_irregular AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        8 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts` AS p
    CROSS JOIN UNNEST([
        STRUCT('ambos_marcam' AS premissa, p.ambos_marcam AS acesa),
        STRUCT('ataque_dos_dois' AS premissa, p.ataque_dos_dois AS acesa),
        STRUCT('defesas_vazaveis' AS premissa, p.defesas_vazaveis AS acesa),
        STRUCT('historico_btts' AS premissa, p.historico_btts AS acesa),
        STRUCT('defesa_forte' AS premissa, p.defesa_forte AS acesa),
        STRUCT('ataque_trava' AS premissa, p.ataque_trava AS acesa),
        STRUCT('historico_seco' AS premissa, p.historico_seco AS acesa)
    ]) AS u
    UNION ALL
    SELECT
        12 AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        u.premissa,
        u.acesa
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc` AS p
    CROSS JOIN UNNEST([
        STRUCT('lado_coberto_forte' AS premissa, p.lado_coberto_forte AS acesa),
        STRUCT('equilibrio_defensivo' AS premissa, p.equilibrio_defensivo AS acesa),
        STRUCT('adversario_limitado' AS premissa, p.adversario_limitado AS acesa),
        STRUCT('invicto_recente' AS premissa, p.invicto_recente AS acesa)
    ]) AS u
),prem_n AS (
    SELECT
        market_id,
        fixture_id,
        outcome_side,
        line_value,
        COUNTIF(acesa)         AS n_prem,
        COUNTIF(acesa IS NULL) AS n_prem_null
    FROM prem_long
    GROUP BY 1, 2, 3, 4
),prem_linha AS (
    SELECT
        1 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        penalidades_1x2_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`
    UNION ALL
    SELECT
        5 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        line_value AS line_value,
        penalidades_ou_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ou`
    UNION ALL
    SELECT
        4 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        line_value AS line_value,
        penalidades_ah_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_ah`
    UNION ALL
    SELECT
        8 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        penalidades_btts_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_btts`
    UNION ALL
    SELECT
        12 AS market_id,
        fixture_id,
        outcome AS outcome_side,
        CAST(NULL AS FLOAT64) AS line_value,
        penalidades_dc_pts AS penalidades_especificas_pts
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_dc`
),pit AS (
    SELECT
        j.fixture_id,
        LEAST(COALESCE(h.played_total, 0), COALESCE(a.played_total, 0)) AS min_jogos
    FROM jogos_encerrados AS j
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS h
           ON h.fixture_id = j.fixture_id
          AND h.team_id    = j.home_team_id
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS a
           ON a.fixture_id = j.fixture_id
          AND a.team_id    = j.away_team_id
),

apostas AS (
    SELECT
        o.market_id,
        o.fixture_id,
        o.outcome_side,
        o.line_value,
        o.best_odd,
        o.edge,
        o.n_casas,
        o.prob_justa_fechamento,
        o.benchmark,
        o.conjunto_incompleto,
        j.competition,
        j.season,
        j.kickoff_utc,
        COALESCE(pit.min_jogos, 0) AS min_jogos,
        pn.n_prem,
        pn.n_prem_null,
        -- Insumos da composição "Score pós-A1" do Teste 4. A A1 remove o componente de
        -- VALOR da nota; corroboração e penalidades continuam. Nota: a corroboração
        -- hoje só está implementada p/ 1X2 e o /predictions era ~vazio no histórico,
        -- então ela é majoritariamente 0 — o que na prática torna o Score pós-A1
        -- ≈ nota de premissas menos penalidades.
        COALESCE(c.pts_corroboracao, 0)              AS pts_corroboracao,
        COALESCE(o.penalidades_globais_pts, 0)       AS penalidades_globais_pts,
        COALESCE(px.penalidades_especificas_pts, 0)  AS penalidades_especificas_pts,
        
    CASE
        WHEN o.market_id = 1 THEN
            CASE o.outcome_side
                WHEN 'Home' THEN j.goals_home > j.goals_away
                WHEN 'Away' THEN j.goals_away > j.goals_home
                ELSE             j.goals_home = j.goals_away
            END
        WHEN o.market_id = 5 THEN
            IF(o.outcome_side = 'Over',
               j.goals_home + j.goals_away > o.line_value,
               j.goals_home + j.goals_away < o.line_value)
        -- line_value vem na ÓTICA DO MANDANTE e é igual p/ Home e Away.
        WHEN o.market_id = 4 THEN
            IF(o.outcome_side = 'Home',
               j.goals_home + o.line_value > j.goals_away,
               j.goals_away - o.line_value > j.goals_home)
        WHEN o.market_id = 8 THEN
            IF(o.outcome_side = 'Yes',
               j.goals_home > 0 AND j.goals_away > 0,
               NOT (j.goals_home > 0 AND j.goals_away > 0))
        -- O modelo de premissas da DC só emite '1X' e 'X2'; o ELSE é sempre 'X2'. As
        -- linhas de '12' existem nas odds, não têm premissa e caem no JOIN — uma saída
        -- inteira fora da medição. Reportado, não corrigido.
        WHEN o.market_id = 12 THEN
            IF(o.outcome_side = '1X',
               j.goals_home >= j.goals_away,
               j.goals_away >= j.goals_home)
    END
 AS ganhou
    FROM odds AS o
    JOIN jogos_encerrados AS j
      ON j.fixture_id = o.fixture_id
    JOIN prem_n AS pn
      ON  pn.market_id                      = o.market_id
      AND pn.fixture_id                     = o.fixture_id
      AND pn.outcome_side                   = o.outcome_side
      AND COALESCE(pn.line_value, -999)     = COALESCE(o.line_value, -999)
    LEFT JOIN pit
      ON pit.fixture_id = o.fixture_id
    LEFT JOIN prem_linha AS px
      ON  px.market_id                  = o.market_id
      AND px.fixture_id                 = o.fixture_id
      AND px.outcome_side               = o.outcome_side
      AND COALESCE(px.line_value, -999) = COALESCE(o.line_value, -999)
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_corroboracao` AS c
      ON  c.market_id                  = o.market_id
      AND c.fixture_id                 = o.fixture_id
      AND c.outcome_side               = o.outcome_side
      AND COALESCE(c.line_value, -999) = COALESCE(o.line_value, -999)
    WHERE o.best_odd IS NOT NULL
      AND o.edge     IS NOT NULL
      -- Escopo do Motor, DECLARADO e derivado do catálogo de premissas acima — não
      -- digitado de novo. A coleta traz mercados que o Motor não pontua: 6 (Goals
      -- Over/Under First Half), 7 (HT/FT Double), 10 (Exact Score). Sem esta linha eles
      -- cairiam pelo INNER JOIN com prem_n, o que é correto por acidente: só do 6 são
      -- ~3,6 mil linhas sumindo em silêncio na janela congelada.
      AND o.market_id IN (1, 5, 4, 8, 12)
      AND 
    (o.market_id NOT IN (4, 5)
     OR MOD(CAST(ABS(o.line_value) * 2 AS INT64), 2) = 1)

)

,pit_disponivel AS (
    SELECT
        j.fixture_id,
        LEAST(COALESCE(h.played_total, 0),
              COALESCE(a.played_total, 0)) AS min_jogos_disponivel
    FROM jogos_encerrados AS j
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS h
           ON h.fixture_id = j.fixture_id
          AND h.team_id    = j.home_team_id
    LEFT JOIN `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit` AS a
           ON a.fixture_id = j.fixture_id
          AND a.team_id    = j.away_team_id
),apostas_marcadas AS (
    SELECT
        a.*,
        COALESCE(f.round, '')                  AS round,a.min_jogos                            AS min_jogos_usado,
        COALESCE(d.min_jogos_disponivel, 0)    AS min_jogos_disponivel
    FROM apostas AS a
    LEFT JOIN pit_disponivel AS d
           ON d.fixture_id = a.fixture_id
    LEFT JOIN `smartbetting-dados`.`futebol`.`fact_fixtures` AS f
           ON f.fixture_id = a.fixture_id
),apostas_universos AS (
    SELECT 'completo' AS universo, a.*
    FROM apostas_marcadas AS a
    WHERE (a.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND a.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00'))
    UNION ALL
    SELECT 'sem_copa_mundo' AS universo, a.*
    FROM apostas_marcadas AS a
    WHERE ((a.kickoff_utc >= TIMESTAMP('2026-06-16')
     AND a.kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')) AND a.competition <> 'copa_mundo')
    UNION ALL
    SELECT 'estendido' AS universo, a.*
    FROM apostas_marcadas AS a
    WHERE (a.kickoff_utc >= TIMESTAMP('2026-06-16'))
    UNION ALL
    SELECT 'estendido_sem_champions_classif' AS universo, a.*
    FROM apostas_marcadas AS a
    WHERE (a.kickoff_utc >= TIMESTAMP('2026-06-16')
         AND NOT 
    (a.competition = 'champions_league'
     AND (a.round LIKE '%Qualifying Round%' OR a.round = 'Play-offs')))
),agregado AS (
    SELECT
        a.universo,
        a.market_id,
        pl.premissa,
        a.benchmark,
        AVG(IF(pl.acesa, a.min_jogos_disponivel, NULL))          AS jogos_medios_disp,
        AVG(IF(pl.acesa, a.min_jogos_usado, NULL))               AS jogos_medios_usado,
        AVG(IF(pl.acesa, IF(a.min_jogos_disponivel < 5, 1.0, 0.0), NULL)) AS frac_curta,
        COUNTIF(pl.acesa AND a.min_jogos_disponivel >= 0) AS n_0,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 0,
               a.prob_justa_fechamento, NULL))                   AS p_odd_0,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 0,
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_0,
        COUNTIF(pl.acesa AND a.min_jogos_disponivel >= 3) AS n_3,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 3,
               a.prob_justa_fechamento, NULL))                   AS p_odd_3,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 3,
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_3,
        COUNTIF(pl.acesa AND a.min_jogos_disponivel >= 5) AS n_5,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 5,
               a.prob_justa_fechamento, NULL))                   AS p_odd_5,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 5,
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_5,
        COUNTIF(pl.acesa AND a.min_jogos_disponivel >= 10) AS n_10,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 10,
               a.prob_justa_fechamento, NULL))                   AS p_odd_10,
        AVG(IF(pl.acesa AND a.min_jogos_disponivel >= 10,
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_10
    FROM apostas_universos AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    GROUP BY a.universo, a.market_id, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
),janela AS (
    SELECT
        universo,
        MIN(DATE(kickoff_utc))     AS janela_ini,
        MAX(DATE(kickoff_utc))     AS janela_fim,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*)                   AS linhas_no_universo
    FROM apostas_universos
    GROUP BY universo
),fatos AS (
    SELECT MAX(dbt_loaded_at) AS odds_loaded_at
    FROM `smartbetting-dados`.`futebol`.`fact_odds_snapshot`
),rotulado AS (
    SELECT
        g.*,
        CASE g.market_id
            WHEN 1 THEN '1X2'
            WHEN 5 THEN 'Gols'
            WHEN 4 THEN 'Handicap'
            WHEN 8 THEN 'BTTS'
            WHEN 12 THEN 'Dupla Chance'
        END AS mercado,
        g.benchmark = CASE g.market_id
                          WHEN 12 THEN 'derivada'
                          WHEN 8  THEN 'consenso'
                          ELSE         'sharp'
                      END AS preferido
    FROM agregado AS g
)

SELECT
    'base'                                          AS celula,
    'da_competicao'                                        AS pit_escopo,
    'temporada'                                       AS pit_recorte,
    r.universo,
    CURRENT_TIMESTAMP()                                     AS medido_em,
    'desconhecido'            AS git_sha,
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
    ROUND(r.frac_curta * 100, 1)                            AS pct_amostra_curta,
    r.n_0                                          AS n_p0,
    ROUND(r.p_odd_0  * 100, 1)                     AS a_odd_dava_p0,
    ROUND(r.p_real_0 * 100, 1)                     AS aconteceu_p0,
    ROUND((r.p_real_0 - r.p_odd_0) * 100, 1) AS diferenca_p0,
    -- peso = max(diferença, 0) × n/(n+k), k=50. Ganho negativo vira ZERO, não peso negativo: com
    -- esta amostra, −5 é indistinguível de ruído.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_0 - r.p_odd_0) * 100, 0)
             * SAFE_DIVIDE(r.n_0, r.n_0 + 50), 2),
       NULL)                                                AS peso_p0,
    r.n_3                                          AS n_p3,
    ROUND(r.p_odd_3  * 100, 1)                     AS a_odd_dava_p3,
    ROUND(r.p_real_3 * 100, 1)                     AS aconteceu_p3,
    ROUND((r.p_real_3 - r.p_odd_3) * 100, 1) AS diferenca_p3,
    -- peso = max(diferença, 0) × n/(n+k), k=50. Ganho negativo vira ZERO, não peso negativo: com
    -- esta amostra, −5 é indistinguível de ruído.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_3 - r.p_odd_3) * 100, 0)
             * SAFE_DIVIDE(r.n_3, r.n_3 + 50), 2),
       NULL)                                                AS peso_p3,
    r.n_5                                          AS n_p5,
    ROUND(r.p_odd_5  * 100, 1)                     AS a_odd_dava_p5,
    ROUND(r.p_real_5 * 100, 1)                     AS aconteceu_p5,
    ROUND((r.p_real_5 - r.p_odd_5) * 100, 1) AS diferenca_p5,
    -- peso = max(diferença, 0) × n/(n+k), k=50. Ganho negativo vira ZERO, não peso negativo: com
    -- esta amostra, −5 é indistinguível de ruído.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_5 - r.p_odd_5) * 100, 0)
             * SAFE_DIVIDE(r.n_5, r.n_5 + 50), 2),
       NULL)                                                AS peso_p5,
    r.n_10                                          AS n_p10,
    ROUND(r.p_odd_10  * 100, 1)                     AS a_odd_dava_p10,
    ROUND(r.p_real_10 * 100, 1)                     AS aconteceu_p10,
    ROUND((r.p_real_10 - r.p_odd_10) * 100, 1) AS diferenca_p10,
    -- peso = max(diferença, 0) × n/(n+k), k=50. Ganho negativo vira ZERO, não peso negativo: com
    -- esta amostra, −5 é indistinguível de ruído.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_10 - r.p_odd_10) * 100, 0)
             * SAFE_DIVIDE(r.n_10, r.n_10 + 50), 2),
       NULL)                                                AS peso_p10,
    -- Sensibilidade: peso sem encolhimento nenhum, no piso 0. Mostra o quanto o k=50 está
    -- segurando.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_0 - r.p_odd_0) * 100, 0), 2),
       NULL)                                                AS peso_p0_k0
FROM rotulado AS r
JOIN janela AS j ON j.universo = r.universo
CROSS JOIN fatos AS f