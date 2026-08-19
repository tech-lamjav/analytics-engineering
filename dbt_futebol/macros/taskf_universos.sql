{#
    OS UNIVERSOS DE MEDIÇÃO da task [F] (issue #49, ticket #58), escritos UMA vez.

    Um UNIVERSO diz QUAIS JOGOS entram na conta. É o terceiro eixo da medição, e ele não tem
    relação com os outros dois:

      universo   quais jogos são MEDIDOS               (esta macro)
      célula     qual HISTÓRICO cada jogo carrega      (macros/taskf_celula.sql — escopo × recorte)
      janela     qual coleta de ODDS foi lida          (daily/t24h/t1h/t15m — nada a ver com [F])

    Até a #57 existia um universo só, o congelado da [0.1] (macros/taskf_universo.sql). A #58
    precisa de quatro porque as duas perguntas que ela fecha são perguntas sobre o UNIVERSO, e não
    sobre o histórico: "a Copa do Mundo deve sair da base de medição?" e a mesma sobre a fase
    classificatória da Champions. Uma pergunta dessas só se responde medindo COM e SEM — e as duas
    medições têm de sair da MESMA construção dos fatos e da MESMA materialização da célula, senão
    a diferença entre elas carrega dentro de si um rebuild. Por isso os universos são uma coluna
    da tabela do Teste 2, emitidos todos pelo mesmo INSERT, e não execuções separadas.

    ────────────────────────────────────────────────────────────────────────────────
    OS QUATRO, e o que cada um existe para responder:

      completo                          o universo congelado da [0.1] — 16/06 a 04/08, 169 jogos.
                                        É o PRIMÁRIO: é dele que sai tudo o que as #51–#55
                                        mediram, e é ele que as guardas da Costura B cobram.

      sem_copa_mundo                    o mesmo, menos a Copa do Mundo (79 jogos, 46,7%). O par
                                        `completo` × `sem_copa_mundo` é a resposta empírica que a
                                        spec pede: a recomendação sai do efeito na ORDENAÇÃO das
                                        premissas, não do bom senso.

      estendido                         de 16/06 até onde os fatos alcançam, SEM teto. Reportado
                                        à parte (user story 5 da #58) e, sobretudo, é o único
                                        universo em que a Champions existe.

      estendido_sem_champions_classif   o estendido menos a FASE CLASSIFICATÓRIA da Champions —
                                        a exclusão candidata que a spec nomeia. Não é "menos a
                                        Champions": ver o predicado abaixo.

    ⚠️ POR QUE A PERGUNTA DA CHAMPIONS SÓ CABE NO ESTENDIDO. O universo congelado não tem UM jogo
    de Champions: os únicos do período são os 8 de 04/08 à noite, e o teto do congelado (04/08
    12:00 UTC) os remove. Medido na #51. Sem o estendido, a user story 24 da spec #49 não teria
    amostra nenhuma.

    ⚠️ O ESTENDIDO NÃO TEM TETO, E ISSO É ESCOLHA. Um teto datado seria um segundo número a
    calibrar, e ele mentiria: o que limita o estendido não é uma data, é a CONSTRUÇÃO DOS FATOS
    que as quatro células leram (o `odds_loaded_at` carimbado na linha). Rebuildar a ancestria
    para o estendido alcançar hoje custaria re-medir as quatro células e quebraria a única coisa
    que faz a comparação entre elas significar algo. Sem teto, o universo é "o que os fatos
    contêm", o `janela_fim` da linha diz até onde ele foi, e o `odds_loaded_at` ao lado diz por
    quê. É o mesmo espírito da variante `A_sem_corte` do analyses/taskf_universo_congelado.sql.

    ⚠️ E O ESTENDIDO NÃO É COMPARÁVEL COM O CONGELADO COMO SE FOSSE OUTRA CÉLULA. Ele contém os
    169 mais o que veio depois; as duas linhas do Teste 2 não são um A/B de um eixo, são dois
    recortes encaixados. O que se compara DENTRO dele é o par com/sem Champions. A tolerância
    `taskf_tolerancia_pp` para `linha_subindo`/`linha_descendo` volta a ter mordida aqui: no
    congelado a coleta de odds já tinha parado (zero capturas após 04/08, medido), no estendido
    não.

    ⚠️ MAS O VALOR DELA NÃO SERVE AQUI SEM MEDIÇÃO NOVA (#92, 19/08/2026). Ela era 0,5 pp e passou
    a ser **0,25 pp**, e o 0,25 foi calibrado sobre o universo `completo`: nele o ruído de
    instrumento mede 0,00 pp (8 execuções, pós-#78) e a deriva de odds é zero por falta de
    mecanismo, então o que sobra dentro da régua é o resíduo conhecido do `linha_descendo` mais
    meia grade do `ROUND(·, 1)`. Aqui no estendido a componente de deriva NÃO é zero e **nunca foi
    medida** — a #78 não a tocou. Quem escrever a primeira comparação sobre o estendido mede essa
    componente antes de reusar o número; herdá-lo às cegas é trocar um falso-verde por um
    falso-vermelho. Ver `analyses/taskf_ruido_do_instrumento.sql`.

    ────────────────────────────────────────────────────────────────────────────────
    O GABARITO (`jogos_esperados`), e por que só dois dos quatro têm um.

    Os dois universos congelados têm contagem FIXA: 169 e 90 (169 − 79 da Copa do Mundo). Uma
    guarda que compare contra eles pega jogo que apareceu ou sumiu — que num universo congelado é
    sempre erro, e a #51 mostrou que ele se move sozinho (resultado que entra tarde, jogo
    remarcado). Os dois estendidos crescem legitimamente a cada construção dos fatos, então
    gabarito neles seria um número a atualizar toda execução — cobrança que só ensina a ignorar
    guarda. `none` aqui quer dizer "não há número a declarar", e não "ninguém conferiu": a
    invariante que vale para os quatro — as quatro células medirem o MESMO universo — é cobrada em
    tests/assert_taskf_celulas_mesmo_universo.sql para TODOS eles.

    Uso:

        {%- for u in taskf_universos() %}
        SELECT '{{ u.nome }}' AS universo, ... WHERE {{ taskf_universo_predicado(u.nome, 'a.') }}
        {%- endfor %}
#}

{% macro taskf_universos() %}
    {%- set j = taskf_universo() -%}
    {{ return([
        {'nome': 'completo',
         'jogos_esperados': j.jogos_esperados,
         'descricao': 'O universo congelado da [0.1]: 16/06 a 04/08, 169 jogos. O primário.'},
        {'nome': 'sem_copa_mundo',
         'jogos_esperados': j.jogos_esperados - 79,
         'descricao': 'O congelado menos a Copa do Mundo — o lado SEM do par que a #58 mede.'},
        {'nome': 'estendido',
         'jogos_esperados': none,
         'descricao': 'De 16/06 até onde a construção dos fatos alcança, sem teto.'},
        {'nome': 'estendido_sem_champions_classif',
         'jogos_esperados': none,
         'descricao': 'O estendido menos a fase classificatória da Champions.'}
    ]) }}
{% endmacro %}


{#-
    A VALIDAÇÃO DO NOME, num lugar só — e devolvendo o nome, para caber numa linha no consumidor:

        {%- set universo = taskf_universo_valido(var('taskf_universo', 'completo')) -%}

    Existe pelo mesmo argumento que a ADR 0007 usa para a lista de valores de eixo em
    `taskf_eixos()`: a LISTA já morava num lugar só, mas o VALIDADOR estava copiado em cada
    consumidor, e quatro cópias de uma checagem que precisa ficar igual para sempre não ficam. A
    divergência aqui seria muda das duas formas — um consumidor aceitando um nome que outro recusa
    lê universo vazio, e universo vazio se parece com "essa premissa não acende aqui".

    Fail-closed: nome desconhecido levanta erro de compilação em vez de virar filtro que não casa
    com linha nenhuma.
-#}
{% macro taskf_universo_valido(nome) %}
    {%- set nomes = [] -%}
    {%- for u in taskf_universos() -%}{%- set _ = nomes.append(u.nome) -%}{%- endfor -%}
    {%- if nome not in nomes -%}
        {{ exceptions.raise_compiler_error(
            "universo inválido: '" ~ nome ~ "'. Valores aceitos: " ~ nomes | join(' | ')) }}
    {%- endif -%}
    {{ return(nome) }}
{% endmacro %}


{#-
    O PREDICADO DE CADA UNIVERSO. `alias` inclui o ponto: taskf_universo_predicado('completo', 'a.')

    O alias precisa expor `kickoff_utc`, `competition` e `round`. Os dois primeiros vêm de
    `apostas` (task01_base); `round` NÃO vem — ele é juntado do fact_fixtures no site que consome,
    do mesmo jeito que a contagem disponível do PIT entra no analyses/taskf_teste2.sql. O macro
    compartilhado não é tocado: ele é o artefato que produziu os números publicados da [0.1].

    Fail-closed pelo mesmo motivo de taskf_eixos(): um nome digitado errado devolveria universo
    vazio, e universo vazio se parece com "essa premissa não acende aqui".
-#}
{% macro taskf_universo_predicado(nome, alias='') %}
    {%- set j = taskf_universo() -%}
    {%- set _ = taskf_universo_valido(nome) -%}
    {%- if nome == 'completo' -%}
        {{ taskf_universo_filtro(alias) }}
    {%- elif nome == 'sem_copa_mundo' -%}
        ({{ taskf_universo_filtro(alias) }} AND {{ alias }}competition <> 'copa_mundo')
    {%- elif nome == 'estendido' -%}
        ({{ alias }}kickoff_utc >= TIMESTAMP('{{ j.ini }}'))
    {%- elif nome == 'estendido_sem_champions_classif' -%}
        ({{ alias }}kickoff_utc >= TIMESTAMP('{{ j.ini }}')
         AND NOT {{ taskf_champions_classificatoria(alias) }})
    {%- endif -%}
{%- endmacro %}


{#-
    A FASE CLASSIFICATÓRIA DA CHAMPIONS, escrita por SEMÂNTICA DE FASE e não por competição.

    A spec é explícita: a exclusão candidata é a FASE, não a competição — "a mesma pergunta da
    Copa do Mundo respondida também para a fase classificatória da Champions" (#49, user story
    24; critério de aceite da #58). Escrever `competition = 'champions_league'` responderia outra
    pergunta, e responderia igual HOJE por acidente: na janela medida a Champions só tem
    qualificatória (a fase de liga começa em setembro). Que as duas coisas coincidam nesta janela
    é MEDIÇÃO, e sai como número no analyses/taskf_exclusao.sql — não é premissa deste predicado.

    ⚠️ A ARMADILHA DO 'Play-offs'. O `round` do fact_fixtures tem DOIS rótulos com a palavra:

        'Play-offs'                 agosto — o último degrau da CLASSIFICATÓRIA, antes da fase de
                                    liga. É classificatória.
        'Knockout Round Play-offs'  fevereiro — o mata-mata de acesso às oitavas, DEPOIS da fase
                                    de liga. NÃO é classificatória.

    Por isso o casamento do primeiro é por IGUALDADE e não por LIKE '%Play-off%', que pegaria os
    dois. Conferido no fact_fixtures: as temporadas 2024 e 2025 têm os dois rótulos, em meses
    opostos do calendário. Na janela desta medição só o de agosto existe — mas um LIKE aqui seria
    uma bomba armada para a primeira vez que alguém rodar isto sobre uma janela de fevereiro.

    As três qualificatórias ('1st/2nd/3rd Qualifying Round') casam por LIKE porque o número muda e
    a semântica não.
-#}
{% macro taskf_champions_classificatoria(alias='') %}
    ({{ alias }}competition = 'champions_league'
     AND ({{ alias }}round LIKE '%Qualifying Round%' OR {{ alias }}round = 'Play-offs'))
{%- endmacro %}
