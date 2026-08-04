{#
    Base compartilhada das análises da Task [0.1] (issue #3).

    Existe para que a reconciliação por resposta conhecida signifique alguma coisa: se
    ela rodasse uma máquina diferente da que produz os resultados finais, não provaria
    nada. Toda análise da task consome ESTA definição de universo, liquidação e escopo
    de mercado — nenhuma redefine a sua.

    Uso:

        WITH {{ task01_base(cutoff='2026-08-02') }},
        minha_cte AS ( ... )
        SELECT ... FROM apostas

    ⚠️ O macro emite SEIS CTEs no escopo do chamador, não duas. Uma CTE do chamador com
    qualquer um destes nomes sombreia a do macro em silêncio:

      jogos_encerrados  grão (fixture_id) — jogos liquidados dentro do `cutoff`.
      odds              grão (fixture, mercado, lado, linha) — TODOS os mercados
                        coletados, sem recorte de escopo e sem recorte de janela.
      prem_long         grão (… , premissa) — uma linha por premissa por linha de
                        aposta, com `acesa`. Insumo do Teste 2 e da nota ponderada.
      prem_n            grão de aposta — contagem de premissas acesas.
      pit               grão (fixture_id) — piso de amostra do jogo.
      apostas           grão de aposta, JÁ recortado (escopo, janela, meia-linha).
                        Traz melhor odd, edge, prob justa, benchmark, liquidação
                        (`ganhou`), contagem de premissas e piso de amostra.

    As duas que interessam ao consumidor comum são `apostas` e `prem_long`. As outras
    quatro ficam expostas de propósito: a guarda de descarte silencioso precisa enxergar
    `odds` ANTES de qualquer recorte, senão não consegue ver o que o recorte come.

    Fidelidade: o universo, a liquidação por mercado e o filtro de meia-linha são os
    mesmos que produziram os números publicados no re-run da Task [0]. Mudar qualquer
    um deles quebra a reconciliação de propósito.
#}


{#- Catálogo das 39 premissas por mercado. É também a FONTE ÚNICA do escopo de mercado
    do Motor — o filtro `market_id IN (...)` abaixo é derivado daqui, não digitado de
    novo.

    NÃO derivar de "todas as colunas BOOL do modelo": os modelos carregam flags que não
    são premissa (`pick_empate`, `desfalque_proprio`, `is_favorito`, `is_azarao`,
    `handicap_alto`, `linha_extrema`) e a contagem infla. Esta lista é a que produziu os
    números publicados. -#}
{% macro task01_markets() %}
    {{ return({
        1: {
            'model': 'int_futebol_premissas_1x2',
            'nome': '1X2',
            'has_line': false,
            'cols': ['forca_mismatch', 'superioridade_xg', 'mando', 'desfalque_adversario',
                     'superioridade_tabela', 'forma', 'h2h_favoravel']
        },
        5: {
            'model': 'int_futebol_premissas_ou',
            'nome': 'Gols',
            'has_line': true,
            'cols': ['ataque_combinado', 'defesas_vazaveis', 'xg_combinado_alto', 'ritmo_alto',
                     'ambos_vazam', 'historico_over', 'linha_subindo', 'defesas_firmes',
                     'clean_sheets_altos', 'xg_baixo_combinado', 'ataques_fracos',
                     'historico_under', 'linha_descendo']
        },
        4: {
            'model': 'int_futebol_premissas_ah',
            'nome': 'Handicap',
            'has_line': true,
            'cols': ['supremacia', 'tende_golear', 'adversario_fragil_fora', 'mando_forte',
                     'sem_rodizio', 'raramente_perde_por_2', 'defesa_fora_solida',
                     'favorito_irregular']
        },
        8: {
            'model': 'int_futebol_premissas_btts',
            'nome': 'BTTS',
            'has_line': false,
            'cols': ['ambos_marcam', 'ataque_dos_dois', 'defesas_vazaveis', 'historico_btts',
                     'defesa_forte', 'ataque_trava', 'historico_seco']
        },
        12: {
            'model': 'int_futebol_premissas_dc',
            'nome': 'Dupla Chance',
            'has_line': false,
            'cols': ['lado_coberto_forte', 'equilibrio_defensivo', 'adversario_limitado',
                     'invicto_recente']
        }
    }) }}
{% endmacro %}


{#- Só meia-linha em Handicap e Over/Under: elimina push, que não tem liquidação
    binária. MOD() do BQ devolve negativo p/ linha AH negativa -> ABS() antes.

    Existe como macro porque a guarda de descarte precisa do MESMO predicado fora da
    CTE `apostas`. Duplicá-lo deixaria a guarda derivar em silêncio da coisa que ela
    guarda. `alias` inclui o ponto: task01_meia_linha('o.') -#}
{% macro task01_meia_linha(alias='') %}
    ({{ alias }}market_id NOT IN (4, 5)
     OR MOD(CAST(ABS({{ alias }}line_value) * 2 AS INT64), 2) = 1)
{% endmacro %}


{% macro task01_base(cutoff=none) %}

{#- Jogos encerrados. `cutoff` congela a janela p/ reconciliar contra número publicado;
    sem ele, o universo é tudo que já foi liquidado até hoje (o caso dos tickets #5+). -#}
jogos_encerrados AS (
    SELECT
        fixture_id,
        competition,
        season,
        home_team_id,
        away_team_id,
        kickoff_utc,
        goals_home,
        goals_away
    FROM {{ ref('fact_fixtures') }}
    WHERE status_short = 'FT'
      AND goals_home IS NOT NULL
      {%- if cutoff is not none %}
      AND DATE(kickoff_utc) <= DATE('{{ cutoff }}')
      {%- endif %}
),

{#- TODOS os mercados coletados, SEM recorte de escopo e SEM recorte de janela. O
    recorte acontece em `apostas`; aqui não, porque a guarda de descarte silencioso
    precisa de uma referência anterior a ele p/ medir o que ele come.

    Benchmark de preço: a Pinnacle não precifica todos os mercados. Dupla Chance(12) é
    DERIVADA do de-vig 1X2 da Pinnacle (âncora sharp, e é por isso que ela chega aqui
    carimbada como valor_fonte='pinnacle'); BTTS(8) cai no consenso (mediana das casas),
    que remove a margem mas mira casa mole. Rotular é obrigatório — ganho contra
    consenso não é comparável em grau com ganho contra linha sharp. -#}
odds AS (
    SELECT
        fixture_id,
        market_id,
        outcome_side,
        line_value,
        best_odd,
        edge,
        n_casas,
        prob_justa_fechamento,
        valor_fonte,
        CASE
            WHEN market_id = 12           THEN 'derivada'
            WHEN valor_fonte = 'pinnacle' THEN 'sharp'
            ELSE valor_fonte
        END AS benchmark
    FROM {{ ref('int_futebol_odds_devig') }}
),

{#- Premissas em formato longo: uma linha por (aposta, premissa).

    ATENÇÃO: `prem_long` NÃO é filtrado pelo `cutoff` nem pelo universo de jogos
    encerrados — ele é o modelo inteiro. O recorte chega pelo JOIN com `apostas`. Quem
    consumir `prem_long` sozinho (o Teste 1, que não usa odd) precisa aplicar o seu
    próprio universo, senão mede em cima de jogos que ainda não aconteceram. -#}
prem_long AS (
    {%- for mid, m in task01_markets().items() %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        {{ mid }} AS market_id,
        p.fixture_id,
        p.outcome AS outcome_side,
        {% if m.has_line %}p.line_value{% else %}CAST(NULL AS FLOAT64){% endif %} AS line_value,
        u.premissa,
        u.acesa
    FROM {{ ref(m.model) }} AS p
    CROSS JOIN UNNEST([
        {%- for c in m.cols %}
        STRUCT('{{ c }}' AS premissa, p.{{ c }} AS acesa){{ "," if not loop.last }}
        {%- endfor %}
    ]) AS u
    {%- endfor %}
),

{#- `n_prem_null` existe p/ diagnóstico: a degradação graciosa promete que premissa
    nunca é NULL (dado faltante = não acende). Se a promessa falhar, contar por soma
    (como a query original) e contar por COUNTIF divergem, e o número publicado não é
    reproduzível. A reconciliação checa isso explicitamente. -#}
prem_n AS (
    SELECT
        market_id,
        fixture_id,
        outcome_side,
        line_value,
        COUNTIF(acesa)         AS n_prem,
        COUNTIF(acesa IS NULL) AS n_prem_null
    FROM prem_long
    GROUP BY 1, 2, 3, 4
),

{#- Piso de amostra do jogo: o MENOR played_total entre os dois times, porque as
    premissas comparam os dois. Sem linha no PIT = sem histórico = 0 (mesma leitura da
    degradação graciosa do modelo). -#}
pit AS (
    SELECT
        j.fixture_id,
        LEAST(COALESCE(h.played_total, 0), COALESCE(a.played_total, 0)) AS min_jogos
    FROM jogos_encerrados AS j
    LEFT JOIN {{ ref('int_futebol_team_form_pit') }} AS h
           ON h.fixture_id = j.fixture_id
          AND h.team_id    = j.home_team_id
    LEFT JOIN {{ ref('int_futebol_team_form_pit') }} AS a
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
        j.competition,
        j.season,
        j.kickoff_utc,
        COALESCE(pit.min_jogos, 0) AS min_jogos,
        pn.n_prem,
        pn.n_prem_null,
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
            -- O modelo de premissas da DC só emite '1X' e 'X2'; o ELSE é sempre 'X2'.
            -- As linhas de '12' existem nas odds, não têm premissa e caem no JOIN
            -- abaixo — uma saída inteira fora da medição. Reportado, não corrigido.
            WHEN o.market_id = 12 THEN
                IF(o.outcome_side = '1X',
                   j.goals_home >= j.goals_away,
                   j.goals_away >= j.goals_home)
        END AS ganhou
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
    WHERE o.best_odd IS NOT NULL
      AND o.edge     IS NOT NULL
      -- Escopo do Motor, DECLARADO e derivado do catálogo de premissas acima — não
      -- digitado de novo. A coleta traz mercados que o Motor não pontua: 6 (Goals
      -- Over/Under First Half), 7 (HT/FT Double), 10 (Exact Score). Sem esta linha eles
      -- cairiam pelo INNER JOIN com prem_n, o que é correto por acidente: só do 6 são
      -- ~3,6 mil linhas sumindo em silêncio na janela congelada.
      AND o.market_id IN ({{ task01_markets().keys() | join(', ') }})
      AND {{ task01_meia_linha('o.') }}
)

{% endmacro %}
