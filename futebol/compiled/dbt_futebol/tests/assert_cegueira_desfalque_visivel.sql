
-- GUARDA DA CEGUEIRA DE DESFALQUE (#42, ADR 0003) — duas direções, e nenhuma delas é a
-- asserção "premissa cega nunca acende": essa é garantida por CONSTRUÇÃO no
-- futebol_premissas_cegas() (a condição `NOT <premissa>` faz parte da expressão gerada) e
-- cobrá-la aqui seria guarda vacuosa, no sentido exato do cabeçalho da
-- assert_contador_sem_dado_vivo.
--
-- O que os dados podem responder, e as duas maneiras de esta entrega morrer em silêncio:
--
--   (1) O CONTADOR PARA DE VER O DESFALQUE. Basta alguém repor um COALESCE em s_missing/
--       o_missing e `desfalque_adversario` volta a chegar aqui como "avaliada e não acendeu"
--       em toda linha. Nada fica vermelho por si: o board segue igual, o contador segue
--       verde, só que menor que a verdade — que é o modo de falha que a ADR 0003 nomeia.
--
--   (2) O REGISTRO DE COLETA PARA DE CHEGAR. O `stg_futebol_injuries_coleta` reconhece o poll
--       por fixture pelo NOME DO ARQUIVO; se a ingestão renomear o arquivo, o modelo devolve
--       zero linha, TODO desfalque vira cego e as linhas em que a premissa legitimamente
--       acende somem do board sem nenhum erro. É o oposto da direção (1) e o mesmo silêncio.
--
-- Nenhuma das duas nasce vermelha: em 2026-08-14 são ~21 mil linhas com desfalque cego (a
-- coleta pré-jogo é forward-only desde 14/07 e cobre dezenas de jogos, não milhares) e 72
-- fixtures com registro pré-apito. Se um dia a direção (1) ficar verde por vacuidade — todo
-- jogo do portfólio com lista pré-apito —, é porque a cegueira acabou, e aí esta guarda vira
-- o aviso de que ela pode ser aposentada.

WITH cegueira AS (
    SELECT
        COUNT(*)                                                        AS n_linhas,
        COUNTIF('desfalque_adversario' IN UNNEST(premissas_cegas))      AS n_cegas
    FROM `smartbetting-dados`.`futebol`.`int_futebol_premissas_1x2`
),

registro AS (
    SELECT COUNT(*) AS n_registros
    FROM `smartbetting-dados`.`futebol`.`stg_futebol_injuries_coleta`
)

SELECT
    c.n_linhas,
    c.n_cegas,
    r.n_registros,
    CASE
        WHEN c.n_cegas = 0
            THEN 'nenhuma linha com desfalque cego: s_missing/o_missing voltaram a chegar preenchidos (COALESCE reposto?) e o contador deixou de enxergar desfalque_adversario'
        ELSE 'o registro de coleta do /injuries por fixture está vazio: o nome do arquivo mudou na ingestão e TODO desfalque virou cego — as premissas de desfalque legítimas sumiram do board'
    END AS diagnostico
FROM cegueira c
CROSS JOIN registro r
WHERE c.n_linhas > 0
  AND (c.n_cegas = 0 OR r.n_registros = 0)