{{ config(tags=['taskf', 'costura_b']) }}
-- COSTURA B da task [F] (issue #49, ticket #55), invariante 2 de 3 — AS PREMISSAS DE TABELA NÃO
-- SE MEXEM ENTRE AS CÉLULAS.
--
-- A ADR 0008 decidiu que as premissas que leem CLASSIFICAÇÃO (`rank`, `ppg`, `n_teams`) ficam
-- competição-scoped nas quatro células, porque não existe tabela de um campeonato juntado —
-- `sem_rodizio` chega a comparar o rank contra o tamanho da liga. E afirma que, por isso, o
-- número delas é "idêntico por construção". Esta guarda é o que transforma essa afirmação em
-- verificação: enquanto ela passar, a imobilidade dessas linhas é fato conferido, e não a
-- promessa de que ninguém deixou o escopo vazar para dentro delas.
--
-- Falha = ou o eixo de escopo alcançou uma premissa que a ADR diz que ele não alcança, ou a
-- célula foi gravada com o rótulo de outra. As duas são graves e nenhuma se vê no número.
--
-- ────────────────────────────────────────────────────────────────────────────────
-- SÃO TRÊS PREMISSAS, E A IDENTIDADE É NO PISO 0. As duas coisas divergem do enunciado literal
-- do critério de aceite da #55, que fala em quatro premissas sem qualificar o piso — e as duas
-- estão registradas na ADR 0008 (seção final e Consequences), medidas antes desta guarda existir:
--
--   TRÊS, NÃO QUATRO. `x_superioridade_tabela` não é uma das 39 premissas medidas: é coluna
--   interna do int_futebol_premissas_1x2 que a Dupla Chance reusa dentro do `lado_coberto_forte`
--   — e este também lê `forca_mismatch`, que segue o eixo. Cobrá-la aqui daria zero linha
--   comparada, que é o modo de falha silencioso que a lista explícita abaixo fecha.
--
--   PISO 0, NÃO TODOS. `min_jogos` segue a célula inclusive nas linhas destas premissas (o piso é
--   propriedade do JOGO, não da premissa — Consequences da ADR 0008). Nos pisos maiores elas
--   mudam de número legitimamente, porque cada célula corta um conjunto diferente de jogos:
--   `superioridade_tabela` vai de n=35 na `base` para n=47 na `escopo` no piso 5. Cobrar
--   igualdade lá seria cobrar que a decisão da ADR não valesse.
--
-- Pelo mesmo motivo, `jogos_medios_disp`, `jogos_medios_usado` e `pct_amostra_curta` ficam FORA
-- da comparação mesmo no piso 0: são médias do histórico do jogo, não da premissa, e elas se
-- mexem de propósito (`supremacia` mede 7,0 partidas na `base` e 29,1 na `ambos`). O que é
-- cobrado são os campos que descrevem a MEDIÇÃO da premissa — quantas vezes acendeu, o que a odd
-- dava, o que aconteceu, a diferença e os dois pesos.
--
-- ────────────────────────────────────────────────────────────────────────────────
-- O GRÃO É (mercado, premissa, benchmark), nunca a premissa sozinha: `supremacia` e `sem_rodizio`
-- saem em duas linhas cada (sharp e consenso do Handicap), com números diferentes, e comparar
-- premissa a premissa juntaria as duas.
--
-- NÃO-VACUIDADE em duas frentes, porque "todos os números batem" é o veredito natural de uma
-- comparação que não comparou nada:
--
--   premissa_ausente     cada uma das três aparece em pelo menos uma célula. Uma renomeada no
--                        catálogo sumiria daqui sem deixar rastro.
--   grao_incompleto      cada linha de grão existe nas QUATRO células. Uma premissa medida em
--                        duas células e comparada só ali passaria dizendo o mesmo que uma medida
--                        nas quatro.
--
-- QUEM RODA: a FASE 3 da receita do analyses/taskf_teste2.sql, depois das quatro células —
-- `dbt test --target taskF --select tag:costura_b`. Não é o agendado (tag `guarda`).
--
-- Falsificada de propósito alterando o `n_p0` de uma célula (e desfazendo em seguida); os
-- comandos e o resultado estão em `docs/TASKF_RESULTADOS.md`, seção do ticket #55.

{#- As três do catálogo medido. Escritas aqui e não derivadas de nada: é a lista que a ADR 0008
    nomeia, e uma guarda que descobrisse sozinha "quais premissas são de tabela" acabaria
    concordando com o que quer que o código estivesse fazendo. -#}
{% set premissas_de_tabela = ['superioridade_tabela', 'supremacia', 'sem_rodizio'] %}

{#- Os campos do piso 0 que descrevem a medição da premissa. `fator_encolhimento` entra porque é
    função de `n_p0` e denunciaria um n que mudou sem a linha inteira mudar junto. -#}
{%- set campos = [
    'n_p0', 'a_odd_dava_p0', 'aconteceu_p0', 'diferenca_p0', 'peso_p0', 'peso_p0_k0',
    'fator_encolhimento'
] %}
-- As duas listas acima são o contrato desta guarda: as premissas que a ADR 0008 nomeia e os
-- campos que descrevem a medição delas. O cabeçalho diz o que ficou de fora, e por quê.

WITH medido AS (
    SELECT
        celula, mercado, premissa, benchmark, usado_para_peso,
        {{ campos | join(', ') }}
    FROM {{ source('futebol_taskF', 'taskf_teste2') }}
    WHERE premissa IN ({{ premissas_de_tabela | map('tojson') | join(', ') }})
),

-- A referência é a célula base do 2×2 quando ela existe (é a que não muda nada); na falta dela, a
-- primeira em ordem alfabética, para a guarda não passar em branco por causa da ausência.
referencia AS (
    SELECT * FROM medido
    -- `WHERE TRUE` não é enfeite: o BigQuery só aceita QUALIFY quando há WHERE, GROUP BY ou
    -- HAVING na mesma query — sem ele, o parser lê `QUALIFY` como alias da tabela e o erro sai
    -- várias linhas adiante.
    WHERE TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY mercado, premissa, benchmark
        ORDER BY IF(celula = 'base', 0, 1), celula
    ) = 1
),

divergencias AS (
    SELECT
        'numero_divergente' AS motivo,
        TO_JSON_STRING(STRUCT(
            m.mercado, m.premissa, m.benchmark, m.usado_para_peso,
            m.celula, r.celula AS referencia,
            {%- for campo in campos %}
            m.{{ campo }}, r.{{ campo }} AS {{ campo }}_ref{{ ',' if not loop.last }}
            {%- endfor %}
        )) AS linha
    FROM medido AS m
    JOIN referencia AS r
      ON  r.mercado   = m.mercado
      AND r.premissa  = m.premissa
      AND r.benchmark = m.benchmark
    WHERE {% for campo in campos -%}
          m.{{ campo }} IS DISTINCT FROM r.{{ campo }}
          {%- if not loop.last %}
       OR {% endif %}
          {%- endfor %}
),

-- NÃO-VACUIDADE 1: as três estão na tabela.
ausentes AS (
    SELECT
        'premissa_ausente' AS motivo,
        TO_JSON_STRING(STRUCT(
            p AS premissa,
            (SELECT COUNT(*) FROM medido WHERE premissa = p) AS linhas_encontradas
        )) AS linha
    FROM UNNEST({{ premissas_de_tabela | tojson }}) AS p
    WHERE NOT EXISTS (SELECT 1 FROM medido WHERE premissa = p)
),

-- NÃO-VACUIDADE 2: cada linha de grão existe nas quatro células. Compara-se contra a contagem de
-- células que a tabela de fato tem (que a invariante 1 cobra ser 4), e não contra um 4 digitado:
-- as duas guardas ficam com um dono cada, e esta não repete a cobrança da outra com número solto.
celulas_na_tabela AS (
    SELECT COUNT(DISTINCT celula) AS n FROM {{ source('futebol_taskF', 'taskf_teste2') }}
),

grao_incompleto AS (
    SELECT
        'grao_incompleto' AS motivo,
        TO_JSON_STRING(STRUCT(
            g.mercado, g.premissa, g.benchmark,
            g.celulas_com_a_linha, t.n AS celulas_na_tabela,
            g.quais_celulas
        )) AS linha
    FROM (
        SELECT
            mercado, premissa, benchmark,
            COUNT(DISTINCT celula) AS celulas_com_a_linha,
            STRING_AGG(DISTINCT celula, ', ' ORDER BY celula) AS quais_celulas
        FROM medido
        GROUP BY mercado, premissa, benchmark
    ) AS g
    CROSS JOIN celulas_na_tabela AS t
    WHERE g.celulas_com_a_linha <> t.n
)

SELECT motivo, linha FROM divergencias
UNION ALL
SELECT motivo, linha FROM ausentes
UNION ALL
SELECT motivo, linha FROM grao_incompleto
