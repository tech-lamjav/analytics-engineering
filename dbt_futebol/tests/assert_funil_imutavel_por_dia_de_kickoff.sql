{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DE IMUTABILIDADE (#96, ADR 0011): contagem e soma de nota, por dia de kickoff já
-- passado, não mudam entre builds.
--
-- É a guarda que dá sentido à ordem em que a [A] foi fatiada. A A7 entra ANTES da A1
-- porque, quando o preço sair da nota e as portas mudarem, o funil de antes tem de
-- continuar exatamente como estava. Uma tabela reconstruída reescreveria 16/06 em diante
-- sob as regras novas e o funil antigo — a coisa inteira que a A7 existe para salvar —
-- deixaria de existir sem deixar rastro. Esta guarda é o rastro.
--
-- ⚠️ ELA COMPARA CONTRA UM REGISTRO ESCRITO FORA DO FUNIL (`fact_value_funnel_selo`), e
-- essa é a decisão inteira. A versão tentadora seria conferir a coerência interna do
-- funil — `gravado_em` contra `kickoff_utc`, portas contra `passou_no_gate`. Ela FECHA
-- SEMPRE depois de um rebuild, porque a tabela reconstruída é internamente coerente e
-- inteiramente nova. É a mesma armadilha da costura B da task [F] e a mesma razão pela
-- qual a `assert_funil_reconcilia_com_devig` lê a fonte: guarda que lê só o próprio
-- produto não é guarda, é uma segunda cópia dele.
--
-- O que ela pega, e o que cada caso significa:
--
--   · CONTAGEM diferente — linha nasceu ou sumiu num dia já encerrado. O filtro de
--     congelamento do modelo parou de valer, ou a tabela foi reconstruída;
--   · SOMA DE NOTA diferente com a mesma contagem — as mesmas linhas foram REPONTUADAS.
--     É o modo de falha silencioso, e é exatamente o que a A1/A2/A3/A5 provocariam num
--     funil reconstruído: mesma população, régua nova, história reescrita;
--   · agregado AUSENTE para um selo cujo fixture ainda mora naquele dia — as linhas do
--     jogo desapareceram do funil inteiras.
--
-- ⚠️ SELO ÓRFÃO É IGNORADO, e é a exceção que o jogo adiado exige (ADR 0011). `PST`/`SUSP`
-- devolvem o kickoff para o futuro, a linha volta a ser gravável e o jogo passa a morar
-- em OUTRO dia. O selo do dia velho continua lá descrevendo um dia em que aquele fixture
-- não está mais, e acusá-lo seria acender vermelho sobre o comportamento correto. A
-- condição `dia_atual = dia_kickoff` é o que separa "o fixture mudou de dia" (silêncio,
-- ele sela de novo quando o dia novo passar) de "as linhas sumiram" (vermelho: o fixture
-- não aparece em lugar nenhum do funil, `dia_atual` vem NULL, e o COALESCE o traz para
-- dentro).
--
-- ⚠️ Ponto cego declarado, o de sempre (ADR 0005, subtask C4): até a C4 fechar, o job do
-- agendado devolve sucesso mesmo com esta guarda vermelha.

WITH funil AS (
    SELECT
        fixture_id,
        DATE(kickoff_utc) AS dia_kickoff,
        score
    FROM {{ ref('fact_value_funnel') }}
    WHERE kickoff_utc IS NOT NULL
),

-- Onde cada fixture mora AGORA. É o que distingue o jogo adiado do jogo apagado.
dia_atual AS (
    SELECT
        fixture_id,
        MAX(dia_kickoff) AS dia_atual
    FROM funil
    GROUP BY fixture_id
),

agora AS (
    SELECT
        fixture_id,
        dia_kickoff,
        COUNT(*)                    AS linhas,
        -- NUMERIC dos dois lados: soma de FLOAT64 depende da ordem das parcelas e a ordem
        -- de leitura do BigQuery não é estável entre execuções — a guarda tremeria no
        -- último bit sem defeito nenhum (#92).
        SUM(CAST(score AS NUMERIC)) AS soma_nota
    FROM funil
    GROUP BY fixture_id, dia_kickoff
)

SELECT
    s.fixture_id,
    s.dia_kickoff,
    s.selado_em,
    s.linhas       AS linhas_seladas,
    a.linhas       AS linhas_agora,
    s.soma_nota    AS soma_nota_selada,
    a.soma_nota    AS soma_nota_agora,
    CASE
        WHEN a.fixture_id IS NULL
            THEN 'dia de kickoff selado que não existe mais no funil — as linhas do jogo foram apagadas'
        WHEN a.linhas <> s.linhas
            THEN 'contagem de um dia de kickoff já passado mudou desde o selo — linha nasceu ou sumiu depois do apito, ou a tabela foi reconstruída'
        ELSE 'mesma contagem e SOMA DE NOTA diferente: as mesmas linhas foram repontuadas sob uma régua que não existia quando o jogo aconteceu — a história do funil foi reescrita'
    END AS diagnostico
FROM {{ ref('fact_value_funnel_selo') }} s
LEFT JOIN agora     a USING (fixture_id, dia_kickoff)
LEFT JOIN dia_atual d USING (fixture_id)
-- selo órfão (o fixture mudou de dia) sai daqui; fixture sumido do funil inteiro fica.
WHERE COALESCE(d.dia_atual, s.dia_kickoff) = s.dia_kickoff
  AND (
        a.fixture_id IS NULL
     OR a.linhas    <> s.linhas
     OR a.soma_nota IS DISTINCT FROM s.soma_nota
      )
