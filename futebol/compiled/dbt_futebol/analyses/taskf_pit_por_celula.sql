/*
    [F-4] A CONTAGEM DE PARTIDAS ANTERIORES de cada célula, guardada para as células poderem ser
    comparadas entre si.

    Por que existe. O critério de aceite da #53 é uma invariante ENTRE células — "para todo par
    (jogo, time), a contagem de partidas anteriores em `escopo` é maior ou igual à de `base`" —, e
    o `int_futebol_team_form_pit` é uma tabela SÓ: cada célula sobrescreve a anterior no dataset
    de medição. Sem este carimbo, comparar as duas exigiria rodar as duas de novo, uma de cada
    lado da comparação, e aí não seriam mais a mesma execução. Aqui cada célula deixa a sua
    contagem gravada e a comparação (analyses/taskf_monotonicidade_escopo.sql) lê as duas.

    ⚠️ ORDEM DE EXECUÇÃO, POR CÉLULA — build → carimbo → Teste 2, os três com as MESMAS `--vars`:

      1. dbt build   --target taskF --select <os 6 nós>   --vars '{...}'
      2. dbt compile --target taskF --select taskf_pit_por_celula --vars '{...}'  + bq query
      3. dbt compile --target taskF --select taskf_teste2         --vars '{...}'  + bq query

    O rótulo da célula é DERIVADO das vars em tempo de compilação (taskf_celula(), que não deixa
    uma célula ser gravada com o nome de outra), mas o DADO vem do que estiver materializado no
    dataset naquele instante. As duas coisas só coincidem se o carimbo vier depois do build da
    MESMA célula. Rodar fora de ordem grava dado de uma célula com o rótulo de outra, e nada na
    tabela denuncia — as duas têm o mesmo formato.

    Isso não fica só na disciplina: a análise de monotonicidade tem veredito de NÃO-VACUIDADE
    (`MESMO_CONTEUDO_NAS_DUAS`, quando nenhum par ganhou partida) e confere o lado `base` contra o
    baseline congelado ANTES de as vars existirem. Ordem errada cai num dos dois.

    ────────────────────────────────────────────────────────────────────────────────
    POR QUE UM SCRIPT DDL, E NÃO UM MODELO dbt. Mesmo argumento do analyses/taskf_teste2.sql: um
    modelo segue o target, e o target default é `dev`, que aponta para o dataset de PRODUÇÃO. O
    destino aqui está escrito no SQL, fixo em `futebol_taskF`, e por isso não tem como escorregar.
    Ver ADR 0007.

    POR QUE SÓ OS `played_*`, E NÃO A LINHA INTEIRA DO PIT. A pergunta da #53 é sobre CONTAGEM de
    partidas anteriores; médias de gols e rank são funções do mesmo join e não acrescentam
    verificação nenhuma — quem quiser a linha inteira de uma célula tem a tabela materializada
    enquanto ela é a corrente. As chaves (fixture, time, competição, season, kickoff) vêm junto
    porque a comparação precisa quebrar por competição e por família.

    ⚠️ AS DUAS CONTAGENS (#54). `played_total` é a USADA — sob recorte de contagem ela satura no
    tamanho do recorte, porque só as partidas que sobreviveram ao teto alimentaram as médias.
    `played_total_disponivel` é quantas EXISTEM no escopo, sem teto. Nas células de recorte
    `temporada` o modelo não emite a segunda coluna (emiti-la mudaria o SQL compilado do caminho
    que produção usa), e aqui ela é projetada do próprio `played_total`: sem teto, disponível É a
    usada, então a projeção é exata e não uma aproximação. É essa igualdade que a
    analyses/taskf_saturacao_recorte.sql confere, em vez de tomá-la como dada.

    ACUMULATIVA POR CÉLULA, igual ao taskf_teste2: a tabela é criada uma vez e cada execução
    substitui SÓ a sua célula (DELETE + INSERT). As quatro convivem.

    ⚠️ O carimbo é do PIT INTEIRO, sem recorte de universo. A invariante de monotonicidade vale
    para todo par (jogo, time) que o modelo produz, não só para os do universo congelado: fan-out
    e perda de linha são defeitos do mecanismo, e limitá-los à janela esconderia os que acontecem
    fora dela. O recorte do universo é aplicado depois, por quem mede efeito
    (analyses/taskf_familia_e_mecanismo.sql), e não por quem carimba.

    COMO RODAR (do dbt_futebol/), depois do build da célula:

      DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_pit_por_celula \
        --vars '{taskf_git_sha: '"$(git rev-parse --short HEAD)"', pit_escopo: todas}'
      bq query --use_legacy_sql=false --project_id=smartbetting-dados \
        < target/compiled/dbt_futebol/analyses/taskf_pit_por_celula.sql

    ⚠️ NA #82 O DESTINO É OUTRO. A âncora da remedição escreve em `taskf_pit_por_celula_ancora`,
    pela var `taskf_destino` (`medicao` | `ancora`, fail-closed) — ver macros/taskf_destino.sql e o
    cabeçalho de analyses/taskf_teste2.sql, FASE 4. Esta acumulativa fica intocada.

    (`bq query` com o SQL como argumento trava nesta máquina — sempre por redirecionamento.)

    → RESULTADOS: `docs/TASKF_RESULTADOS.md`.
*/CREATE TABLE IF NOT EXISTS `smartbetting-dados.futebol_taskF.taskf_pit_por_celula` (
    celula STRING,
    pit_escopo STRING,
    pit_recorte STRING,
    medido_em TIMESTAMP,
    git_sha STRING,
    fixture_id INT64,
    team_id INT64,
    competition STRING,
    competition_id INT64,
    season INT64,
    kickoff_utc TIMESTAMP,
    played_home INT64,
    played_away INT64,
    played_total INT64,
    played_total_disponivel INT64
);


DELETE FROM `smartbetting-dados.futebol_taskF.taskf_pit_por_celula` WHERE celula = 'ambos';


INSERT INTO `smartbetting-dados.futebol_taskF.taskf_pit_por_celula` (celula, pit_escopo, pit_recorte, medido_em, git_sha, fixture_id, team_id, competition, competition_id, season, kickoff_utc, played_home, played_away, played_total, played_total_disponivel)
SELECT
    'ambos'                               AS celula,
    'todas'                             AS pit_escopo,
    'ultimos_10'                            AS pit_recorte,
    CURRENT_TIMESTAMP()                          AS medido_em,
    'desconhecido' AS git_sha,
    fixture_id,
    team_id,
    competition,
    competition_id,
    season,
    kickoff_utc,
    played_home,
    played_away,
    played_total,
    played_total_disponivel AS played_total_disponivel
FROM `smartbetting-dados`.`futebol`.`int_futebol_team_form_pit`