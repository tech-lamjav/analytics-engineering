{{ config(severity='warn') }}
-- ⚠️ APOSENTADA, NÃO APAGADA (PPP#365, ADR 0013, 2026-09-04). O `futebol_score_normalizado()`
-- deixou de dividir pela `futebol_p95_nota_contexto` — divide pelo teto do catálogo
-- (`futebol_teto_nota_contexto`). Esta guarda vigiava exatamente a coluna que saiu do
-- caminho vivo: rodá-la em `severity='error'` sob `tag:guarda` pagaria custo de BigQuery
-- todo dia por um número que não decide mais nada. Por isso o `tag:guarda` TAMBÉM saiu
-- do config — ela não entra mais na fase agendada nem no resumo diário, e "warn" aqui é
-- o "não é guarda de verdade" que o parágrafo original já dizia. Mantida (arquivo E seed
-- E fixture) para quem quiser reconsiderar o p95 no futuro, e como registro de como o
-- denominador era medido antes da PPP#365 — não é dead code por acidente, é decisão.
--
-- O texto abaixo descreve o que ela fazia QUANDO era guarda de produção; não editado,
-- porque o valor dele agora é histórico.
-- --------------------------------------------------------------------------------------
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
-- do Handicap estão congelados em zero porque nenhuma premissa se APLICA a eles — no 1X2 o
-- empate não tem lado apostado, e no Handicap todas as premissas são `is_favorito AND ...`
-- ou `is_azarao AND ...`, e as duas flags são FALSE na linha 0. A distância relativa
-- dividiria por zero e um `SAFE_DIVIDE` devolveria NULL — a guarda ficaria CEGA exatamente
-- nos dois lados onde a mudança é mais barata de detectar.
--
-- A regra é de PRESENÇA: com zero congelado, acende se o MÁXIMO vivo for maior que zero.
-- Uma premissa que passa a acender no empate é mudança de catálogo, e é o sinal que esta
-- guarda existe para dar.
--
-- ⚠️ MÁXIMO, e não o p95 — a distinção não é cosmética. `PERCENTILE_DISC(..., 0.95)` só sai
-- de zero depois que MAIS DE 5% das linhas do lado acendem; até lá uma mudança de catálogo
-- que fizesse premissa disparar em 3% dos empates passaria calada. Como ali nenhuma
-- premissa PODE acender, o máximo não tem falso positivo a temer: uma linha basta, e uma
-- linha é o que se quer ver.
--
-- ⚠️ E este ramo NÃO passa pelas condições de cobrança abaixo. Presença não é percentil:
-- não precisa de piso de amostra para ser estável nem de janela cheia para ser comparável.
-- Gatear ambos os ramos junto adiaria em trinta dias o único sinal que a guarda dá de
-- graça — e, no `Pick`, o piso de 200 sobre 648 linhas por janela chegaria a calá-lo numa
-- parada de calendário.
--
-- ⚠️ O PISO DE AMOSTRA É ABSTENÇÃO, e está declarado. Abaixo de `p95_deriva_min_linhas` o
-- lado não é cobrado: um p95 de trinta linhas anda de degrau sozinho e produziria vermelho
-- sem defeito. O preço é lado de baixo volume ficar sem vigilância numa janela magra —
-- dito aqui, e não escondido num `HAVING`.
--
-- A MARGEM ESTÁ MEDIDA, e é o que impede o piso de virar cegueira permanente. Numa janela
-- rolante de 30 dias (medida em 26/08), o lado mais magro é o do Resultado e o do Ambos
-- Marcam, com 325 candidatos cada — um por fixture, contra ~5.800 do Handicap e ~6.400 do
-- Gols, que têm um por LINHA. Com o piso em 200 a margem é de 1,6×, e os onze lados são
-- cobráveis.
--
-- ⚠️ Não confundir a margem com o `n_candidatos` do seed: lá são 476, sobre a janela INTEIRA
-- de 2,5 meses, e ela não é uniforme — o começo é backfill esparso. Dividir 476 por 76 dias
-- daria ~188 e concluiria que o Resultado e o BTTS nunca são cobrados; o número que vale é
-- o da janela rolante, que é 325.
--
-- ⚠️ O QUE ISSO AINDA DEIXA PASSAR: quinze dias de parada (data FIFA, virada de temporada)
-- levam esses dois mercados abaixo de 200 e a deriva deles fica sem vigilância enquanto
-- durar. É abstenção temporária e se cura sozinha quando o calendário volta — mas ela é
-- MUDA, e é a razão de estar escrita aqui: quem estranhar a guarda quieta num mercado
-- confere `n_vivo` na saída dela antes de concluir que o denominador está certo.
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
        -- o MÁXIMO, e não o p95, é o que o ramo do denominador ZERO cobra: ali a pergunta
        -- é "acendeu ALGUMA premissa?", e o p95 só enxergaria isso depois de 5% das linhas
        -- do lado acenderem. Ver o ⚠️ do cabeçalho.
        MAX(nota_contexto)                 OVER (PARTITION BY market, lado) AS max_vivo,
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
        v.max_vivo,
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
    max_vivo,
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
   -- o ramo do ZERO não passa pelo `cobravel`: ele não é percentil, é presença, e não tem
   -- de esperar amostra nem janela cheia para cobrar. Ver o ⚠️ do cabeçalho.
   OR (p95_congelado = 0 AND max_vivo > 0)
   OR (cobravel AND p95_congelado > 0
       AND distancia_rel > {{ var('p95_deriva_tolerancia_rel') }})
ORDER BY market, lado
