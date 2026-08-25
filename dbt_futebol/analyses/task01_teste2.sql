{#
    Task [0.1] — TESTE 2 completo nos 5 mercados, base limpa, e derivação do peso
    medido.  Ticket #5, spec #3.

    O Teste 2 mede se a premissa BATE O PREÇO, e é o único dos quatro que pode
    justificar um peso. O Teste 1 mede outra coisa (prever a linha) — foi essa distinção
    que primeiro salvou e depois derrubou o `xg_combinado_alto`.

        diferença = média(acerto | premissa acesa) − média(prob justa | premissa acesa)

    ────────────────────────────────────────────────────────────────────────────────
    BENCHMARK: a tabela sai por (mercado, premissa, BENCHMARK), e não por (mercado,
    premissa).

    A Pinnacle não cobre todos os jogos. Handicap e Gols são MISTOS — cerca de metade
    das linhas tem preço sharp e metade cai no consenso (mediana das casas). A rodada
    anterior mediu só as sharp; juntar as duas metades numa linha só misturaria dois
    benchmarks de graus diferentes dentro do mesmo número.

    O PESO é derivado apenas do MELHOR benchmark disponível de cada mercado:

        1X2, Handicap, Gols   sharp      (de-vig direto da Pinnacle)
        Dupla Chance          derivada   (do de-vig 1X2 da Pinnacle — âncora sharp)
        BTTS                  consenso   (a Pinnacle estruturalmente não precifica)

    As linhas de consenso do Handicap e do Gols vão na saída assim mesmo, marcadas com
    `usado_para_peso = false`. Elas não pesam, mas precisam ser vistas: o ROI delas é
    muito pior que o das sharp (−26,7 contra −6,5 no Handicap), e essa diferença não é
    do benchmark — é de QUAIS jogos a Pinnacle escolhe precificar. Ignorá-las
    esconderia isso.
    ────────────────────────────────────────────────────────────────────────────────
    PESO (ADR 0001):

        peso = max(diferença, 0) × n / (n + k)          k = 50

    Encolhimento por amostra, não ganho cru. O achado central da Task [0] foi que
    amostra curta fabrica sinal: os +9,7% que morreram vinham inteiramente de
    competições de mata-mata com 0,8 a 2,4 jogos disputados. Peso proporcional ao ganho
    bruto daria as maiores notas justamente às premissas que acenderam poucas vezes.
    `peso_k0` (sem encolhimento) vai junto como sensibilidade.

    Ganho negativo vira peso ZERO, não peso negativo: com esta amostra, uma diferença de
    −5 é indistinguível de ruído, e peso negativo fitaria esse ruído.
    ────────────────────────────────────────────────────────────────────────────────
    `jogos_medios` e `pct_amostra_curta` existem para amarrar cada premissa ao artefato
    que matou a medição anterior. Premissa com ganho alto E `pct_amostra_curta` alto é
    exatamente o padrão que produziu os +9,7%.

    Universo: TODOS os jogos liquidados com odd, sem corte congelado — a janela exata
    sai nas duas primeiras colunas.

    → RESULTADOS: `docs/TASK01_RESULTADOS.md`.

    Rodar com:
      dbt compile --select task01_teste2
      bq query --use_legacy_sql=false < target/compiled/dbt_futebol/analyses/task01_teste2.sql
#}

WITH {{ task01_base() }},

{#- Uma passada, grão (mercado, premissa, benchmark). Só as linhas em que a premissa
    ACENDEU entram nas médias — é essa a definição do Teste 2.

    O PISO DE AMOSTRA entra como COLUNA, não como execução separada. Motivo: a primeira
    rodada do Teste 2 mostrou que o encolhimento por amostra e o piso tratam eixos
    DIFERENTES. `k` trata `n` pequeno (a premissa acendeu poucas vezes); o piso trata
    jogo sem histórico. `clean_sheets_altos` tem n=105 (grande, o encolhimento mal
    encosta) e 77% das linhas em jogo com menos de 5 partidas disputadas — que é a
    assinatura exata do artefato que matou os +9,7%. Sem ver os dois lado a lado não dá
    para saber se um peso alto é sinal ou é o mata-mata de novo. -#}
agregado AS (
    SELECT
        a.market_id,
        pl.premissa,
        a.benchmark,
{#- ⚠️ `jogos_medios` MUDA DE SENTIDO CONFORME A CÉLULA desde a #91 (ADR 0010). O `min_jogos`
            do task01_base() é a contagem DISPONÍVEL, então sob recorte `ultimos_10` — o default — esta
            média é sem teto e sobe; sob `temporada` é a mesma de sempre. Ele é diagnóstico de amostra,
            não resultado: nenhuma conclusão da [0.1] se apoia nele, e comparar este número entre
            células é comparar duas definições. Ver ADR 0010, seção 5. -#}
        AVG(IF(pl.acesa, a.min_jogos, NULL))                     AS jogos_medios,
        AVG(IF(pl.acesa, IF(a.min_jogos < 5, 1.0, 0.0), NULL))   AS frac_curta
        {%- for piso in [0, 5, 10] %},
        COUNTIF(pl.acesa AND a.min_jogos >= {{ piso }})          AS n_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos >= {{ piso }},
               a.prob_justa_fechamento, NULL))                   AS p_odd_{{ piso }},
        AVG(IF(pl.acesa AND a.min_jogos >= {{ piso }},
               CAST(a.ganhou AS INT64), NULL))                   AS p_real_{{ piso }}
        {%- endfor %}
    FROM apostas AS a
    JOIN prem_long AS pl
      ON  pl.market_id                  = a.market_id
      AND pl.fixture_id                 = a.fixture_id
      AND pl.outcome_side               = a.outcome_side
      AND COALESCE(pl.line_value, -999) = COALESCE(a.line_value, -999)
    GROUP BY a.market_id, pl.premissa, a.benchmark
    HAVING COUNTIF(pl.acesa) > 0
),

janela AS (
    SELECT
        MIN(DATE(kickoff_utc)) AS janela_ini,
        MAX(DATE(kickoff_utc)) AS janela_fim,
        COUNT(DISTINCT fixture_id) AS jogos_no_universo,
        COUNT(*) AS linhas_no_universo
    FROM apostas
),

{#- `preferido` calculado UMA vez, não repetido em cada coluna que depende dele. -#}
rotulado AS (
    SELECT
        g.*,
        CASE g.market_id
            {%- for mid, m in task01_markets().items() %}
            WHEN {{ mid }} THEN '{{ m.nome }}'
            {%- endfor %}
        END AS mercado,
        g.benchmark = CASE g.market_id
                          WHEN 12 THEN 'derivada'
                          WHEN 8  THEN 'consenso'
                          ELSE         'sharp'
                      END AS preferido
    FROM agregado AS g
)

SELECT
    j.janela_ini,
    j.janela_fim,
    j.jogos_no_universo,
    r.mercado,
    r.premissa,
    r.benchmark,
    r.preferido                                             AS usado_para_peso,
    -- Fator de encolhimento aplicado ao peso: n/(n+50). Exposto em vez de um flag
    -- binário de "n suficiente" porque o corte seria arbitrário e este número já diz
    -- exatamente quanto da medição sobreviveu. `desfalque_adversario` (n=7) fica em
    -- 0,12: qualquer sinal que ela tivesse seria 88% descartado por falta de amostra,
    -- e isso é diferente de "medimos e deu ruim".
    ROUND(SAFE_DIVIDE(r.n_0, r.n_0 + 50), 2)                AS fator_encolhimento,
    ROUND(r.jogos_medios, 1)                                AS jogos_medios,
    ROUND(r.frac_curta * 100, 1)                            AS pct_amostra_curta
    {%- for piso in [0, 5, 10] %},
    r.n_{{ piso }}                                          AS n_p{{ piso }},
    ROUND(r.p_odd_{{ piso }}  * 100, 1)                     AS a_odd_dava_p{{ piso }},
    ROUND(r.p_real_{{ piso }} * 100, 1)                     AS aconteceu_p{{ piso }},
    ROUND((r.p_real_{{ piso }} - r.p_odd_{{ piso }}) * 100, 1) AS diferenca_p{{ piso }},
    -- peso = max(diferença, 0) × n/(n+k), k=50. Ganho negativo vira ZERO, não peso
    -- negativo: com esta amostra, −5 é indistinguível de ruído.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_{{ piso }} - r.p_odd_{{ piso }}) * 100, 0)
             * SAFE_DIVIDE(r.n_{{ piso }}, r.n_{{ piso }} + 50), 2),
       NULL)                                                AS peso_p{{ piso }}
    {%- endfor %},
    -- Sensibilidade: peso sem encolhimento nenhum, no piso 0. Mostra o quanto o k=50
    -- está segurando.
    IF(r.preferido,
       ROUND(GREATEST((r.p_real_0 - r.p_odd_0) * 100, 0), 2),
       NULL)                                                AS peso_p0_k0
FROM rotulado AS r
CROSS JOIN janela AS j
ORDER BY r.mercado, r.preferido DESC, diferenca_p0 DESC
