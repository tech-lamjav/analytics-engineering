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
          registrado de data-engineering#33 para ter de onde tirar o NULL). Nenhuma das 39
          está fora do alcance do contador hoje. ⚠️ O zero de desfalque agora é MERECIDO —
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
    Ver docs/adr/0003-dado-faltante-diagnostica-nao-elimina.md. -#}
{% macro futebol_insumos_premissa() %}
    {%- set ligas_pontos_corridos = 'competition IN ' ~ futebol_ligas_pontos_corridos_sql() %}
    {{ return([
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'forca_mismatch',       'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_gf_venue', 'o_ga_venue']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'superioridade_xg',     'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_xg_for', 'o_xg_against']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'mando',                'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': [{'col': 'pct_pts_home', 'quando': 's_is_home'}, {'col': 'aprov_fora', 'quando': 'NOT s_is_home'}]},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'desfalque_adversario', 'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_missing', 'o_missing']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'superioridade_tabela', 'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['s_rank', 'o_rank', 's_ppg', 'o_ppg']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'forma',                'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['n_wins_last5']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'h2h_favoravel',        'tipo': 'premissa',   'aplicavel': "outcome <> 'Draw'", 'insumos': ['h2h_total', 's_wins']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'pick_empate',          'tipo': 'penalidade', 'aplicavel': 'TRUE',              'insumos': []},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'desfalque_proprio',    'tipo': 'penalidade', 'aplicavel': 'TRUE',              'insumos': ['s_missing']},

        {'modelo': 'int_futebol_premissas_ah',  'nome': 'is_favorito',            'tipo': 'marcador',   'aplicavel': 'TRUE',                          'insumos': []},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'is_azarao',              'tipo': 'marcador',   'aplicavel': 'TRUE',                          'insumos': []},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'supremacia',             'tipo': 'premissa',   'aplicavel': 'is_favorito',                   'insumos': ['s_rank', 'o_rank', 's_ppg', 'o_ppg']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'tende_golear',           'tipo': 'premissa',   'aplicavel': 'is_favorito',                   'insumos': ['s_gf_venue', 's_ga_venue']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'adversario_fragil_fora', 'tipo': 'premissa',   'aplicavel': 'is_favorito',                   'insumos': ['o_ga_venue']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'mando_forte',            'tipo': 'premissa',   'aplicavel': 'is_favorito AND s_is_home',     'insumos': ['pct_pts_home']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'sem_rodizio',            'tipo': 'premissa',   'aplicavel': 'is_favorito AND ' ~ ligas_pontos_corridos, 'insumos': ['s_rank', 'n_teams']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'raramente_perde_por_2',  'tipo': 'premissa',   'aplicavel': 'is_azarao',                     'insumos': ['s_n_games', 's_lost2']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'defesa_fora_solida',     'tipo': 'premissa',   'aplicavel': 'is_azarao',                     'insumos': ['s_ga_venue']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'favorito_irregular',     'tipo': 'premissa',   'aplicavel': 'is_azarao',                     'insumos': ['o_n_games', 'o_won2']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'handicap_alto',          'tipo': 'penalidade', 'aplicavel': 'TRUE',                          'insumos': []},

        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ambos_marcam',     'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_fts_pct', 'away_fts_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ataque_dos_dois',  'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_gf', 'away_gf']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'defesas_vazaveis', 'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'historico_btts',   'tipo': 'premissa', 'aplicavel': "outcome = 'Yes'", 'insumos': ['home_btts_cnt', 'away_btts_cnt']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'defesa_forte',     'tipo': 'premissa', 'aplicavel': "outcome = 'No'",  'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ataque_trava',     'tipo': 'premissa', 'aplicavel': "outcome = 'No'",  'insumos': ['home_fts_pct', 'away_fts_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'historico_seco',   'tipo': 'premissa', 'aplicavel': "outcome = 'No'",  'insumos': ['home_no_btts_cnt', 'away_no_btts_cnt']},

        {'modelo': 'int_futebol_premissas_dc', 'nome': 'lado_coberto_forte',   'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['x_forca_mismatch', 'x_superioridade_tabela']},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'equilibrio_defensivo', 'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['s_ga_total', 'o_ga_total', 's_thrash_rate', 'o_thrash_rate']},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'adversario_limitado',  'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['o_aproveitamento', 'x_h2h_favoravel']},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'invicto_recente',      'tipo': 'premissa', 'aplicavel': 'TRUE', 'insumos': ['s_games_last5', 's_losses_last5']},

        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ataque_combinado',   'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['gf_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'defesas_vazaveis',   'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['ga_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'xg_combinado_alto',  'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['xg_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ritmo_alto',         'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['pace_both', 'pace_median']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ambos_vazam',        'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'historico_over',     'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['home_over_cnt', 'away_over_cnt']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'linha_subindo',      'tipo': 'premissa',   'aplicavel': "outcome = 'Over'",  'insumos': ['prob_t24h', 'prob_t15m']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'defesas_firmes',     'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['ga_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'clean_sheets_altos', 'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'xg_baixo_combinado', 'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['xg_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ataques_fracos',     'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['home_fts_pct', 'away_fts_pct']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'historico_under',    'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['home_under_cnt', 'away_under_cnt']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'linha_descendo',     'tipo': 'premissa',   'aplicavel': "outcome = 'Under'", 'insumos': ['prob_t24h', 'prob_t15m']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'linha_extrema',      'tipo': 'penalidade', 'aplicavel': 'TRUE',              'insumos': []}
    ]) }}
{% endmacro %}
