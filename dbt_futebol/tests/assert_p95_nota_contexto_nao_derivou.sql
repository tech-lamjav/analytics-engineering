{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DO DENOMINADOR CONGELADO (#105, ADR 0005). Duas cobranças, uma tabela:
--
--   COBERTURA  todo (mercado, lado) que aparece no funil tem linha no seed;
--   DERIVA     o p95 VIVO de cada lado não se afastou do congelado além da tolerância.
--
-- ⚠️ POR QUE `severity='error'`, e está no aceite da issue: `dbt test` sai com 0 quando
-- tudo que falhou é `warn`. Guarda `warn` neste projeto é comentário, não guarda.
--
-- ⚠️ O PONTO CEGO QUE NÃO É NOSSO (ADR 0005): teste em dbt hoje não alarma sozinho. O que
-- lê o vermelho é a fase `tag:guarda` do workflow, e o resumo diário depende da subtask C4.
--
-- ==========================================================================
-- 1. COBERTURA — o lado que existe e não tem denominador
--
-- Sem esta metade, um lado novo (mercado novo, saída nova no catálogo) entraria no funil,
-- não casaria com nenhuma linha do seed, o `p95` chegaria NULL e a normalização o trataria
-- como denominador ausente: nota ZERO. A linha reprovaria a régua para sempre, em silêncio
-- e com aparência de linha ruim. É o mesmo defeito que a ADR 0006 nomeia, chegando pela
-- porta do join em vez da porta do `WHERE`.
--
-- O join do modelo é LEFT justamente para que a linha não SUMA; é aqui que ela acende.
-- Cobrado só sobre lado NÃO NULO: a "12" da Dupla Chance resolve o lado para NULL por
-- desenho (fail-closed do `futebol_lado()`), e a decisão de não pontuá-la já está
-- carimbada na `porta_saida_catalogada`.
--
-- ==========================================================================
-- 2. DERIVA — o número congelado que envelheceu
--
-- O p95 vivo é recalculado do MESMO jeito que a medição o mediu, e as três regras que
-- fazem os dois comparáveis moram em macro ou em var, nunca copiadas aqui:
--
--   · a MESMA função de percentil (`futebol_p95()`), porque duas expressões diferentes
--     fabricam deriva que não existe — `APPROX_QUANTILES` é aproximado por construção e
--     num lado com poucos valores possíveis ele salta de degrau sozinho;
--   · o MESMO lado (`futebol_lado()`), DERIVADO aqui e não lido da coluna `lado` do funil.
--     Não é desconfiança do modelo — os dois leem o mesmo macro. É que a coluna também
--     chegou por `append_new_columns`: a linha escrita entre o deploy da #103 e o desta
--     entrega tem `nota_contexto` preenchida e `lado` NULL, e ler a coluna a jogaria fora
--     da amostra justamente na janela mais recente que a guarda existe para vigiar;
--   · a MESMA regra de UMA JANELA POR CANDIDATO (`janela_e_corrente`). O funil guarda até
--     quatro linhas por candidato e a nota de contexto é a mesma nas quatro; contando as
--     quatro, o jogo precificado cedo pesaria até 4× e o p95 descreveria "quem foi
--     precificado por mais tempo".
--
-- ⚠️ A JANELA VIVA É ROLANTE, e é ela que faz a guarda falar de HOJE. Duas linhas a
-- definem, e as duas são necessárias:
--
--   `nota_contexto IS NOT NULL` — é o carimbo de que a linha foi escrita pelo código
--   PÓS-A1. A coluna chegou por `append_new_columns`, e sob o append-only (#96, ADR 0011)
--   toda linha de jogo apitado antes daquele deploy ficou com ela NULL para sempre. Sem
--   este filtro a guarda misturaria as DUAS escalas do Gols — a de antes da #103, com as
--   premissas de movimento de linha e o clamp em 55, e a de depois — e nasceria vermelha
--   descrevendo uma escala que não existe mais. É o mesmo escopo, e pelo mesmo motivo, que
--   a `assert_funil_nota_contexto_reconstroi` já usa.
--
--   `kickoff_utc >= hoje − p95_deriva_janela_dias` — a janela rolante propriamente dita.
--
-- ⚠️ DENOMINADOR ZERO TEM REGRA PRÓPRIA, e não é `SAFE_DIVIDE`. O empate do 1X2 e o `Pick`
-- do Handicap estão congelados em zero porque nenhuma premissa se aplica a eles. A
-- distância relativa dividiria por zero e um `SAFE_DIVIDE` devolveria NULL — a guarda
-- ficaria CEGA exatamente nos dois lados onde a mudança é mais barata de detectar. A regra
-- é binária: com zero congelado, acende se o p95 vivo for MAIOR que zero. Premissa que
-- passa a acender no empate é mudança de catálogo, e é o sinal que esta guarda existe para
-- dar.
--
-- ⚠️ O PISO DE AMOSTRA É ABSTENÇÃO, e está declarado. Abaixo de `p95_deriva_min_linhas` o
-- lado não é cobrado: um p95 de trinta linhas anda de degrau sozinho e produziria vermelho
-- sem defeito. O preço é lado de baixo volume ficar sem vigilância numa janela magra —
-- dito aqui, e não escondido num `HAVING`.
--
-- ⚠️ A JANELA PRECISA ESTAR CHEIA ATÉ O FUNDO, e esta é a terceira condição de cobrança —
-- a que a medição desta entrega descobriu, e não é teórica. No dia do deploy as ÚNICAS
-- linhas com `nota_contexto` preenchida são as de jogo ainda por vir: o append-only não
-- reescreve o passado, então a amostra viva nasce com SEIS DIAS de rodada, não com trinta.
-- Medido em 26/08, o favorito do Handicap dava p95 30 nesses seis dias contra 24 na janela
-- inteira — 25% de distância, guarda vermelha, e nada de errado com o denominador. Sobre
-- uma janela rolante de 30 dias de verdade os onze lados batem (o maior desvio é 7%, o
-- "Sim" do BTTS), que é o que diz que a tolerância de 20% não é frouxa.
--
-- `profundidade_dias >= p95_deriva_janela_dias` exige que a linha mais velha da amostra
-- esteja no fundo da janela antes de qualquer cobrança de deriva. Consequência declarada:
-- **a metade da DERIVA fica dormente por ~30 dias depois do deploy**, enquanto o funil
-- acumula linhas pós-A1. A metade da COBERTURA não espera nada e morde desde o primeiro
-- build — que é a que importa no dia 0, porque é ela que pega o lado sem denominador.

WITH congelado AS (
    SELECT
        market,
        lado,
        p95        AS p95_congelado,
        medido_em,
        janela_fim AS janela_congelada_ate
    FROM {{ ref('futebol_p95_nota_contexto') }}
),

-- as linhas vivas: uma por candidato, escritas pelo código pós-A1, dentro da janela
-- rolante. O lado sai do MESMO macro que o modelo e a medição usam.
vivo_linhas AS (
    SELECT
        f.market,
        {{ futebol_lado('f.market', 'f.outcome', 'f.line_value') }} AS lado,
        f.nota_contexto,
        f.kickoff_utc
    FROM {{ ref('fact_value_funnel') }} f
    WHERE f.janela_e_corrente
      AND f.nota_contexto IS NOT NULL
      AND f.kickoff_utc >= TIMESTAMP_SUB(
              CURRENT_TIMESTAMP(), INTERVAL {{ var('p95_deriva_janela_dias') }} DAY)
),

vivo AS (
    SELECT DISTINCT
        market,
        lado,
        {{ futebol_p95('nota_contexto') }} OVER (PARTITION BY market, lado) AS p95_vivo,
        COUNT(*)                           OVER (PARTITION BY market, lado) AS n_vivo,
        -- a idade da linha mais VELHA da amostra viva. É o que diz se a janela está cheia
        -- até o fundo — ver o ⚠️ do cabeçalho sobre janela rasa.
        DATE_DIFF(CURRENT_DATE(),
                  MIN(DATE(kickoff_utc)) OVER (PARTITION BY market, lado),
                  DAY)                     AS profundidade_dias
    FROM vivo_linhas
    -- saída não catalogada (a "12") tem lado NULL por desenho e não é cobrada.
    WHERE lado IS NOT NULL
),

-- FULL OUTER: o lado sem denominador entra pela direita vazia (cobertura), e o
-- denominador sem lado vivo entra pela esquerda vazia (abstenção, não falha — lado que
-- não teve jogo na janela não derivou, só não foi medido).
confronto AS (
    SELECT
        COALESCE(c.market, v.market) AS market,
        COALESCE(c.lado,   v.lado)   AS lado,
        c.p95_congelado,
        c.medido_em,
        c.janela_congelada_ate,
        v.p95_vivo,
        COALESCE(v.n_vivo, 0)             AS n_vivo,
        COALESCE(v.profundidade_dias, 0)  AS profundidade_dias
    FROM congelado c
    FULL OUTER JOIN vivo v
        ON  v.market = c.market
       AND  v.lado   = c.lado
),

veredito AS (
    SELECT
        *,
        (p95_congelado IS NULL) AS sem_denominador,
        -- só há o que cobrar com denominador congelado, amostra suficiente E janela cheia
        -- até o fundo. As três condições, e as três declaradas no cabeçalho.
        (p95_congelado IS NOT NULL
         AND n_vivo >= {{ var('p95_deriva_min_linhas') }}
         AND profundidade_dias >= {{ var('p95_deriva_janela_dias') }}) AS cobravel,
        -- a distância, em fração do congelado. NULL quando o congelado é zero — e é por
        -- isso que o zero tem ramo próprio no `WHERE` lá embaixo, em vez de cair aqui.
        IF(p95_congelado > 0,
           ABS(p95_vivo - p95_congelado) / p95_congelado,
           NULL) AS distancia_rel
    FROM confronto
)

SELECT
    market,
    lado,
    p95_congelado,
    p95_vivo,
    n_vivo,
    profundidade_dias,
    ROUND(distancia_rel, 4) AS distancia_rel,
    {{ var('p95_deriva_tolerancia_rel') }} AS tolerancia_rel,
    medido_em,
    janela_congelada_ate,
    CASE
        WHEN sem_denominador
            THEN 'lado presente no funil e ausente do seed futebol_p95_nota_contexto — o p95 chega NULL, a nota normalizada vira zero e a linha reprova a régua em silêncio; medir o lado (analyses/taskA_a6_p95.sql) e acrescentá-lo ao seed'
        WHEN p95_congelado = 0
            THEN 'lado congelado em ZERO (sem lado apostado) passou a ter premissa acendendo — mudança de catálogo: remedir o p95 e recongelar o seed'
        ELSE 'p95 vivo se afastou do congelado além da tolerância declarada — o denominador envelheceu (catálogo, liga nova ou premissa removida); remedir com analyses/taskA_a6_p95.sql e recongelar o seed, com janela e data novas'
    END AS diagnostico
FROM veredito
WHERE sem_denominador
   OR (cobravel AND p95_congelado = 0 AND p95_vivo > 0)
   OR (cobravel AND p95_congelado > 0
       AND distancia_rel > {{ var('p95_deriva_tolerancia_rel') }})
ORDER BY market, lado
