{#- Catálogo do Total de escanteios (`prop-play-predictor` docs/futebol-metodologia-escanteios-total.md,
    seção 3, commit b89fadb — cruzado com scripts/futebol-escanteios-total.mjs FAMILIAS/BOOLEANAS,
    que é o código que de fato gerou os números do documento).

    18 premissas, cada uma com um corte "acende no Mais" (>=) e um "acende no Menos" (<=) —
    ou, pra mata_mata/reta_final, um flag booleano que acende IGUAL nos dois lados (o
    documento marca "verdadeiro"/"verdadeiro" nas duas colunas: não é um sinal direcional
    de contagem de escanteio, é "jogo de contexto especial", e o próprio script testa a
    MESMA condição pros dois lados — ver BOOLEANAS em futebol-escanteios-total.mjs).

    ⚠️ DIVERGÊNCIA DECLARADA COM A PROSE DO DOCUMENTO (e com a issue #183, que repete a
    prosa): a seção "Quais entram em cada lado" do documento diz "só três [premissas]
    servem nos dois: volume_de_finalizacao, jogo_faltoso e finalizacao_na_area" — mas as
    DUAS listas enumeradas logo abaixo (Lado Mais — 9 / Lado Menos — 9) têm
    `finalizacao_de_fora` E `campeonato_de_escanteio` nas DUAS, não só as três citadas.
    Contagem correta pela enumeração: 5 compartilhadas, não 3. Não escolhi decidir qual das
    duas fontes (prosa vs. lista) está certa — decidi não escolher: esta medição roda o
    CATÁLOGO COMPLETO, as 18 premissas × os dois lados (36 combinações), exatamente como
    a AC do #183 pede ("catálogo COMPLETO"). Isso testa TODA premissa em AMBOS os lados,
    inclusive as que o documento já descartou de um lado (ex.: `bloqueios` no Mais,
    `ataque_de_escanteio` no Menos) — sob os gates do board e min_jogos>=10, o descarte
    pode não se replicar (mesmo achado que #161 já teve pro Handicap: "ganho individual de
    premissa não se replica"). A pergunta "3 ou 5 compartilhadas" fica sem resposta
    necessária porque a resposta certa é "meça as duas, todas as vezes".

    piso min_jogos>=10 aplicado SEMPRE, dentro de `acesa` — mesmo padrão AE#172 (a cópia
    que esqueceu o piso no Handicap). Aqui não existe cópia: um macro só. -#}
{% macro ae183_premissas_escanteios_total() %}
    {{ return([
        {'premissa': 'ataque_de_escanteio',    'campo': '(h_ck + a_ck)',              'mais': 10.40, 'menos': 9.00},
        {'premissa': 'defesa_que_cede',        'campo': '(h_sof + a_sof)',            'mais': 10.30, 'menos': 8.90},
        {'premissa': 'volume_de_finalizacao',  'campo': '(h_ts + a_ts)',              'mais': 27.00, 'menos': 23.90},
        {'premissa': 'finalizacao_de_fora',    'campo': '(h_ob + a_ob)',              'mais': 10.40, 'menos': 8.60},
        {'premissa': 'finalizacao_na_area',    'campo': '(h_ib + a_ib)',              'mais': 16.90, 'menos': 14.50},
        {'premissa': 'bloqueios',              'campo': '(h_bl + a_bl)',              'mais': 7.30,  'menos': 6.20},
        {'premissa': 'defesas_do_goleiro',     'campo': '(h_gs + a_gs)',              'mais': 6.30,  'menos': 5.46},
        {'premissa': 'jogo_faltoso',           'campo': '(h_fl + a_fl)',              'mais': 26.40, 'menos': 23.40},
        {'premissa': 'chute_de_longe',         'campo': '(SAFE_DIVIDE(h_ob, h_ts) + SAFE_DIVIDE(a_ob, a_ts))', 'mais': 0.81, 'menos': 0.69},
        {'premissa': 'desequilibrio_de_posse', 'campo': 'ABS(h_po - a_po)',           'mais': 8.30,  'menos': 3.70},
        {'premissa': 'pressao_do_mandante',    'campo': 'h_ck_lado',                  'mais': 6.00,  'menos': 4.80},
        {'premissa': 'visitante_que_cede',     'campo': 'a_sof_lado',                 'mais': 6.00,  'menos': 4.60},
        {'premissa': 'campeonato_de_escanteio','campo': 'campeonato_de_escanteio',    'mais': 10.06, 'menos': 9.51},
        {'premissa': 'escanteio_previsto',     'campo': 'escanteio_previsto',         'mais': 10.05, 'menos': 9.30},
        {'premissa': 'previsao_x_linha',       'campo': '(escanteio_previsto - line_value)', 'mais': 0.50, 'menos': -0.50},
        {'premissa': 'chance_de_gol',          'campo': '(h_xg + a_xg)',              'mais': 2.87,  'menos': 2.38},
        {'premissa': 'mata_mata',              'campo': 'mata_mata',                  'mais': none,  'menos': none},
        {'premissa': 'reta_final',             'campo': 'reta_final',                 'mais': none,  'menos': none}
    ]) }}
{% endmacro %}

{#- Materializa o catálogo como SELECT ... UNION ALL, no grão (fixture_id, outcome_side,
    line_value, benchmark, prob_justa_fechamento, ganhou, premissa, lado, acesa) — pronto
    pra agregar direto, sem join de volta em `apostas`. `tabela` é sempre a CTE local
    `apostas` (nunca ref() — ae183_base_escanteios_total() não materializa nada).

    Cada premissa é testada contra a APOSTA REAL do lado que seu corte declara — Mais
    contra a linha Over daquele jogo (o corte >= é sobre a aposta que Mais realmente é),
    Menos contra a linha Under. Não é um cross join Mais×{Over,Under}: `WHERE
    outcome_side='Over'/'Under'` no FROM já resolve isso, e resolve de graça o caso
    `previsao_x_linha` (cujo campo usa `line_value` — a linha do Over pode não ser a
    mesma linha do Under no mesmo jogo, já que a seleção de linha principal roda
    independente por lado; usar a própria linha da aposta que está sendo testada, em vez
    de reconciliar duas linhas depois, é a razão de filtrar aqui e não juntar depois). -#}
{% macro ae183_premissas_escanteios_total_sql(tabela) %}
    {%- set catalogo = ae183_premissas_escanteios_total() -%}
    {%- set combos = [] -%}
    {%- for p in catalogo -%}
        {%- set _ = combos.append((p, 'Mais', 'Over')) -%}
        {%- set _ = combos.append((p, 'Menos', 'Under')) -%}
    {%- endfor -%}
    {%- for p, lado_medido, side in combos %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        fixture_id, outcome_side, line_value, benchmark, prob_justa_fechamento, ganhou,
        '{{ p.premissa }}'  AS premissa,
        '{{ lado_medido }}' AS lado,
        {%- if p.mais is none %}
        -- booleana (mata_mata/reta_final): mesmo flag acende nos dois lados do catálogo
        (COALESCE({{ p.campo }}, FALSE) AND min_jogos >= 10) AS acesa
        {%- elif lado_medido == 'Mais' %}
        (COALESCE({{ p.campo }} >= {{ p.mais }}, FALSE) AND min_jogos >= 10) AS acesa
        {%- else %}
        (COALESCE({{ p.campo }} <= {{ p.menos }}, FALSE) AND min_jogos >= 10) AS acesa
        {%- endif %}
    FROM {{ tabela }}
    WHERE outcome_side = '{{ side }}'
    {%- endfor %}
{% endmacro %}
