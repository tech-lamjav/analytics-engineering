
-- Competição de INSUMO sem passado no mart (DE#96 no data-engineering, ADR 0004 lá, seção
-- "Medição (DE#95)") — trava de regressão do corte em stg_futebol_fixtures.sql.
--
-- Amistosos de seleção (league_id 10) entram em fact_fixtures só com kickoff a partir da data de
-- entrada declarada em macros/futebol_competicoes_insumo.sql. O raw traz a temporada inteira
-- (115 FT de jan–jun/2026), e a #95 mediu que esse passado deslocaria em ~23 pp a forma PIT de
-- âncoras de Copa do Mundo e Nations League já medidas, contra a régua de 0,25 pp.
--
-- Se este teste acender, o corte upstream foi removido, contornado (ex.: build de produção com a
-- var `taskf_incluir_amistosos`) ou a data de entrada foi recuada sem nova medição — o
-- deslocamento que a #95 recusou está no board.
--
-- Até a #96 este arquivo era assert_amistosos_fora_do_mart e reprovava QUALQUER linha da liga 10;
-- com o slug ligado, os jogos futuros são legítimos e só o passado é violação.
--
-- fact_fixtures é incremental (merge por fixture_id): uma linha que vazou NÃO sai sozinha quando
-- o corte volta — precisa de --full-refresh ou DELETE dirigido.

SELECT competition_id, competition, COUNT(*) AS jogos, MIN(kickoff_utc) AS primeiro_kickoff
FROM `smartbetting-dados`.`futebol`.`fact_fixtures`
WHERE (FALSE
        OR (competition_id = 10 AND kickoff_utc < TIMESTAMP('2026-09-23'))
    )
GROUP BY competition_id, competition