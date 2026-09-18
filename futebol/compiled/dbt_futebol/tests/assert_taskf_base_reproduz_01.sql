
-- COSTURA B da task [F] (issue #49, ticket #55), invariante 3 de 3 — A CÉLULA `base` REPRODUZ O
-- TESTE 2 PUBLICADO DA TASK [0.1].
--
-- `base` é a célula que não muda nada: escopo na competição do jogo, recorte na temporada
-- corrente, que é o que roda hoje. Se ela não reproduz o número publicado, o caminho inteiro da
-- medição — var → target → dataset → Teste 2 — está errado em algum ponto, e as outras três
-- células não têm como significar coisa alguma. É a única das três invariantes que compara a
-- medição contra algo de FORA dela.
--
-- ⚠️ ELA É VERDE POR CONGELAMENTO DESDE A ADR 0010, E ISSO É DELIBERADO. O cabeçalho abaixo
-- previa que ela ficaria vermelha "na próxima remedição", quando as células fossem reconstruídas.
-- Elas não serão: a ADR 0010 decidiu que a remedição roda em produção, e a #82 pôs a célula
-- reconstruída em `taskf_teste2_ancora`, fora da acumulativa que esta guarda lê. Então ela segue
-- comparando a `base` de 12–13/08 contra os números publicados da [0.1] — duas coisas paradas,
-- que continuam batendo e continuarão. A aposentadoria dela (com o dataset de medição) é limpeza
-- da task [B]; até lá, verde aqui significa "o registro congelado segue íntegro", e não "a
-- medição de hoje reproduz a [0.1]".
--
-- ⚠️ E É `base` NO UNIVERSO `completo` (#58). Esta é a única das quatro guardas que NÃO se
-- generaliza para os outros universos, e a razão não é economia: o lado esquerdo da comparação são
-- os números PUBLICADOS da [0.1], que existem para um recorte só — os 169 jogos de 16/06 a 04/08.
-- Não há [0.1] "sem Copa do Mundo" nem [0.1] estendida contra a qual reproduzir. Cobrar os outros
-- universos aqui seria compará-los com o gabarito errado.
--
-- ⚠️ ESTA GUARDA NÃO SUBSTITUI A `analyses/taskf_reconciliacao_01.sql`, e as duas não são cópia
-- uma da outra. A reconciliação EXPLICA a divergência: mede se o mecanismo de deriva de odds
-- existe na janela (`capturas_apos_o_teto`), se a correção da spec #22 alcança o benchmark
-- preferido, e classifica cada linha em `deriva_de_odds` / `correcao_22` / `investigar`. Ela é
-- leitura humana, e produz o texto de `docs/TASKF_RESULTADOS.md`. Esta aqui só responde
-- vermelho/verde contra a régua declarada, que é o que uma guarda faz — e é por isso que ela é
-- muito menor.
--
-- ────────────────────────────────────────────────────────────────────────────────
-- A RÉGUA, E POR QUE ELA VALE PARA DUAS PREMISSAS E NÃO PARA AS 39
--
--   as 37 restantes    IGUALDADE EXATA em todo campo publicado. Elas leem fixture, estatística
--                      ou tabela — insumos determinísticos sobre um universo congelado. Não há
--                      deriva legítima para acomodar, e acomodar assim mesmo seria a régua
--                      virando desculpa.
--   linha_subindo e    `taskf_tolerancia_pp` (0,25 pp) nos campos medidos EM PONTOS PERCENTUAIS.
--   linha_descendo     São as duas únicas que comparam preço com preço: acendem quando a média
--                      das probabilidades implícitas de todas as casas sobe de t24h para t15m, e
--                      o fechamento é a última janela disponível no momento do build.
--
-- ⚠️ O VALOR É 0,25 pp DESDE 19/08/2026 (#92). ANTES ERA 0,5, E O 0,5 NUNCA FOI MEDIDO.
--
-- Ele foi declarado antes de medir, calibrado por uma frase de `docs/TASK01_RESULTADOS.md` — "o
-- mercado de Gols anda 0,2–0,4 pp entre execuções sem que nada mude". Aqueles 0,2–0,4 pp são
-- deltas de ROI do TESTE 3 (ticket #4 daquele doc), e o Teste 3 é um agregado atrás de um
-- LIMIAR: 0,07% das linhas trocando de lado moveu o ROI do mercado em 0,4 pp. Esta régua governa
-- os campos por premissa do TESTE 2, que são médias. Na MESMA reconciliação de 04/08 as seis
-- linhas do Teste 2 reproduziram com delta EXATAMENTE 0,0. Ou seja: a régua foi calibrada por
-- uma métrica diferente da que ela mede, e a métrica que ela mede nunca tinha se mexido.
--
-- O 0,25 é medido, e é a soma de quatro parcelas, cada uma com número (#92, 19/08, N=8 —
-- `analyses/taskf_ruido_do_instrumento.sql` e `docs/TASKF_RESULTADOS.md`):
--
--   ruído de instrumento       0,00 pp. Duas camadas, as duas em 8 execuções: a reconstrução das
--                              premissas devolve fingerprint XOR por linha IDÊNTICO (pós-#78 a
--                              soma é NUMERIC, exata, não depende da ordem), e a agregação do
--                              Teste 2 não move um único campo arredondado.
--   deriva legítima de odds    0,00 pp NESTE universo. `capturas_apos_o_teto` remedido em 19/08:
--                              zero, última captura em 03/08. Ver o ⚠️ da janela congelada acima.
--   resíduo conhecido do       0,2 pp, medido: com `--vars '{taskf_tolerancia_pp: 0}'` a guarda
--   `linha_descendo`           acende 6 campos e só eles, deltas 0,1/0,1/0,1/0,2/0,2/0,2.
--   grade do ROUND(·, 1)       0,05 pp de meia-grade, para o número não ficar EM CIMA da grade —
--                              ver o parágrafo do knife-edge logo abaixo.
--
-- Por que 0,25 e não 0,2: os dois lados da comparação são impressos em UMA casa, então a
-- subtração em FLOAT64 de dois valores da grade não devolve 0,2 e sim 0,20000000000000284 — que
-- é `> 0.2` e deixaria a guarda vermelha no próprio resíduo que a régua declara cobrir. 0,25 cai
-- no meio da grade: admite |Δ| até 0,2 e recusa a partir de 0,3, sem depender do último bit.
--
-- ⚠️ E 0,25 É CALIBRADO PARA O UNIVERSO `completo`, QUE É O ÚNICO QUE ESTA GUARDA COMPARA. A
-- segunda parcela é zero porque a coleta parou antes do teto; no universo `estendido`, que
-- alcança o presente, ela NÃO é zero e não foi medida — a #78 não a tocou. Quem escrever a
-- primeira comparação sobre o estendido mede essa componente ANTES de reusar este número.
--
-- Ele mora em `taskf_tolerancia_pp`, o MESMO var da reconciliação: a régua existe uma vez.
--
-- ⚠️ NOS CAMPOS FORA DA ESCALA EM PP (`n_p0`, `n_p5`, `jogos_medios`, os dois pesos) essas duas
-- premissas NÃO são cobradas, e isso é decisão consciente, não esquecimento. A régua declarada é
-- em pp; inventar aqui um segundo limite para contagem seria calibrar um número até a medição
-- passar, que é o vício que esta task inteira existe para não cometer. O que esses campos fazem
-- quando divergem é aparecer na reconciliação, em `campos_divergentes_fora_da_regua`, com o
-- número ao lado — e o resíduo conhecido (as 2 linhas de aposta de 405 que `linha_descendo`
-- perdeu, ≤ 0,2 pp) está documentado e delimitado em `docs/TASKF_RESULTADOS.md`.
--
-- ⚠️ E A JUSTIFICATIVA DA TOLERÂNCIA NÃO SE APLICA A UMA JANELA CONGELADA — achado da #51. A
-- coleta de odds é forward-only e para no apito: para os 169 jogos do universo congelado há ZERO
-- capturas posteriores ao teto, então o insumo dessas duas é imóvel e a folga está cobrindo um
-- mecanismo que ali não existe. (⚠️ A #92 tirou daqui a conclusão que estava escrita nesta linha —
-- "ela continua declarada porque volta a ter mordida no universo estendido". A folga continua
-- declarada, mas por OUTRO motivo, e menor: o resíduo conhecido do `linha_descendo`, medido. O
-- universo estendido nunca foi medido e deixou de ser a justificativa; ver a decomposição das
-- quatro parcelas acima.) Quem quiser o veredito honesto sobre a
-- divergência de hoje lê a reconciliação, que se recusa a chamá-la de deriva e a marca
-- `INVESTIGAR`. A guarda é deliberadamente a mais frouxa das duas leituras: ela protege o
-- caminho da medição, não a explicação do resíduo.
--
-- ⚠️ O MODO DE FALHA CONHECIDO DESTA GUARDA É O EMPATE DE ARREDONDAMENTO, e quem a vir vermelha
-- deve descartá-lo ANTES de procurar bug. O `AVG` do BigQuery acumula em ponto flutuante e a
-- ordem depende do layout físico da tabela, que muda quando os modelos são reconstruídos; um valor
-- exatamente no meio da grade de `ROUND(·, 1)` cai para um lado numa medição e para o outro na
-- seguinte. A própria #55 mediu isso: entre duas medições sobre os MESMOS fatos, 5 campos de 7.200
-- viraram 0,1 — e um deles era `aconteceu_p10` da `base`, que só não bate aqui porque a linha é de
-- consenso e o `usado_para_peso` a deixa de fora. Numa linha de benchmark preferido o mesmo empate
-- deixa esta guarda VERMELHA sem defeito nenhum por trás.
--
-- Ela continua EXATA assim mesmo, e a escolha é deliberada: uma folga de 0,1 em todos os campos
-- engoliria divergência real de 0,1 pp, que é a ordem de grandeza do que esta task mede. O
-- diagnóstico é aritmético e fechado, não opinião — pegue o `n` da linha, veja se o valor cai em
-- cima de um múltiplo de meia unidade da grade (51/400 = 12,75; 308/320 = 96,25; 492/48 = 10,25) e,
-- se cair, é empate. `analyses/taskf_remedicao.sql` faz essa comparação entre duas medições e é
-- onde o caso se confirma.
--
-- ⚠️ ESSE MODO DE FALHA ESTÁ MORTO DESDE A #78, E ISSO FOI MEDIDO NA #92 — descarte-o em dois
-- segundos, não em duas horas. O parágrafo acima fica porque descreve um fenômeno que de fato
-- aconteceu (5 campos em 7.200 viraram 0,1 entre duas medições, e é assim que ele se
-- diagnostica); o que mudou é o tamanho do tremor que o alimenta:
--
--     tremor da agregação entre 8 execuções sobre insumo imóvel   ~1e-12 pp
--     menor folga até a fronteira do ROUND(·, 1), em 360 campos    4,1e-4 pp
--     idem, só nas duas premissas de odds que a régua cobre        3,6e-3 pp
--
-- São OITO ordens de grandeza de distância. O empate não é raro nesta base: ele é impossível,
-- e continua impossível até algum campo chegar a 1e-12 da grade. Quem vir esta guarda vermelha
-- agora está olhando para divergência de verdade — a regra de descarte se inverteu.
--
-- ⚠️ CORREÇÃO DE DUAS COISAS DITAS ACIMA, MEDIDAS NA #78 — leia antes de usar este parágrafo.
--
--   1. "a ordem depende do layout físico da tabela, que muda quando os modelos são reconstruídos"
--      é MAIS BENIGNO do que a realidade. A ordem muda entre EXECUÇÕES, sobre a MESMA tabela, sem
--      reconstrução nenhuma: o `AVG` funde as médias PARCIAIS dos shards em ponto flutuante e o
--      particionamento varia sozinho. Seis execuções da mesma SQL sobre insumo congelado deram
--      quatro valores distintos de `superioridade_xg`. Não é preciso reconstruir nada para a
--      guarda virar.
--   2. A régua acima diz que as 37 premissas fora de `linha_subindo`/`linha_descendo` leem
--      "insumos determinísticos sobre um universo congelado". Isso era FALSO para quatro delas —
--      `superioridade_xg`, `xg_combinado_alto`, `xg_baixo_combinado` e `ritmo_alto` —, e uma das
--      16 linhas de borda do 1X2 cai dentro da janela publicada da [0.1]. A guarda tinha uma linha
--      capaz de virar sozinha a cada remedição.
--
-- A #78 tornou a afirmação VERDADEIRA na produção (nenhum modelo de premissa usa mais `AVG` nem
-- `APPROX_QUANTILES` — ver tests/assert_premissas_sem_agregado_instavel.sql). A contrapartida é
-- que os números de `macros/taskf_publicado_01.sql` foram medidos sob a regra antiga:
--
--   ⚠️ NA PRÓXIMA RECONSTRUÇÃO DAS CÉLULAS DA [F] ESTA GUARDA FICA VERMELHA DE PROPÓSITO,
--      em `superioridade_xg`, `xg_combinado_alto`, `xg_baixo_combinado` e `ritmo_alto`.
--
-- Não é bug e não é o empate de arredondamento descrito acima: é a correção chegando à medição.
-- O rebaseline dos quatro exige remedir as células (um `dbt run --target taskF`) e ficou FORA da
-- #78 por isso — está no ticket de follow-up. Enquanto ele não roda, a guarda segue verde, porque
-- as células materializadas hoje são as da regra antiga.
--
-- ────────────────────────────────────────────────────────────────────────────────
-- O QUE É COMPARÁVEL. O doc da [0.1] publica três recortes diferentes (ver
-- macros/taskf_publicado_01.sql), então nem toda linha tem todo campo — NULL ali significa NÃO
-- PUBLICADO, nunca zero, e campo não publicado não é comparado. Só o benchmark PREFERIDO de cada
-- mercado entra (`usado_para_peso`), que é o recorte que o doc publica; as linhas de consenso do
-- Handicap e do Gols não têm contraparte e ficam fora de propósito.
--
-- NÃO-VACUIDADE, porque "não achei divergência" é o veredito natural de quem não comparou nada:
--
--   sem_contraparte    FULL OUTER JOIN, 39 de cada lado. Uma premissa renomeada, um `base` que
--                      não foi medido ou um filtro que zerou a leitura caem aqui, e não em
--                      silêncio verde.
--   linha_sem_campo    nenhuma linha comparada pode ter ZERO campos comparáveis.
--
-- QUEM RODA: a FASE 3 da receita do analyses/taskf_teste2.sql, depois das quatro células —
-- `dbt test --target taskF --select tag:costura_b`. Não é o agendado (tag `guarda`).
--
-- Falsificada de propósito com `--vars '{taskf_tolerancia_pp: 0}'`, que tira a folga e deixa a
-- divergência de `linha_descendo` vermelha; o comando e o resultado estão em
-- `docs/TASKF_RESULTADOS.md`, seção do ticket #55. A #92 acrescentou a falsificação do valor
-- NOVO — `--vars '{taskf_tolerancia_pp: 0.15}'` derruba só os três campos de delta 0,2 —, que é
-- o que prova que 0,25 ainda morde em vez de ser folga de sobra.

WITH 

publicado_01 AS (
    SELECT * FROM UNNEST([
        STRUCT<mercado STRING, premissa STRING,
               n_p0 INT64, a_odd_dava_p0 FLOAT64, aconteceu_p0 FLOAT64, diferenca_p0 FLOAT64,
               jogos_medios FLOAT64, pct_amostra_curta FLOAT64,
               peso_p0 FLOAT64, peso_p0_k0 FLOAT64,
               n_p5 INT64, diferenca_p5 FLOAT64, diferenca_p10 FLOAT64>
        ('Gols',         'clean_sheets_altos',     105, 51.5, 68.6,  17.1,  5.3, 77.1, 11.58, 17.10,   24,  -1.7, -10.1),
        ('Handicap',     'raramente_perde_por_2',  445, 63.1, 69.4,   6.3, 14.1, 20.9,  5.67,  6.31,  352,   7.4,   7.7),
        ('Handicap',     'favorito_irregular',     453, 62.3, 68.2,   5.9, 14.8, 17.4,  5.29,  5.88,  374,   7.1,   7.9),
        ('BTTS',         'ataque_dos_dois',         32, 50.6, 62.5,  11.9, 12.1, 37.5,  4.65, 11.91, NULL,  NULL,  NULL),
        ('1X2',          'superioridade_xg',       109, 38.0, 43.1,   5.2,  6.3, 71.6,  3.54,  5.17,   31,  -8.9, -12.3),
        ('Handicap',     'defesa_fora_solida',     322, 62.5, 66.5,   3.9,  8.4, 58.4,  3.39,  3.92,  134,   2.6,   2.8),
        ('Gols',         'defesas_firmes',         246, 64.6, 68.3,   3.7, 11.4, 40.7,  3.05,  3.67, NULL,  NULL,  NULL),
        ('Handicap',     'tende_golear',           154, 44.2, 48.1,   3.9,  3.5, 88.3,  2.91,  3.86,   18, -18.5, -22.3),
        ('Gols',         'linha_descendo',         405, 53.0, 56.0,   3.1, 10.3, 46.9,  2.74,  3.08,  215,   5.3,   5.3),
        ('Dupla Chance', 'lado_coberto_forte',     112, 74.0, 76.8,   2.8,  8.6, 58.0,  1.92,  2.78, NULL,  NULL,  NULL),
        ('Gols',         'ataques_fracos',         357, 51.7, 53.8,   2.1,  9.6, 50.1,  1.81,  2.07,  178,  -1.1,  -1.1),
        ('BTTS',         'defesa_forte',            70, 52.9, 55.7,   2.8,  4.4, 82.9,  1.65,  2.82,   12,  -3.3,  -6.3),
        ('1X2',          'mando',                  107, 43.4, 45.8,   2.4,  9.0, 55.1,  1.63,  2.39,   48,  -6.4,  -8.3),
        ('Dupla Chance', 'equilibrio_defensivo',   144, 63.3, 65.3,   2.0,  9.0, 54.2,  1.49,  2.01,   66,   6.4,   7.7),
        ('Gols',         'xg_baixo_combinado',     307, 64.9, 66.4,   1.5,  8.7, 56.7,  1.31,  1.52,  133,   3.6,   4.1),
        ('BTTS',         'defesas_vazaveis',        58, 47.8, 50.0,   2.2, 10.3, 46.6,  1.20,  2.24,   31,   8.7,   8.7),
        ('Gols',         'historico_under',        144, 70.0, 71.5,   1.5, 17.0,  3.5,  1.11,  1.50,  139,   1.2,   2.1),
        ('1X2',          'superioridade_tabela',    98, 50.2, 51.0,   0.8,  7.6, 64.3,  0.55,  0.82,   35,  -8.2,  -8.2),
        ('Dupla Chance', 'adversario_limitado',    160, 68.7, 69.4,   0.7,  9.7, 50.0,  0.51,  0.66, NULL,  NULL,  NULL),
        ('BTTS',         'historico_btts',          16, 50.0, 50.0,   0.0, 18.4,  0.0,  0.01,  0.03, NULL,  NULL,  NULL),
        ('Gols',         'historico_over',        NULL, NULL, NULL,  -0.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'historico_seco',        NULL, NULL, NULL,  -0.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'forma',                 NULL, NULL, NULL,  -1.4, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'linha_subindo',         NULL, NULL, NULL,  -1.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'supremacia',            NULL, NULL, NULL,  -1.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'ataque_trava',          NULL, NULL, NULL,  -2.2, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'ambos_marcam',          NULL, NULL, NULL,  -2.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'xg_combinado_alto',     NULL, NULL, NULL,  -2.6, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'sem_rodizio',           NULL, NULL, NULL,  -2.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'adversario_fragil_fora',NULL, NULL, NULL,  -2.8, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'mando_forte',           NULL, NULL, NULL,  -3.1, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'forca_mismatch',        NULL, NULL, NULL,  -3.1, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ataque_combinado',      NULL, NULL, NULL,  -3.6, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ambos_vazam',           NULL, NULL, NULL,  -3.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'defesas_vazaveis',      NULL, NULL, NULL,  -5.0, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ritmo_alto',            NULL, NULL, NULL,  -5.3, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'h2h_favoravel',         NULL, NULL, NULL, -10.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Dupla Chance', 'invicto_recente',       NULL, NULL, NULL, -10.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'desfalque_adversario',     7, NULL, NULL, -24.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL)
    ])
)

,

medido AS (
    SELECT
        mercado, premissa,
        n_p0,
        a_odd_dava_p0,
        aconteceu_p0,
        diferenca_p0,
        jogos_medios_disp AS jogos_medios,
        pct_amostra_curta,
        peso_p0,
        peso_p0_k0,
        n_p5,
        diferenca_p5,
        diferenca_p10
    FROM `smartbetting-dados`.`futebol_taskF`.`taskf_teste2`
    WHERE celula = 'base'
      AND universo = 'completo'
      AND usado_para_peso
),

-- FULL OUTER para que a linha sem contraparte apareça de qualquer um dos dois lados.
juntado AS (
    SELECT
        COALESCE(m.mercado,  p.mercado)  AS mercado,
        COALESCE(m.premissa, p.premissa) AS premissa,
        m.mercado IS NULL AS so_no_publicado,
        p.mercado IS NULL AS so_no_medido,
        m.n_p0 AS n_p0_medido,
        p.n_p0 AS n_p0_pub,
        m.a_odd_dava_p0 AS a_odd_dava_p0_medido,
        p.a_odd_dava_p0 AS a_odd_dava_p0_pub,
        m.aconteceu_p0 AS aconteceu_p0_medido,
        p.aconteceu_p0 AS aconteceu_p0_pub,
        m.diferenca_p0 AS diferenca_p0_medido,
        p.diferenca_p0 AS diferenca_p0_pub,
        m.jogos_medios AS jogos_medios_medido,
        p.jogos_medios AS jogos_medios_pub,
        m.pct_amostra_curta AS pct_amostra_curta_medido,
        p.pct_amostra_curta AS pct_amostra_curta_pub,
        m.peso_p0 AS peso_p0_medido,
        p.peso_p0 AS peso_p0_pub,
        m.peso_p0_k0 AS peso_p0_k0_medido,
        p.peso_p0_k0 AS peso_p0_k0_pub,
        m.n_p5 AS n_p5_medido,
        p.n_p5 AS n_p5_pub,
        m.diferenca_p5 AS diferenca_p5_medido,
        p.diferenca_p5 AS diferenca_p5_pub,
        m.diferenca_p10 AS diferenca_p10_medido,
        p.diferenca_p10 AS diferenca_p10_pub
    FROM medido AS m
    FULL OUTER JOIN publicado_01 AS p
      ON  p.mercado  = m.mercado
      AND p.premissa = m.premissa
),

-- Um registro por (linha, campo), para a comparação ser escrita UMA vez em vez de onze. CAST para
-- FLOAT64 porque `n_p0`/`n_p5` são INT64 e a régua é a mesma conta nos dois casos.
por_campo AS (
    SELECT
        j.mercado,
        j.premissa,
        j.premissa IN ("linha_subindo", "linha_descendo") AS premissa_de_odds,
        c.*
    FROM juntado AS j,
    UNNEST([
        STRUCT('n_p0'                        AS campo,
               false                 AS em_pp,
               CAST(j.n_p0_medido AS FLOAT64) AS medido,
               CAST(j.n_p0_pub    AS FLOAT64) AS publicado),
        STRUCT('a_odd_dava_p0'                        AS campo,
               true                 AS em_pp,
               CAST(j.a_odd_dava_p0_medido AS FLOAT64) AS medido,
               CAST(j.a_odd_dava_p0_pub    AS FLOAT64) AS publicado),
        STRUCT('aconteceu_p0'                        AS campo,
               true                 AS em_pp,
               CAST(j.aconteceu_p0_medido AS FLOAT64) AS medido,
               CAST(j.aconteceu_p0_pub    AS FLOAT64) AS publicado),
        STRUCT('diferenca_p0'                        AS campo,
               true                 AS em_pp,
               CAST(j.diferenca_p0_medido AS FLOAT64) AS medido,
               CAST(j.diferenca_p0_pub    AS FLOAT64) AS publicado),
        STRUCT('jogos_medios'                        AS campo,
               false                 AS em_pp,
               CAST(j.jogos_medios_medido AS FLOAT64) AS medido,
               CAST(j.jogos_medios_pub    AS FLOAT64) AS publicado),
        STRUCT('pct_amostra_curta'                        AS campo,
               true                 AS em_pp,
               CAST(j.pct_amostra_curta_medido AS FLOAT64) AS medido,
               CAST(j.pct_amostra_curta_pub    AS FLOAT64) AS publicado),
        STRUCT('peso_p0'                        AS campo,
               false                 AS em_pp,
               CAST(j.peso_p0_medido AS FLOAT64) AS medido,
               CAST(j.peso_p0_pub    AS FLOAT64) AS publicado),
        STRUCT('peso_p0_k0'                        AS campo,
               false                 AS em_pp,
               CAST(j.peso_p0_k0_medido AS FLOAT64) AS medido,
               CAST(j.peso_p0_k0_pub    AS FLOAT64) AS publicado),
        STRUCT('n_p5'                        AS campo,
               false                 AS em_pp,
               CAST(j.n_p5_medido AS FLOAT64) AS medido,
               CAST(j.n_p5_pub    AS FLOAT64) AS publicado),
        STRUCT('diferenca_p5'                        AS campo,
               true                 AS em_pp,
               CAST(j.diferenca_p5_medido AS FLOAT64) AS medido,
               CAST(j.diferenca_p5_pub    AS FLOAT64) AS publicado),
        STRUCT('diferenca_p10'                        AS campo,
               true                 AS em_pp,
               CAST(j.diferenca_p10_medido AS FLOAT64) AS medido,
               CAST(j.diferenca_p10_pub    AS FLOAT64) AS publicado)
    ]) AS c
    WHERE NOT j.so_no_medido AND NOT j.so_no_publicado
),

divergencias AS (
    SELECT
        'campo_divergente' AS motivo,
        TO_JSON_STRING(STRUCT(
            mercado, premissa, campo, premissa_de_odds, em_pp,
            publicado, medido,
            ROUND(medido - publicado, 2) AS delta,
            IF(premissa_de_odds, 0.25, 0.0) AS regua
        )) AS linha
    FROM por_campo
    WHERE publicado IS NOT NULL
      AND CASE
              -- As 37 determinísticas: exato, em todo campo publicado.
              WHEN NOT premissa_de_odds THEN medido IS DISTINCT FROM publicado
              -- As duas de odds, campo em pp: a régua declarada.
              WHEN em_pp THEN medido IS NULL OR ABS(medido - publicado) > 0.25
              -- As duas de odds, campo fora da escala em pp: não cobrado. Ver o cabeçalho.
              ELSE FALSE
          END
),

-- NÃO-VACUIDADE 1: 39 de cada lado, nenhum órfão.
sem_contraparte AS (
    SELECT
        'sem_contraparte' AS motivo,
        TO_JSON_STRING(STRUCT(
            mercado, premissa, so_no_medido, so_no_publicado,
            (SELECT COUNT(*) FROM medido)       AS linhas_medidas,
            (SELECT COUNT(*) FROM publicado_01) AS linhas_publicadas
        )) AS linha
    FROM juntado
    WHERE so_no_medido OR so_no_publicado
),

-- NÃO-VACUIDADE 2: toda linha comparada tem pelo menos um campo comparável. No macro publicado
-- isso é verdade por construção (toda linha publica ao menos a diferença no piso 0), e é
-- justamente por isso que vale conferir: se deixar de ser, a linha some da comparação sem sumir
-- da contagem.
linha_sem_campo AS (
    SELECT
        'linha_sem_campo' AS motivo,
        TO_JSON_STRING(STRUCT(mercado, premissa, campos_comparaveis)) AS linha
    FROM (
        SELECT mercado, premissa, COUNTIF(publicado IS NOT NULL) AS campos_comparaveis
        FROM por_campo
        GROUP BY mercado, premissa
    )
    WHERE campos_comparaveis = 0
)

SELECT motivo, linha FROM divergencias
UNION ALL
SELECT motivo, linha FROM sem_contraparte
UNION ALL
SELECT motivo, linha FROM linha_sem_campo