{#- DE ONDE CADA PREMISSA PUXA O HISTÓRICO — as três colunas QUALITATIVAS do entregável da
    task [F] (#59), declaradas num lugar só.

    O ticket de origem (ClickUp `wdx6zevnhy`) pede quatro colunas por premissa:

      1. de onde puxa o histórico          -> `fonte` + `predicado`
      2. se a janela é limitada à competição -> `escopo_hoje`
      3. se dá para juntar, e o que impede -> `juntavel` + `impedimento`
      4. o que o número vira               -> NÃO mora aqui: sai da medição
                                              (futebol_taskF.taskf_teste2, células `base` e
                                              `escopo`), lida por analyses/taskf_entregavel.sql

    A quarta é medida e as três primeiras são lidas do código — por isso elas são declaração, e
    não query. Mas declaração que ninguém confere apodrece no primeiro modelo que mudar, e o
    apodrecimento aqui seria MUDO: a tabela do entregável continuaria com 39 linhas bonitas
    descrevendo um pipeline que já não é o que roda. Duas defesas, nesta ordem:

      COMPILAÇÃO (aqui). O conjunto (mercado, premissa) declarado tem de ser EXATAMENTE o que
      futebol_insumos_premissa() lista como `tipo = 'premissa'`, traduzido de modelo para mercado
      por task01_markets() — as duas fontes que a própria medição já usa. Sobra ou falta levanta
      erro de compilação, no padrão fail-closed de taskf_eixos(). É o que pega premissa NOVA (o
      caso provável: alguém acrescenta uma premissa e ninguém lembra desta tabela).

      ⚠️ E ela NÃO depende de alguém compilar a análise à mão: o erro sobe já no `dbt parse`,
      porque a análise é nó do manifesto e o Jinja dela é renderizado ali. Medido, trocando
      `ritmo_alto` por um nome inexistente — `dbt parse` sai com código 2 e a mensagem desta
      macro. Como o workflow de docs roda `dbt docs generate`, que parseia o projeto inteiro, a
      quebra aparece no CI mesmo que ninguém rode esta análise.

      LEITURA (analyses/taskf_entregavel.sql). A declaração é confrontada com a MEDIÇÃO: quem
      está declarado como imóvel (`nao` / `ja_junto` / `nao_se_aplica`) tem de sair com número
      idêntico entre `base` e `escopo` no piso 0, e quem está declarado `sim` tem de se mexer. É
      o que pega declaração ERRADA — o caso que nenhuma checagem de nome alcança.

    ⚠️ DUAS LINHAS SAÍRAM NA #103 (ADR 0012). `Gols · linha_subindo` e `Gols · linha_descendo`
    eram as duas únicas famílias das 39 cujo insumo não era jogo anterior — elas liam PREÇO —, e
    a A1 as removeu do `int_futebol_premissas_ou`. A validação de compilação acima é o que cobrou
    esta edição: sem ela o `dbt parse` sai com código 2, que é a defesa funcionando.

    Daqui em diante o entregável tem 37 linhas, não 39. As 39 PUBLICADAS continuam publicadas —
    docs/TASKF_RESULTADOS.md é registro do que foi medido em 12–13/08, e nada aqui o reescreve.

    ⚠️ CHAVE É (mercado, premissa), NUNCA premissa sozinha. `defesas_vazaveis` existe no BTTS e
    no Gols, com vereditos opostos na [0.1], e chavear por nome ou funde as duas ou multiplica a
    tabela — as 39 linhas viram 38 ou 40 sem ninguém notar.

    ────────────────────────────────────────────────────────────────────────────────
    OS NOVE PREDICADOS DE ESCOPO (#52). O eixo `pit_escopo` da medição solta `competition_id`
    em nove sites, e é a eles que a coluna `predicado` aponta:

      team_form_pit          o join do `team_log` (dois ramos: `pares` sob recorte de contagem,
                             `pit` sob temporada) — a fonte de longe mais consumida
      premissas_1x2.spine    o spine de xG do 1X2
      premissas_ah.margin    o `margin_stats` (⚠️ o único SEM filtro de season no default)
      premissas_btts.last5   os últimos 5 de BTTS
      premissas_dc.hist      o `team_hist` (thrash_rate + last5_lost)
      premissas_ou.spine     o spine de xG e de ritmo do Gols
      premissas_ou.pool      o histórico dos times do pool da mediana de ritmo
      premissas_ou.last5     os últimos 5 de gols

    `nenhum` marca as fontes que o eixo NÃO alcança, e elas são de três tipos diferentes — a
    tabela do campeonato (ADR 0008), o `fact_h2h` (já cruza) e o que não é histórico (boletim de
    desfalques e preço). A distinção está em `juntavel`, não em `predicado`.

    ────────────────────────────────────────────────────────────────────────────────
    VALORES ACEITOS

    `escopo_hoje` — a resposta à segunda coluna do ticket:
      competicao_e_temporada  o histórico é filtrado por competição E season (o caso comum)
      competicao              filtrado só por competição: já atravessa temporada hoje
      cruza_tudo              não é filtrado por nenhum dos dois
      sem_historico           a premissa não lê passado
      misto                   insumos de escopos diferentes na mesma premissa

    `juntavel` — a resposta à terceira:
      sim            o eixo de escopo alcança e o número muda
      nao            há impedimento de definição; `impedimento` diz qual (obrigatório)
      ja_junto       não há o que juntar: a fonte já cruza campeonatos hoje
      nao_se_aplica  não lê histórico, então a pergunta não incide

    `ressalva` é o que o leitor precisa saber para não tirar a conclusão errada da linha. Fica
    separado de `impedimento` de propósito: impedimento é o que BARRA o merge, ressalva é o que
    qualifica um merge que acontece.
-#}

{% macro taskf_fontes_de_historico() %}

    {%- set fontes = [
        {'mercado': '1X2', 'premissa': 'forca_mismatch',
         'fonte': 'int_futebol_team_form_pit · gols pró/contra por venue',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': '1X2', 'premissa': 'superioridade_xg',
         'fonte': 'int_futebol_premissas_1x2 · spine de xG sobre fact_fixture_stats',
         'predicado': 'premissas_1x2.spine',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'xG não é coletado em toda competição; juntar o escopo não cria a cobertura que falta'},
        {'mercado': '1X2', 'premissa': 'mando',
         'fonte': 'int_futebol_team_form_pit · aproveitamento em casa e fora',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': '1X2', 'premissa': 'desfalque_adversario',
         'fonte': 'int_futebol_desfalques · boletim do próprio jogo',
         'predicado': 'nenhum',
         'escopo_hoje': 'sem_historico', 'juntavel': 'nao_se_aplica',
         'impedimento': '',
         'ressalva': 'conta desfalque importante no jogo avaliado; não lê passado nenhum'},
        {'mercado': '1X2', 'premissa': 'superioridade_tabela',
         'fonte': 'int_futebol_team_form_pit · CTE `tabela` (rank e ppg)',
         'predicado': 'nenhum',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'nao',
         'impedimento': 'classificação só existe dentro de uma competição: não há rank num histórico juntado (ADR 0008)',
         'ressalva': 'a alternativa séria — eleger uma competição principal por time — muda a definição da premissa e ficou para a [B]'},
        {'mercado': '1X2', 'premissa': 'forma',
         'fonte': 'int_futebol_team_form_pit · vitórias nos 5 jogos anteriores',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': '1X2', 'premissa': 'h2h_favoravel',
         'fonte': 'fact_h2h · confronto direto',
         'predicado': 'nenhum',
         'escopo_hoje': 'cruza_tudo', 'juntavel': 'ja_junto',
         'impedimento': '',
         'ressalva': 'o join é por par de times e kickoff anterior, sem competição nem season — é a única fonte imune ao efeito medido'},

        {'mercado': 'Handicap', 'premissa': 'supremacia',
         'fonte': 'int_futebol_team_form_pit · CTE `tabela` (rank e ppg)',
         'predicado': 'nenhum',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'nao',
         'impedimento': 'classificação só existe dentro de uma competição: não há rank num histórico juntado (ADR 0008)',
         'ressalva': ''},
        {'mercado': 'Handicap', 'premissa': 'tende_golear',
         'fonte': 'int_futebol_team_form_pit · gols pró/contra por venue',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Handicap', 'premissa': 'adversario_fragil_fora',
         'fonte': 'int_futebol_team_form_pit · gols sofridos do adversário por venue',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Handicap', 'premissa': 'mando_forte',
         'fonte': 'int_futebol_team_form_pit · aproveitamento em casa',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Handicap', 'premissa': 'sem_rodizio',
         'fonte': 'int_futebol_team_form_pit · CTE `tabela` (rank) e tamanho da liga',
         'predicado': 'nenhum',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'nao',
         'impedimento': 'compara o rank contra o número de times da liga — nem o rank nem o `n_teams` existem num histórico juntado (ADR 0008)',
         'ressalva': 'é a mais rígida das quatro de tabela: só acende em liga de pontos corridos, e por isso não se mexe em nenhum piso'},
        {'mercado': 'Handicap', 'premissa': 'raramente_perde_por_2',
         'fonte': 'int_futebol_premissas_ah · `margin_stats` sobre resultados anteriores',
         'predicado': 'premissas_ah.margin',
         'escopo_hoje': 'competicao', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'o `margin_stats` não filtra season nem hoje: já atravessa temporada, então aqui o eixo de recorte ENCOLHE o histórico em vez de alargá-lo'},
        {'mercado': 'Handicap', 'premissa': 'defesa_fora_solida',
         'fonte': 'int_futebol_team_form_pit · gols sofridos por venue',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Handicap', 'premissa': 'favorito_irregular',
         'fonte': 'int_futebol_premissas_ah · `margin_stats` sobre resultados anteriores',
         'predicado': 'premissas_ah.margin',
         'escopo_hoje': 'competicao', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'mesma do `raramente_perde_por_2`: a fonte já atravessa temporada, e sob recorte ela encolhe'},

        {'mercado': 'BTTS', 'premissa': 'ambos_marcam',
         'fonte': 'int_futebol_team_form_pit · failed-to-score% dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'BTTS', 'premissa': 'ataque_dos_dois',
         'fonte': 'int_futebol_team_form_pit · gols feitos por venue',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'BTTS', 'premissa': 'defesas_vazaveis',
         'fonte': 'int_futebol_team_form_pit · clean sheet% dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'homônima da do Gols, com insumo e veredito próprios — as duas linhas não são a mesma premissa'},
        {'mercado': 'BTTS', 'premissa': 'historico_btts',
         'fonte': 'int_futebol_premissas_btts · últimos 5 jogos com os dois marcando',
         'predicado': 'premissas_btts.last5',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'BTTS', 'premissa': 'defesa_forte',
         'fonte': 'int_futebol_team_form_pit · clean sheet% dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'BTTS', 'premissa': 'ataque_trava',
         'fonte': 'int_futebol_team_form_pit · failed-to-score% dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'BTTS', 'premissa': 'historico_seco',
         'fonte': 'int_futebol_premissas_btts · últimos 5 jogos sem os dois marcarem',
         'predicado': 'premissas_btts.last5',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},

        {'mercado': 'Dupla Chance', 'premissa': 'lado_coberto_forte',
         'fonte': 'int_futebol_premissas_1x2 · reuso de forca_mismatch OU superioridade_tabela',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'misto', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'metade juntável: `forca_mismatch` segue o eixo, `superioridade_tabela` não (ADR 0008) — e o OR basta para a premissa se mexer'},
        {'mercado': 'Dupla Chance', 'premissa': 'equilibrio_defensivo',
         'fonte': 'int_futebol_team_form_pit · gols sofridos + `team_hist` do DC (goleadas)',
         'predicado': 'premissas_dc.hist',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Dupla Chance', 'premissa': 'adversario_limitado',
         'fonte': 'int_futebol_team_form_pit · aproveitamento do adversário OU h2h reusado do 1X2',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'misto', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'reusa a única fonte imune (h2h) e ainda assim se mexe: imunidade só se herda quando TODOS os insumos são imunes'},
        {'mercado': 'Dupla Chance', 'premissa': 'invicto_recente',
         'fonte': 'int_futebol_premissas_dc · `team_hist` (derrotas nos últimos 5)',
         'predicado': 'premissas_dc.hist',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},

        {'mercado': 'Gols', 'premissa': 'ataque_combinado',
         'fonte': 'int_futebol_team_form_pit · gols feitos por venue dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Gols', 'premissa': 'defesas_vazaveis',
         'fonte': 'int_futebol_team_form_pit · gols sofridos por venue dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'homônima da do BTTS, com insumo e veredito próprios — as duas linhas não são a mesma premissa'},
        {'mercado': 'Gols', 'premissa': 'xg_combinado_alto',
         'fonte': 'int_futebol_premissas_ou · spine de xG sobre fact_fixture_stats',
         'predicado': 'premissas_ou.spine',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'xG não é coletado em toda competição; juntar o escopo não cria a cobertura que falta'},
        {'mercado': 'Gols', 'premissa': 'ritmo_alto',
         'fonte': 'int_futebol_premissas_ou · ritmo dos dois times contra a mediana da liga',
         'predicado': 'premissas_ou.pool',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'o POOL de times da mediana segue a competição do jogo em qualquer célula (é o benchmark "a liga em que estou jogando"); o que junta é o histórico de cada time do pool'},
        {'mercado': 'Gols', 'premissa': 'ambos_vazam',
         'fonte': 'int_futebol_team_form_pit · clean sheet% dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Gols', 'premissa': 'historico_over',
         'fonte': 'int_futebol_premissas_ou · total de gols dos últimos 5 jogos',
         'predicado': 'premissas_ou.last5',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Gols', 'premissa': 'defesas_firmes',
         'fonte': 'int_futebol_team_form_pit · gols sofridos por venue dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Gols', 'premissa': 'clean_sheets_altos',
         'fonte': 'int_futebol_team_form_pit · clean sheet% dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Gols', 'premissa': 'xg_baixo_combinado',
         'fonte': 'int_futebol_premissas_ou · spine de xG sobre fact_fixture_stats',
         'predicado': 'premissas_ou.spine',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '',
         'ressalva': 'xG não é coletado em toda competição; juntar o escopo não cria a cobertura que falta'},
        {'mercado': 'Gols', 'premissa': 'ataques_fracos',
         'fonte': 'int_futebol_team_form_pit · failed-to-score% dos dois times',
         'predicado': 'team_form_pit',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''},
        {'mercado': 'Gols', 'premissa': 'historico_under',
         'fonte': 'int_futebol_premissas_ou · total de gols dos últimos 5 jogos',
         'predicado': 'premissas_ou.last5',
         'escopo_hoje': 'competicao_e_temporada', 'juntavel': 'sim',
         'impedimento': '', 'ressalva': ''}
    ] -%}

    {#- ── A validação, nos DOIS sentidos ──────────────────────────────────────────────
        O conjunto declarado tem de ser idêntico ao que a medição mede. As duas listas de
        referência são as MESMAS que o taskf_teste2 usa: futebol_insumos_premissa() diz quais
        colunas são premissa, e task01_markets() traduz modelo em mercado. Nenhuma terceira
        cópia é digitada aqui — cópia que precisa ficar igual para sempre não fica. -#}
    {%- set modelo_para_mercado = {} -%}
    {%- for _, m in task01_markets().items() -%}
        {%- do modelo_para_mercado.update({m.model: m.nome}) -%}
    {%- endfor -%}

    {%- set esperadas = [] -%}
    {%- for p in futebol_insumos_premissa() if p.tipo == 'premissa' -%}
        {%- do esperadas.append(modelo_para_mercado[p.modelo] ~ ' · ' ~ p.nome) -%}
    {%- endfor -%}

    {%- set declaradas = [] -%}
    {%- for f in fontes -%}
        {%- do declaradas.append(f.mercado ~ ' · ' ~ f.premissa) -%}
    {%- endfor -%}

    {%- set faltando = esperadas | reject('in', declaradas) | list -%}
    {%- set sobrando = declaradas | reject('in', esperadas) | list -%}
    {%- if faltando or sobrando -%}
        {{ exceptions.raise_compiler_error(
            "taskf_fontes_de_historico() saiu de sincronia com as premissas medidas. "
            ~ "Sem declaração: [" ~ faltando | join(', ') ~ "]. "
            ~ "Declarada mas não medida: [" ~ sobrando | join(', ') ~ "]. "
            ~ "A fonte da verdade é futebol_insumos_premissa() (tipo='premissa') traduzida por "
            ~ "task01_markets(); acrescente ou remova a linha aqui.") }}
    {%- endif -%}
    {#- Duplicata passaria pelas duas listas acima (as duas direções ficariam vazias) e só
        apareceria como linha repetida na tabela do entregável. -#}
    {%- if declaradas | unique | list | length != declaradas | length -%}
        {{ exceptions.raise_compiler_error(
            "taskf_fontes_de_historico() tem (mercado, premissa) repetido — a chave é o par, e "
            ~ "duplicata vira linha a mais na tabela de 39.") }}
    {%- endif -%}

    {%- for f in fontes -%}
        {%- if f.escopo_hoje not in ['competicao_e_temporada', 'competicao', 'cruza_tudo',
                                     'sem_historico', 'misto'] -%}
            {{ exceptions.raise_compiler_error(
                "escopo_hoje inválido em '" ~ f.mercado ~ " · " ~ f.premissa ~ "': '"
                ~ f.escopo_hoje ~ "'.") }}
        {%- endif -%}
        {%- if f.juntavel not in ['sim', 'nao', 'ja_junto', 'nao_se_aplica'] -%}
            {{ exceptions.raise_compiler_error(
                "juntavel inválido em '" ~ f.mercado ~ " · " ~ f.premissa ~ "': '"
                ~ f.juntavel ~ "'.") }}
        {%- endif -%}
        {#- "o que impede" é metade da terceira coluna do ticket: um `nao` sem motivo entregaria
            meia resposta, e um motivo em linha que junta confundiria quem lê. -#}
        {%- if (f.juntavel == 'nao') != (f.impedimento | length > 0) -%}
            {{ exceptions.raise_compiler_error(
                "'" ~ f.mercado ~ " · " ~ f.premissa ~ "': `impedimento` tem de estar preenchido "
                ~ "quando juntavel='nao' e vazio nos demais casos.") }}
        {%- endif -%}
    {%- endfor -%}

    {{ return(fontes) }}

{% endmacro %}
