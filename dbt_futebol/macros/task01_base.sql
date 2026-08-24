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

    ⚠️ O macro emite SETE CTEs no escopo do chamador, não duas. Uma CTE do chamador com
    qualquer um destes nomes sombreia a do macro em silêncio:

      prem_linha        grão de aposta — atributos de linha vindos dos modelos de
                        premissas (hoje a penalidade específica do mercado).

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

    ⚠️ REAPONTADA em 2026-08-05 (spec #22): o universo de referência passa a ser o
    CORRIGIDO — sem as linhas de conjunto de saídas incompleto, que o de-vig deixou de
    emitir. Os números publicados da Task [0.1] incluíam 172 dessas linhas no Teste 2
    (2 vitórias em 172, ROI −35,5%), que era a única análise que não filtrava o flag
    `conjunto_incompleto`. O headline de consenso se move de −14,9% para −14,5%:
    ~0,4 ponto, e NENHUMA conclusão da [0.1] vira. As demais análises já filtravam o
    flag e devolvem número idêntico — re-rodá-las só misturaria o efeito da correção
    com a instabilidade conhecida do mercado de Gols entre builds.
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
            'pen': 'penalidades_1x2_pts',
            'nome': '1X2',
            'has_line': false,
            'cols': ['forca_mismatch', 'superioridade_xg', 'mando', 'desfalque_adversario',
                     'superioridade_tabela', 'forma', 'h2h_favoravel']
        },
        5: {
            'model': 'int_futebol_premissas_ou',
            'pen': 'penalidades_ou_pts',
            'nome': 'Gols',
            'has_line': true,
            'cols': ['ataque_combinado', 'defesas_vazaveis', 'xg_combinado_alto', 'ritmo_alto',
                     'ambos_vazam', 'historico_over', 'linha_subindo', 'defesas_firmes',
                     'clean_sheets_altos', 'xg_baixo_combinado', 'ataques_fracos',
                     'historico_under', 'linha_descendo']
        },
        4: {
            'model': 'int_futebol_premissas_ah',
            'pen': 'penalidades_ah_pts',
            'nome': 'Handicap',
            'has_line': true,
            'cols': ['supremacia', 'tende_golear', 'adversario_fragil_fora', 'mando_forte',
                     'sem_rodizio', 'raramente_perde_por_2', 'defesa_fora_solida',
                     'favorito_irregular']
        },
        8: {
            'model': 'int_futebol_premissas_btts',
            'pen': 'penalidades_btts_pts',
            'nome': 'BTTS',
            'has_line': false,
            'cols': ['ambos_marcam', 'ataque_dos_dois', 'defesas_vazaveis', 'historico_btts',
                     'defesa_forte', 'ataque_trava', 'historico_seco']
        },
        12: {
            'model': 'int_futebol_premissas_dc',
            'pen': 'penalidades_dc_pts',
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


{#- Liquidação por mercado: a linha ganhou ou perdeu, dado o placar.

    Existe como macro porque o Teste 1 liquida SEM odds — o universo dele é todo jogo
    encerrado, não só os que têm preço — e precisa exatamente da mesma regra que o
    Teste 2 e o Teste 3 usam. Duplicá-la deixaria os testes medindo coisas diferentes
    sem ninguém perceber.

    `linha` é o alias de quem traz market_id/outcome_side/line_value (a CTE de odds no
    Teste 2/3, a de premissas no Teste 1); `jogo` é o alias do fixture. Ambos incluem o
    ponto. -#}
{% macro task01_liquidacao(linha, jogo) %}
    CASE
        WHEN {{ linha }}market_id = 1 THEN
            CASE {{ linha }}outcome_side
                WHEN 'Home' THEN {{ jogo }}goals_home > {{ jogo }}goals_away
                WHEN 'Away' THEN {{ jogo }}goals_away > {{ jogo }}goals_home
                ELSE             {{ jogo }}goals_home = {{ jogo }}goals_away
            END
        WHEN {{ linha }}market_id = 5 THEN
            IF({{ linha }}outcome_side = 'Over',
               {{ jogo }}goals_home + {{ jogo }}goals_away > {{ linha }}line_value,
               {{ jogo }}goals_home + {{ jogo }}goals_away < {{ linha }}line_value)
        -- line_value vem na ÓTICA DO MANDANTE e é igual p/ Home e Away.
        WHEN {{ linha }}market_id = 4 THEN
            IF({{ linha }}outcome_side = 'Home',
               {{ jogo }}goals_home + {{ linha }}line_value > {{ jogo }}goals_away,
               {{ jogo }}goals_away - {{ linha }}line_value > {{ jogo }}goals_home)
        WHEN {{ linha }}market_id = 8 THEN
            IF({{ linha }}outcome_side = 'Yes',
               {{ jogo }}goals_home > 0 AND {{ jogo }}goals_away > 0,
               NOT ({{ jogo }}goals_home > 0 AND {{ jogo }}goals_away > 0))
        -- O modelo de premissas da DC só emite '1X' e 'X2'; o ELSE é sempre 'X2'. As
        -- linhas de '12' existem nas odds, não têm premissa e caem no JOIN — uma saída
        -- inteira fora da medição. Reportado, não corrigido.
        WHEN {{ linha }}market_id = 12 THEN
            IF({{ linha }}outcome_side = '1X',
               {{ jogo }}goals_home >= {{ jogo }}goals_away,
               {{ jogo }}goals_away >= {{ jogo }}goals_home)
    END
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
    {# ⚠️ O `{#` ABRE SEM TRAÇO DE PROPÓSITO. Com `{#-`, o Jinja come a quebra de linha
        acima e o SQL compilado sai `... AS conjunto_incompletoFROM (`, que não é SQL. Foi o
        que aconteceu entre a #37 e a #55: as análises que chamam este macro pararam de
        compilar e ninguém viu, porque nenhuma delas roda no agendado.

        ⚠️ REDUZIDO À JANELA CORRENTE (#37). O de-vig passou a emitir uma avaliação por
        janela coletada; ler sem reduzir faria cada aposta entrar no backtest até 4 vezes,
        uma por preço, todas liquidadas pelo mesmo placar. É EXATAMENTE o erro que a ADR
        0001 e a ADR 0004 existem para impedir: o ROI esperado não se move e o intervalo de
        confiança encolhe por √n sem entrar informação nenhuma — amostra falsa.

        A redução reproduz byte-a-byte a base de antes da #37, porque a janela que ela
        escolhe é a mesma que o de-vig escolhia sozinho. Quem quiser a base por janela —
        a pergunta de CLV que a #37 destrava, "o edge de abertura prevê melhor que o de
        fechamento?" — tem que optar por ela DELIBERADAMENTE, lendo o modelo direto e
        declarando o que faz com a dependência entre as janelas da mesma aposta. -#}
    FROM ({{ futebol_devig_janela_corrente() }})
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

{#- Atributos de LINHA (não de premissa) que vivem nos modelos de premissas: hoje só a
    penalidade específica do mercado. Separado de `prem_long` porque o grão é outro —
    uma linha por aposta, não uma por premissa. Insumo da composição "Score pós-A1" do
    Teste 4. -#}
prem_linha AS (
    {%- for mid, m in task01_markets().items() %}
    {%- if not loop.first %}
    UNION ALL
    {%- endif %}
    SELECT
        {{ mid }} AS market_id,
        fixture_id,
        outcome AS outcome_side,
        {% if m.has_line %}line_value{% else %}CAST(NULL AS FLOAT64){% endif %} AS line_value,
        {{ m.pen }} AS penalidades_especificas_pts
    FROM {{ ref(m.model) }}
    {%- endfor %}
),

{#- Piso de amostra do jogo: o MENOR played_total_disponivel entre os dois times, porque as
    premissas comparam os dois. Sem linha no PIT = sem histórico = 0 (mesma leitura da
    degradação graciosa do modelo).

    ⚠️ #91: lê `played_total_disponivel`, e NÃO `played_total`. Sob `pit_recorte = ultimos_10`
    — que virou o default nesta mesma entrega — `played_total` é a contagem USADA e satura em
    10, enquanto o disponível é quantas partidas anteriores EXISTEM no escopo. A regra da [F]
    (ADR 0007) é que o piso corte o DISPONÍVEL: o piso pergunta "esse time tem passado
    suficiente p/ a premissa significar algo", e essa pergunta é sobre o que existe, não sobre
    o que o teto deixou passar.

    No piso 5 a troca é inócua pela identidade `LEAST(d,10) >= 5 ⟺ d >= 5` — só deixa de ser
    a partir do piso 10, onde `played_total` saturado empataria todo mundo em 10 e o piso
    pararia de filtrar qualquer coisa. Trocar agora é o que impede esse defeito de nascer
    calado quando alguém subir o piso. -#}
pit AS (
    SELECT
        j.fixture_id,
        LEAST(COALESCE(h.played_total_disponivel, 0),
              COALESCE(a.played_total_disponivel, 0)) AS min_jogos
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
        {{ task01_liquidacao('o.', 'j.') }} AS ganhou
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
    LEFT JOIN {{ ref('int_futebol_corroboracao') }} AS c
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
      AND o.market_id IN ({{ task01_markets().keys() | join(', ') }})
      AND {{ task01_meia_linha('o.') }}
)

{% endmacro %}
