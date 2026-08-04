{#
    Base compartilhada das análises da Task [0.1] (issue #3).

    Existe para que a reconciliação por resposta conhecida signifique alguma coisa: se
    ela rodasse uma máquina diferente da que produz os resultados finais, não provaria
    nada. Toda análise da task consome ESTA definição de universo, liquidação e filtro
    de meia-linha — nenhuma redefine a sua.

    Uso:

        WITH {{ task01_base(cutoff='2026-08-02') }},
        minha_cte AS ( ... )
        SELECT ... FROM bets

    Expõe duas CTEs finais:

      bets      grão (market_id, fixture_id, outcome_side, line_value) — uma aposta.
                Traz melhor odd, edge, prob justa, benchmark de preço, liquidação
                (`ganhou`), contagem de premissas acesas e o piso de amostra do jogo.

      prem_long grão (… , premissa) — uma linha por premissa por aposta, com `acesa`.
                É o insumo do Teste 2 e da nota ponderada.

    Fidelidade: o universo, a liquidação por mercado e o filtro de meia-linha são os
    mesmos que produziram os números publicados no re-run da Task [0]. Mudar qualquer
    um deles quebra a reconciliação de propósito.
#}


{#- Catálogo das 39 premissas por mercado.

    NÃO derivar de "todas as colunas BOOL do modelo": os modelos carregam flags que não
    são premissa (`pick_empate`, `desfalque_proprio`, `is_favorito`, `is_azarao`,
    `handicap_alto`, `linha_extrema`) e a contagem infla. Esta lista é a que produziu os
    números publicados. -#}
{% macro task01_markets() %}
    {{ return({
        1: {
            'model': 'int_futebol_premissas_1x2',
            'has_line': false,
            'cols': ['forca_mismatch', 'superioridade_xg', 'mando', 'desfalque_adversario',
                     'superioridade_tabela', 'forma', 'h2h_favoravel']
        },
        5: {
            'model': 'int_futebol_premissas_ou',
            'has_line': true,
            'cols': ['ataque_combinado', 'defesas_vazaveis', 'xg_combinado_alto', 'ritmo_alto',
                     'ambos_vazam', 'historico_over', 'linha_subindo', 'defesas_firmes',
                     'clean_sheets_altos', 'xg_baixo_combinado', 'ataques_fracos',
                     'historico_under', 'linha_descendo']
        },
        4: {
            'model': 'int_futebol_premissas_ah',
            'has_line': true,
            'cols': ['supremacia', 'tende_golear', 'adversario_fragil_fora', 'mando_forte',
                     'sem_rodizio', 'raramente_perde_por_2', 'defesa_fora_solida',
                     'favorito_irregular']
        },
        8: {
            'model': 'int_futebol_premissas_btts',
            'has_line': false,
            'cols': ['ambos_marcam', 'ataque_dos_dois', 'defesas_vazaveis', 'historico_btts',
                     'defesa_forte', 'ataque_trava', 'historico_seco']
        },
        12: {
            'model': 'int_futebol_premissas_dc',
            'has_line': false,
            'cols': ['lado_coberto_forte', 'equilibrio_defensivo', 'adversario_limitado',
                     'invicto_recente']
        }
    }) }}
{% endmacro %}


{% macro task01_base(cutoff=none) %}

{#- Jogos encerrados. `cutoff` congela a janela p/ reconciliar contra número publicado;
    sem ele, o universo é tudo que já foi liquidado até hoje. -#}
fx AS (
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

{#- Benchmark de preço: a Pinnacle não precifica todos os mercados. Dupla Chance(12) é
    DERIVADA do de-vig 1X2 da Pinnacle (âncora sharp); BTTS(8) cai no consenso (mediana
    das casas), que remove a margem mas mira casa mole. Rotular é obrigatório — ganho
    contra consenso não é comparável em grau com ganho contra linha sharp. -#}
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
    WHERE best_odd IS NOT NULL
      AND edge     IS NOT NULL
),

{#- Premissas em formato longo: uma linha por (aposta, premissa).

    ATENÇÃO: `prem_long` NÃO é filtrado pelo `cutoff` nem pelo universo de jogos
    encerrados — ele é o modelo inteiro. O recorte chega pelo JOIN com `bets`. Quem
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
        f.fixture_id,
        LEAST(COALESCE(h.played_total, 0), COALESCE(a.played_total, 0)) AS min_jogos
    FROM fx AS f
    LEFT JOIN {{ ref('int_futebol_team_form_pit') }} AS h
           ON h.fixture_id = f.fixture_id
          AND h.team_id    = f.home_team_id
    LEFT JOIN {{ ref('int_futebol_team_form_pit') }} AS a
           ON a.fixture_id = f.fixture_id
          AND a.team_id    = f.away_team_id
),

bets AS (
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
        f.competition,
        f.season,
        f.kickoff_utc,
        COALESCE(pit.min_jogos, 0) AS min_jogos,
        pn.n_prem,
        pn.n_prem_null,
        CASE
            WHEN o.market_id = 1 THEN
                CASE o.outcome_side
                    WHEN 'Home' THEN f.goals_home > f.goals_away
                    WHEN 'Away' THEN f.goals_away > f.goals_home
                    ELSE             f.goals_home = f.goals_away
                END
            WHEN o.market_id = 5 THEN
                IF(o.outcome_side = 'Over',
                   f.goals_home + f.goals_away > o.line_value,
                   f.goals_home + f.goals_away < o.line_value)
            -- line_value vem na ÓTICA DO MANDANTE e é igual p/ Home e Away.
            WHEN o.market_id = 4 THEN
                IF(o.outcome_side = 'Home',
                   f.goals_home + o.line_value > f.goals_away,
                   f.goals_away - o.line_value > f.goals_home)
            WHEN o.market_id = 8 THEN
                IF(o.outcome_side = 'Yes',
                   f.goals_home > 0 AND f.goals_away > 0,
                   NOT (f.goals_home > 0 AND f.goals_away > 0))
            -- O modelo de premissas da DC só emite '1X' e 'X2'; o ELSE é sempre 'X2'.
            -- As linhas de '12' existem nas odds, não têm premissa e caem no JOIN
            -- abaixo — uma saída inteira fora da medição. Reportado, não corrigido.
            WHEN o.market_id = 12 THEN
                IF(o.outcome_side = '1X',
                   f.goals_home >= f.goals_away,
                   f.goals_away >= f.goals_home)
        END AS ganhou
    FROM odds AS o
    JOIN fx AS f
      ON f.fixture_id = o.fixture_id
    JOIN prem_n AS pn
      ON  pn.market_id                      = o.market_id
      AND pn.fixture_id                     = o.fixture_id
      AND pn.outcome_side                   = o.outcome_side
      AND COALESCE(pn.line_value, -999)     = COALESCE(o.line_value, -999)
    LEFT JOIN pit
      ON pit.fixture_id = o.fixture_id
    -- Só meia-linha em AH e O/U: elimina push, que não tem liquidação binária.
    -- MOD() do BQ devolve negativo p/ linha AH negativa -> ABS() antes.
    WHERE (o.market_id NOT IN (4, 5)
           OR MOD(CAST(ABS(o.line_value) * 2 AS INT64), 2) = 1)
)

{% endmacro %}
