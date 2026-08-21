{{ config(tags=['guarda'], severity='error') }}
-- GUARDA DE CONGELAMENTO (#96, ADR 0011): nenhuma linha do funil foi escrita depois do
-- apito inicial do seu próprio jogo.
--
-- É a guarda que prova a promessa central da entrega. O funil deixou de ser uma foto do
-- que o código de hoje diria e passou a ser registro do que o Motor disse — e "o que ele
-- disse" só vale se tiver sido dito ANTES de a bola rolar. Uma linha com
-- `gravado_em > kickoff_utc` é nota que ninguém podia ter lido antes de apostar; ela não
-- responde a pergunta que o funil existe para responder, contamina ela (ADR 0009).
--
-- ⚠️ ESCOPADA A `origem = 'corrente'`, e a exclusão é obrigatória, não conveniência. O
-- backfill é o build que criou a tabela: ele recalculou 16/06 em diante com o código de
-- hoje, então `gravado_em` é POSTERIOR ao apito em toda linha de jogo já disputado, por
-- construção. Sem o escopo esta guarda nasceria vermelha em ~100% da história e morreria
-- ignorada no primeiro dia. É exatamente por isso que a `origem` existe como coluna: sem
-- ela não haveria como escrever esta guarda sem mentir.
--
-- ⚠️ E é justamente por causa desse escopo que ela NÃO cobre o rebuild. Um
-- `--full-refresh` reescreve a tabela inteira carimbada `backfill`, e passa por aqui em
-- silêncio. Quem pega isso é `assert_funil_imutavel_por_dia_de_kickoff`, que compara
-- contra um selo escrito FORA do funil. As duas guardas se completam e nenhuma das duas
-- substitui a outra.
--
-- ⚠️ Kickoff NULL (fixture ausente em `fact_fixtures`) cai fora do predicado sozinho —
-- `gravado_em > NULL` é NULL, nunca TRUE. É o comportamento certo: a linha é gravável
-- para sempre por decisão do modelo (fail-open, ADR 0003), e não dá para acusar atraso
-- contra um apito cuja hora não se sabe. Quem grita sobre fixture ausente é a
-- reconciliação, com diagnóstico próprio.
--
-- ⚠️ Ponto cego declarado, o de sempre (ADR 0005, subtask C4): até a C4 fechar, o job do
-- agendado devolve sucesso mesmo com esta guarda vermelha.

SELECT
    fixture_id,
    market,
    outcome,
    line_key,
    janela,
    kickoff_utc,
    gravado_em,
    origem,
    TIMESTAMP_DIFF(gravado_em, kickoff_utc, MINUTE) AS minutos_depois_do_apito,
    'linha escrita DEPOIS do apito do próprio jogo — o filtro de congelamento do modelo deixou passar, e esta nota nasceu com a bola rolando' AS diagnostico
FROM {{ ref('fact_value_funnel') }}
WHERE origem = 'corrente'
  AND gravado_em > kickoff_utc
