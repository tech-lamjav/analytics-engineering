{#- FONTE ÚNICA do insumo de cada premissa do Motor de Score.

    Uma premissa que não acende pode ser duas coisas muito diferentes: o sinal foi medido e
    não estava lá, ou o sinal nunca pôde ser medido. Hoje as duas viram o mesmo score mais
    baixo, e o leitor não tem como separar pouca informação de informação contrária. Contar a
    segunda é o trabalho da ADR 0003 — e este macro é de onde a contagem sai.

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

    OS INSUMOS SÃO NOMES DA CTE `metrics` de cada modelo, não colunas da saída. É lá que a
    nulidade tem de ser lida — a premissa já chega ao SELECT final como booleano, e nesse
    ponto "não acendeu" e "não pôde ser avaliada" já colapsaram num FALSE só.

    ⚠️ INSUMO NÃO-NULO NÃO É INSUMO PRESENTE, e é por isso que este mapa sozinho não faz o
    contador funcionar. Um contador baseado em `IS NULL` nasce ZERADO por construção enquanto
    os insumos chegarem preenchidos. São TRÊS classes, e a terceira é a pior:

      (a) COALESCE para ZERO na própria `metrics` — s_missing e o_missing, n_wins_last5,
          h2h_total. Nomeadas na ADR 0003; sair delas é o trabalho de #41 e #42.
      (b) CONTAGEM sobre array vazio ou NULL — home_btts_cnt, home_over_cnt, home_under_cnt,
          s_losses_last5 e irmãs, todas de UNNEST(last5_*). Devolvem 0 sem nenhum NULL para
          detectar, e o zero é indistinguível de "cinco jogos, nenhum deles bateu".
      (c) BOOLEANO JÁ COLAPSADO — x_forca_mismatch, x_superioridade_tabela e x_h2h_favoravel
          (Dupla Chance, reusados do 1X2) e linha_caiu (Gols). Todos são COALESCE(..., FALSE),
          ou seja, exatamente o colapso que a regra acima manda evitar, só que acontecendo uma
          CTE antes. A Dupla Chance herda o FALSE de premissas do 1X2 que podem elas mesmas
          não ter podido ser avaliadas, então a cegueira atravessa dois modelos sem deixar
          rastro. E linha_caiu compara t15m contra t24h: numa janela distante o t15m ainda não
          existe, então linha_subindo e linha_descendo ficam permanentemente cegas justamente
          no horizonte novo, que é onde o contador mais precisa falar.

    A guarda não pega nenhuma das três — ela valida nome e não-vazio, não a semântica do
    insumo. Quem consumir este mapa tem de tratar as três, não só a (a).
    Ver docs/adr/0003-dado-faltante-diagnostica-nao-elimina.md. -#}
{% macro futebol_insumos_premissa() %}
    {{ return([
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'forca_mismatch',       'tipo': 'premissa',   'insumos': ['s_gf_venue', 'o_ga_venue']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'superioridade_xg',     'tipo': 'premissa',   'insumos': ['s_xg_for', 'o_xg_against']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'mando',                'tipo': 'premissa',   'insumos': ['pct_pts_home', 'aprov_fora']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'desfalque_adversario', 'tipo': 'premissa',   'insumos': ['s_missing', 'o_missing']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'superioridade_tabela', 'tipo': 'premissa',   'insumos': ['s_rank', 'o_rank', 's_ppg', 'o_ppg']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'forma',                'tipo': 'premissa',   'insumos': ['n_wins_last5']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'h2h_favoravel',        'tipo': 'premissa',   'insumos': ['h2h_total', 's_wins']},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'pick_empate',          'tipo': 'penalidade', 'insumos': []},
        {'modelo': 'int_futebol_premissas_1x2', 'nome': 'desfalque_proprio',    'tipo': 'penalidade', 'insumos': ['s_missing']},

        {'modelo': 'int_futebol_premissas_ah',  'nome': 'is_favorito',            'tipo': 'marcador',   'insumos': []},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'is_azarao',              'tipo': 'marcador',   'insumos': []},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'supremacia',             'tipo': 'premissa',   'insumos': ['s_rank', 'o_rank', 's_ppg', 'o_ppg']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'tende_golear',           'tipo': 'premissa',   'insumos': ['s_gf_venue', 's_ga_venue']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'adversario_fragil_fora', 'tipo': 'premissa',   'insumos': ['o_ga_venue']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'mando_forte',            'tipo': 'premissa',   'insumos': ['pct_pts_home']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'sem_rodizio',            'tipo': 'premissa',   'insumos': ['s_rank', 'n_teams']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'raramente_perde_por_2',  'tipo': 'premissa',   'insumos': ['s_n_games', 's_lost2']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'defesa_fora_solida',     'tipo': 'premissa',   'insumos': ['s_ga_venue']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'favorito_irregular',     'tipo': 'premissa',   'insumos': ['o_n_games', 'o_won2']},
        {'modelo': 'int_futebol_premissas_ah',  'nome': 'handicap_alto',          'tipo': 'penalidade', 'insumos': []},

        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ambos_marcam',     'tipo': 'premissa', 'insumos': ['home_fts_pct', 'away_fts_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ataque_dos_dois',  'tipo': 'premissa', 'insumos': ['home_gf', 'away_gf']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'defesas_vazaveis', 'tipo': 'premissa', 'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'historico_btts',   'tipo': 'premissa', 'insumos': ['home_btts_cnt', 'away_btts_cnt']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'defesa_forte',     'tipo': 'premissa', 'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'ataque_trava',     'tipo': 'premissa', 'insumos': ['home_fts_pct', 'away_fts_pct']},
        {'modelo': 'int_futebol_premissas_btts', 'nome': 'historico_seco',   'tipo': 'premissa', 'insumos': ['home_no_btts_cnt', 'away_no_btts_cnt']},

        {'modelo': 'int_futebol_premissas_dc', 'nome': 'lado_coberto_forte',   'tipo': 'premissa', 'insumos': ['x_forca_mismatch', 'x_superioridade_tabela']},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'equilibrio_defensivo', 'tipo': 'premissa', 'insumos': ['s_ga_total', 'o_ga_total', 's_thrash_rate', 'o_thrash_rate']},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'adversario_limitado',  'tipo': 'premissa', 'insumos': ['o_aproveitamento', 'x_h2h_favoravel']},
        {'modelo': 'int_futebol_premissas_dc', 'nome': 'invicto_recente',      'tipo': 'premissa', 'insumos': ['s_games_last5', 's_losses_last5']},

        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ataque_combinado',   'tipo': 'premissa',   'insumos': ['gf_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'defesas_vazaveis',   'tipo': 'premissa',   'insumos': ['ga_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'xg_combinado_alto',  'tipo': 'premissa',   'insumos': ['xg_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ritmo_alto',         'tipo': 'premissa',   'insumos': ['pace_both', 'pace_median']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ambos_vazam',        'tipo': 'premissa',   'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'historico_over',     'tipo': 'premissa',   'insumos': ['home_over_cnt', 'away_over_cnt']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'linha_subindo',      'tipo': 'premissa',   'insumos': ['linha_caiu']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'defesas_firmes',     'tipo': 'premissa',   'insumos': ['ga_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'clean_sheets_altos', 'tipo': 'premissa',   'insumos': ['home_cs_pct', 'away_cs_pct']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'xg_baixo_combinado', 'tipo': 'premissa',   'insumos': ['xg_comb']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'ataques_fracos',     'tipo': 'premissa',   'insumos': ['home_fts_pct', 'away_fts_pct']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'historico_under',    'tipo': 'premissa',   'insumos': ['home_under_cnt', 'away_under_cnt']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'linha_descendo',     'tipo': 'premissa',   'insumos': ['linha_caiu']},
        {'modelo': 'int_futebol_premissas_ou', 'nome': 'linha_extrema',      'tipo': 'penalidade', 'insumos': []}
    ]) }}
{% endmacro %}
