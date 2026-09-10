{#- FONTE ÚNICA do insumo de cada premissa do Motor de Score.

    Uma premissa que não acende pode ser duas coisas muito diferentes: o sinal foi medido e
    não estava lá, ou o sinal nunca pôde ser medido. Hoje as duas viram o mesmo score mais
    baixo, e o leitor não tem como separar pouca informação de informação contrária. Contar a
    segunda é o trabalho da ADR 0003 — e este macro é de onde a contagem sai
    (futebol_premissas_cegas, em macros/premissas_sem_dado.sql).

    Por que declarar num lugar só, e não contar NULL à mão em cada modelo: o contador escrito
    à mão fica correto no dia em que é escrito e apodrece na premissa seguinte. Quem
    acrescentar uma premissa nova precisa lembrar de somá-la, e esquecer é SILENCIOSO — o
    contador segue verde, só que menor que a verdade. É o mesmo modo de falha do mercado órfão
    que a ADR 0002 tratou com futebol_conjunto_saidas(), e a resposta aqui é a mesma: declarar
    num lugar, e pôr uma guarda comparando o declarado com o que os modelos realmente
    produzem (assert_premissas_insumo_declarado).

    TRÊS TIPOS, porque nem toda coluna booleana de um modelo de premissas é uma premissa:

      premissa   — entra no PTS_PREMISSAS e conta para premissas_sem_dado. São 39.
      penalidade — subtrai pontos. Não conta para o contador (não é conhecimento faltando),
                   mas declara insumo do mesmo jeito: desfalque_proprio depende de s_missing,
                   e a ADR 0003 decidiu que cegueira deixa de EXIMIR a penalidade.
      marcador   — nem soma nem subtrai; diz de que lado a linha está (is_favorito/is_azarao
                   no Handicap). Declarado para que a guarda não o acuse de premissa não
                   declarada, que é o ponto cego do fail-closed.

    TRÊS CHAVES por entrada, e a terceira é a que faz o contador ser diagnóstico e não ruído:

      insumos   — as colunas da CTE `metrics` de onde a premissa lê. NÃO são colunas da saída:
                  é na `metrics` que a nulidade ainda existe, porque no SELECT final "não
                  acendeu" e "não pôde ser avaliada" já colapsaram num FALSE só.
                  Uma entrada pode ser um nome (a premissa lê sempre aquela coluna) ou um par
                  {'col': ..., 'quando': ...} — o insumo CONDICIONAL, que só é lido quando a
                  condição vale. `mando` é o caso: lê pct_pts_home mandando e aprov_fora
                  jogando fora, e exigir os dois não-nulos marcaria como cega uma premissa a
                  que só falta relevância.

      aplicavel — em que linhas a premissa PODE acender. A maioria das premissas é gated por
                  lado (`is_favorito AND ...` no Handicap, `outcome = 'Over'` em Gols, `Yes`
                  em BTTS), e uma premissa do outro lado não está cega: ela não está em jogo.
                  Sem esta chave, TODA linha de Handicap contaria 3 ou 4 premissas sem dado,
                  permanentemente e por desenho — e um contador que diz o mesmo número em toda
                  linha é ignorado exatamente como guarda que nasce vermelha, escondendo a
                  cegueira real no meio do ruído. No 1X2 o gate é o `Draw`: sem lado apostado
                  não existe time S de quem medir nada, e as 7 ficam fora.

    ⚠️ INSUMO NÃO-NULO NÃO É INSUMO PRESENTE. Um contador baseado em `IS NULL` só conta o que
    consegue chegar NULL até ele, e há TRÊS maneiras de a ausência se disfarçar de presença.
    A #41 desfez as três nos pontos alcançáveis de dentro dos modelos de premissas; ficam
    registradas aqui porque quem acrescentar premissa nova vai recriá-las sem perceber:

      (a) COALESCE para ZERO na própria `metrics`. Era o caso de n_wins_last5 e h2h_total
          (removidos na #41) e de s_missing/o_missing (removido na #42, que dependia do vazio
          registrado de data-engineering#33 para ter de onde tirar o NULL). Nenhuma das 37
          está fora do alcance do contador hoje (eram 39 até a #103 tirar as duas premissas
          de movimento de linha do Gols — ADR 0012). ⚠️ O zero de desfalque agora é MERECIDO —
          contagem real do time OU registro de coleta pré-apito (stg_futebol_injuries_coleta).
          Repor um COALESCE ali não deixa nada vermelho por si: devolve a cegueira ao estado
          de "premissa avaliada", que é o disfarce que esta classe descreve.
      (b) CONTAGEM sobre array vazio ou NULL — os `(SELECT COUNT(*) FROM UNNEST(last5_*))` de
          Gols, BTTS e Dupla Chance, e o n_wins_last5 que vem do team_form_pit. Devolvem 0 sem
          nenhum NULL para detectar, e o zero é indistinguível de "cinco jogos, nenhum deles
          bateu". Os modelos passaram a devolver NULL quando o ARRAY inteiro não existe.
          O que segue NÃO contado é o histórico CURTO (1 a 4 jogos): ele é medição real, só
          que de amostra pequena — questão de piso de amostra, não de ausência, e contá-la
          acenderia o contador em toda rodada 2 de toda liga.
      (c) BOOLEANO JÁ COLAPSADO — `linha_caiu` (Gols) e os `x_*` que a Dupla Chance reusa do
          1X2. Eram COALESCE(..., FALSE), ou seja, o mesmo colapso que a regra acima manda
          evitar, só que uma CTE antes. Gols passou a declarar as duas probabilidades de onde
          `linha_caiu` sai (numa janela distante o t15m ainda não existe, e é justamente no
          horizonte novo que o contador precisa falar); e a Dupla Chance passou a herdar a
          cegueira do 1X2 pela lista premissas_cegas de lá, em vez de herdar só o FALSE.

    Nada disso é pego por guarda de declaração: a assert_premissas_insumo_declarado compara
    NOMES contra o catálogo, e `aplicavel`/insumo vazio são erro de compilação no gerador —
    nenhum dos dois olha a SEMÂNTICA do insumo. Quem acrescentar premissa tem de olhar as três.
    Ver docs/adr/0003-dado-faltante-diagnostica-nao-elimina.md.

    QUARTA CHAVE — `regimes` (issue #148, ADR 0014): sob qual regime temporal/de competição cada
    insumo foi medido. Existe porque "qual insumo" (as três chaves acima) responde só metade da
    pergunta que motivou esta entrega — o front divergiu do modelo por 11 dias (#91, 25/08) não
    por ler o insumo errado, mas por adivinhar a JANELA errada em que ele foi medido. `escopo` e
    `recorte` (ADR 0007/0010) já são os nomes certos para isso — nunca "janela", que já nomeia a
    janela de coleta de odds (macros/taskf_eixos.sql). `regimes` é um dict `{nome_do_insumo:
    regime}`, chaveado pelo NOME do insumo (o `col` de uma entrada condicional, ou a própria
    string de uma entrada simples) — não embutido dentro de cada item de `insumos`, porque
    `futebol_premissas_cegas` usa `i is mapping` para distinguir insumo condicional de simples;
    transformar todo insumo simples em dict quebraria essa distinção em silêncio.

    QUATRO REGIMES, e a pergunta que cada um responde é "este insumo se move se eu trocar
    pit_escopo/pit_recorte?":

      pit               — segue o eixo (ADR 0007/0010). A MAIORIA dos insumos: tudo que vem de
                          int_futebol_team_form_pit ou de uma fonte de histórico própria que o
                          eixo explicitamente alcança (margin_stats do Handicap desde a #54,
                          team_hist da Dupla Chance, o spine de xG/ritmo e o last5 de Gols/BTTS).
                          Inclui os insumos em forma de "últimos 5" (last5_desc, historico_btts/
                          seco, historico_over/under): `recorte` satura neles (5 é subconjunto de
                          10 em qualquer ordem, então temporada->ultimos_10 não os move), mas
                          `escopo` os move — o pool de jogos elegíveis de onde os 5 são tirados é
                          filtrado por competição antes do corte. Por isso são `pit`, não um
                          regime à parte: a pergunta é "se move com ALGUM dos dois eixos", não
                          "se move com os dois".
      local_fixo        — temporal, mas independente do eixo: não se move nem com escopo nem com
                          recorte. Só h2h_favoravel/h2h_total/s_wins hoje — fact_h2h "já cruza
                          campeonatos hoje" incondicionalmente (não é o var pit_escopo que decide
                          isso) e não tem noção de recorte de contagem nem de temporada, só quantas
                          vezes os dois times já se enfrentaram.
      sempre_competicao — o oposto de `pit`: NUNCA solta a competição, mesmo sob escopo=todas.
                          superioridade_tabela (ADR 0008) e, no Handicap, supremacia/sem_rodizio
                          (rank/ppg/n_teams vêm do team_form_pit, que os mantém competição-scoped
                          em toda célula).
      sem_recorte       — não é temporal por natureza: presença/ausência, não histórico. Só
                          s_missing/o_missing (desfalque_adversario, desfalque_proprio) — vêm da
                          coleta de lesão pré-apito, não de um recorte de jogos passados.

    Validado em COMPILAÇÃO, não em teste de dado: todo insumo de premissa/penalidade com lista de
    insumos não-vazia precisa aparecer em `regimes` com um valor do enum. Isso é mais forte que
    uma guarda separada (`tag:guarda`) teria sido — a validação abaixo roda incondicionalmente
    para qualquer consumidor deste macro, então uma guarda de dado nunca conseguiria ficar
    vermelha sozinha (o `dbt compile` já teria falhado antes dela rodar). Uma guarda infalsificável
    por desenho é exatamente o anti-padrão que o cabeçalho de assert_premissas_insumo_declarado já
    descreve — por isso não foi criada uma segunda. Ver ADR 0014.

    ⚠️ O QUE ISTO NÃO VALIDA: se o regime declarado ainda é VERDADE sobre o SQL de hoje. A
    validação garante só a FORMA (todo insumo tem um valor do enum) — igual `aplicavel`/`insumos`
    não-vazio já garantem forma, nunca semântica, desde a #39. Se `int_futebol_team_form_pit.sql`
    ou um dos 5 modelos de premissa mudar de tal jeito que `s_rank` passe a seguir o eixo (hoje
    `sempre_competicao`, ADR 0008), nada aqui acusa — `dbt compile`/`dbt test` continuam verdes
    sobre um catálogo que virou documentação falsa, o mesmo modo de falha que fez o front divergir
    do modelo por 11 dias na origem da #148. Não existe verificação automática possível contra
    essa classe de deriva sem reimplementar a lógica de escopo/recorte numa segunda linguagem só
    para comparar — o preço seria maior que o problema. Manter `regimes` correto é disciplina de
    quem edita os 5 modelos de premissa: ao tocar de onde um insumo lê, conferir se o regime dele
    neste mapa ainda descreve a leitura nova. É a mesma disciplina que já existe para as três
    chaves anteriores. -#}
{#- O nome de um insumo, seja ele simples (string) ou condicional ({'col', 'quando'}). Único
    lugar que sabe extrair o nome — futebol_premissas_cegas (premissas_sem_dado.sql) e a
    validação de regimes abaixo chamam este macro em vez de repetir `i.col if i is mapping else
    i` cada um por conta própria. -#}
{% macro futebol_insumo_nome(i) -%}
    {{- i.col if i is mapping else i -}}
{%- endmacro %}

{#- ⚠️ CORRIGIDO na AE#153 (achado do code-review): `desfalque_proprio` (1X2) declarava
    'aplicavel': 'TRUE' em vez de "outcome <> 'Draw'", como toda premissa/penalidade do
    mercado que depende de lado apostado. Ficou inerte por builds porque nada checava
    'aplicavel' de tipo='penalidade' — futebol_premissas_cegas() só lê tipo='premissa'
    (ver macros/premissas_sem_dado.sql). futebol_insumos_medidos() (macros/
    premissas_valores_medidos.sql, mesma entrega) é o primeiro consumidor, e com 'TRUE'
    publicava desfalque_proprio/s_missing=0 num Draw — sem s_team_id, logo sem "próprio"
    nenhum — sempre que a coleta pré-apito existia pro fixture: `cl`
    (stg_futebol_injuries_coleta) casa só por fixture_id, não por time, em
    int_futebol_premissas_1x2.sql. -#}
{% macro futebol_insumos_premissa() %}
    {%- set ligas_pontos_corridos = 'competition IN ' ~ futebol_ligas_pontos_corridos_sql() %}
    {%- set regimes_validos = ['pit', 'local_fixo', 'sempre_competicao', 'sem_recorte'] %}
    {%- set mapa = [
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'forca_mismatch',       'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_gf_venue', 'o_ga_venue'], 'regimes': {'s_gf_venue': 'pit', 'o_ga_venue': 'pit'}},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'superioridade_xg',     'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_xg_for', 'o_xg_against'], 'regimes': {'s_xg_for': 'pit', 'o_xg_against': 'pit'}},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'mando',                'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': [{'col': 'pct_pts_home', 'quando': 's_is_home'}, {'col': 'aprov_fora', 'quando': 'NOT s_is_home'}], 'regimes': {'pct_pts_home': 'pit', 'aprov_fora': 'pit'}},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'desfalque_adversario', 'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_missing', 'o_missing'], 'regimes': {'s_missing': 'sem_recorte', 'o_missing': 'sem_recorte'}},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'superioridade_tabela', 'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_rank', 'o_rank', 's_ppg', 'o_ppg'], 'regimes': {'s_rank': 'sempre_competicao', 'o_rank': 'sempre_competicao', 's_ppg': 'sempre_competicao', 'o_ppg': 'sempre_competicao'}},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'forma',                'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['n_wins_last5'], 'regimes': {'n_wins_last5': 'pit'}},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'h2h_favoravel',        'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['h2h_total', 's_wins'], 'regimes': {'h2h_total': 'local_fixo', 's_wins': 'local_fixo'}},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'pick_empate',          'tipo': 'penalidade', 'aplicavel': 'TRUE',              'insumos': []},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'desfalque_proprio',    'tipo': 'penalidade', 'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_missing'], 'regimes': {'s_missing': 'sem_recorte'}},

        {'modelo': 'int_futebol_premissas_ah',  'nome': 'is_favorito',            'tipo': 'marcador',   'aplicavel': 'TRUE',                          'insumos': []},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'is_azarao',              'tipo': 'marcador',   'aplicavel': 'TRUE',                          'insumos': []},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'supremacia',             'tipo': 'premissa',   'aplicavel': 'is_favorito',                   'insumos': ['s_rank', 'o_rank', 's_ppg', 'o_ppg'], 'regimes': {'s_rank': 'sempre_competicao', 'o_rank': 'sempre_competicao', 's_ppg': 'sempre_competicao', 'o_ppg': 'sempre_competicao'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'tende_golear',           'tipo': 'premissa',   'aplicavel': 'is_favorito',                   'insumos': ['s_gf_venue', 's_ga_venue'], 'regimes': {'s_gf_venue': 'pit', 's_ga_venue': 'pit'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'adversario_fragil_fora', 'tipo': 'premissa',   'aplicavel': 'is_favorito',                   'insumos': ['o_ga_venue'], 'regimes': {'o_ga_venue': 'pit'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'mando_forte',            'tipo': 'premissa',   'aplicavel': 'is_favorito AND s_is_home',     'insumos': ['pct_pts_home'], 'regimes': {'pct_pts_home': 'pit'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'sem_rodizio',            'tipo': 'premissa',   'aplicavel': 'is_favorito AND ' ~ ligas_pontos_corridos, 'insumos': ['s_rank', 'n_teams'], 'regimes': {'s_rank': 'sempre_competicao', 'n_teams': 'sempre_competicao'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'raramente_perde_por_2',  'tipo': 'premissa',   'aplicavel': 'is_azarao',                     'insumos': ['s_n_games', 's_lost2'], 'regimes': {'s_n_games': 'pit', 's_lost2': 'pit'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'defesa_fora_solida',     'tipo': 'premissa',   'aplicavel': 'is_azarao',                     'insumos': ['s_ga_venue'], 'regimes': {'s_ga_venue': 'pit'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'favorito_irregular',     'tipo': 'premissa',   'aplicavel': 'is_azarao',                     'insumos': ['o_n_games', 'o_won2'], 'regimes': {'o_n_games': 'pit', 'o_won2': 'pit'}},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'handicap_alto',          'tipo': 'penalidade', 'aplicavel': 'TRUE',                          'insumos': []},

        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ambos_marcam',     'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_fts_pct', 'away_fts_pct'], 'regimes': {'home_fts_pct': 'pit', 'away_fts_pct': 'pit'}},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ataque_dos_dois',  'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_gf', 'away_gf'], 'regimes': {'home_gf': 'pit', 'away_gf': 'pit'}},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'defesas_vazaveis', 'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_cs_pct', 'away_cs_pct'], 'regimes': {'home_cs_pct': 'pit', 'away_cs_pct': 'pit'}},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'historico_btts',   'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_btts_cnt', 'away_btts_cnt'], 'regimes': {'home_btts_cnt': 'pit', 'away_btts_cnt': 'pit'}},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'defesa_forte',     'tipo': 'premissa', 'aplicavel': "outcome = 'No'",  'insumos': ['home_cs_pct', 'away_cs_pct'], 'regimes': {'home_cs_pct': 'pit', 'away_cs_pct': 'pit'}},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ataque_trava',     'tipo': 'premissa', 'aplicavel': "outcome = 'No'",  'insumos': ['home_fts_pct', 'away_fts_pct'], 'regimes': {'home_fts_pct': 'pit', 'away_fts_pct': 'pit'}},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'historico_seco',   'tipo': 'premissa', 'aplicavel': "outcome = 'No'",  'insumos': ['home_no_btts_cnt', 'away_no_btts_cnt'], 'regimes': {'home_no_btts_cnt': 'pit', 'away_no_btts_cnt': 'pit'}},

        {'modelo': 'int_futebol_premissas_dc', 'nome': 'lado_coberto_forte',   'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['x_forca_mismatch', 'x_superioridade_tabela'], 'regimes': {'x_forca_mismatch': 'pit', 'x_superioridade_tabela': 'sempre_competicao'}},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'equilibrio_defensivo', 'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['s_ga_total', 'o_ga_total', 's_thrash_rate', 'o_thrash_rate'], 'regimes': {'s_ga_total': 'pit', 'o_ga_total': 'pit', 's_thrash_rate': 'pit', 'o_thrash_rate': 'pit'}},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'adversario_limitado',  'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['o_aproveitamento', 'x_h2h_favoravel'], 'regimes': {'o_aproveitamento': 'pit', 'x_h2h_favoravel': 'local_fixo'}},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'invicto_recente',      'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['s_games_last5', 's_losses_last5'], 'regimes': {'s_games_last5': 'pit', 's_losses_last5': 'pit'}},

        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ataque_combinado',   'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['gf_comb'], 'regimes': {'gf_comb': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'defesas_vazaveis',   'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['ga_comb'], 'regimes': {'ga_comb': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'xg_combinado_alto',  'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['xg_comb'], 'regimes': {'xg_comb': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ritmo_alto',         'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['pace_both', 'pace_median'], 'regimes': {'pace_both': 'pit', 'pace_median': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ambos_vazam',        'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['home_cs_pct', 'away_cs_pct'], 'regimes': {'home_cs_pct': 'pit', 'away_cs_pct': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'historico_over',     'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['home_over_cnt', 'away_over_cnt'], 'regimes': {'home_over_cnt': 'pit', 'away_over_cnt': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'defesas_firmes',     'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['ga_comb'], 'regimes': {'ga_comb': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'clean_sheets_altos', 'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['home_cs_pct', 'away_cs_pct'], 'regimes': {'home_cs_pct': 'pit', 'away_cs_pct': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'xg_baixo_combinado', 'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['xg_comb'], 'regimes': {'xg_comb': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ataques_fracos',     'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['home_fts_pct', 'away_fts_pct'], 'regimes': {'home_fts_pct': 'pit', 'away_fts_pct': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'historico_under',    'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['home_under_cnt', 'away_under_cnt'], 'regimes': {'home_under_cnt': 'pit', 'away_under_cnt': 'pit'}},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'linha_extrema',      'tipo': 'penalidade', 'aplicavel': 'TRUE',              'insumos': []}
    ] %}

    {#- Validação fail-closed (issue #148): todo insumo de premissa/penalidade com lista de
        insumos não-vazia precisa de regime declarado e válido. Roda em toda invocação deste
        macro, então qualquer `dbt compile`/`dbt run`/`dbt test` que dependa dele já barra a
        entrada malformada — não precisa de guarda de dado separada (ver cabeçalho acima). -#}
    {%- for p in mapa %}
        {%- if p.tipo in ['premissa', 'penalidade'] and (p.insumos | length) > 0 %}
            {%- set nomes_insumo = [] %}
            {%- for i in p.insumos %}
                {%- do nomes_insumo.append(futebol_insumo_nome(i)) %}
            {%- endfor %}
            {%- set regimes = p.get('regimes', {}) %}
            {%- for nome in nomes_insumo %}
                {%- if nome not in regimes %}
                    {{ exceptions.raise_compiler_error(
                        "futebol_insumos_premissa: '" ~ p.nome ~ "' (" ~ p.modelo ~ ") não declara "
                        "regime para o insumo '" ~ nome ~ "'. Todo insumo de premissa/penalidade "
                        "precisa de um regime em 'regimes': " ~ regimes_validos | join(' | ')) }}
                {%- elif regimes[nome] not in regimes_validos %}
                    {{ exceptions.raise_compiler_error(
                        "futebol_insumos_premissa: regime inválido '" ~ regimes[nome] ~ "' para o "
                        "insumo '" ~ nome ~ "' de '" ~ p.nome ~ "' (" ~ p.modelo ~ "). Valores "
                        "aceitos: " ~ regimes_validos | join(' | ')) }}
                {%- endif %}
            {%- endfor %}
        {%- endif %}
    {%- endfor %}

    {{ return(mapa) }}
{% endmacro %}
