-- AE#160 (spec #157) — inventário dos valores distintos de rank_description por competição,
-- classificados pelo macro futebol_zona_tabela() (macros/futebol_zona_tabela.sql), e a
-- verificação manual que a AC pede.
--
-- MEDIDO em 14/09/2026 sobre fact_standings_snapshot (22.070 linhas, 11 competições com
-- standings — Copa do Brasil não tem standings, como já documentado em outras specs):
--
--   10.054 linhas com rank_description NULL  — zona NEUTRA, nada em jogo. A própria
--                                               API-Football só preenche a descrição quando a
--                                               posição carrega algum stake — não há seed novo
--                                               a escrever, o texto já É o sinal.
--   12.016 linhas com rank_description NÃO-NULO — cada uma cai em EXATAMENTE uma categoria do
--                                               macro (cobertura 100%, garantida pelo ELSE
--                                               'classificacao' — nenhum rótulo passa em branco).
--
-- VERIFICAÇÃO MANUAL, por competição (as 11 com standings; sample = todo valor DISTINTO
-- observado, não uma amostra aleatória — o inventário inteiro é pequeno o bastante, ~100
-- combinações (league_id, rank_description), para conferir cada uma):
--
--   league_id  competição            categorias observadas                    conferido
--   1          Copa do Mundo         classificacao (grupo/oitavas), promocao  OK — grupo/
--                                     (playoff pro mata-mata)                 mata-mata não tem
--                                                                             nome de competição
--                                                                             continental no
--                                                                             texto, cai no
--                                                                             catch-all por
--                                                                             desenho
--   2          UCL (fase prévia)     vaga_continental, classificacao          OK
--   11         Sudamericana          vaga_continental, classificacao          OK — "Playoffs"
--                                                                             genérico ao lado
--                                                                             do rótulo
--                                                                             específico na
--                                                                             MESMA faixa de
--                                                                             rank (mesma zona,
--                                                                             rótulo duplicado
--                                                                             pela API)
--   13         Libertadores          vaga_continental, classificacao          OK
--   39         Premier League        rebaixamento, vaga_continental           OK — sem faixa
--                                                                             "promocao" (liga
--                                                                             sem 2ª divisão
--                                                                             conectada aqui)
--   61         Ligue 1               rebaixamento, vaga_continental,          OK
--                                     classificacao
--   71         Brasileirão           rebaixamento, vaga_continental,          OK
--                                     classificacao
--   72         Série B               promocao, rebaixamento                  OK — única com
--                                                                             "promocao" pura
--                                                                             (sobe pra Série A,
--                                                                             sem nome de
--                                                                             competição
--                                                                             continental)
--   78         Bundesliga            rebaixamento, vaga_continental           OK
--   94         Primeira Liga         rebaixamento, vaga_continental           OK
--   135        Serie A ITA           rebaixamento, vaga_continental,          OK
--                                     classificacao
--   140        La Liga               rebaixamento, vaga_continental,          OK
--                                     classificacao
--
-- Nenhuma linha caiu em categoria errada por leitura equivocada do texto (ex.: "Relegation -
-- Serie B" no Brasileirão é rebaixamento do PRÓPRIO Brasileirão pra Série B, não confundir com
-- "promocao" da Série B pra Série A — são competições e direções diferentes, e o texto de
-- origem (league_id) já separa as duas).

SELECT
    league_id,
    rank_description,
    {{ futebol_zona_tabela('rank_description') }} AS categoria,
    COUNT(*)   AS linhas,
    MIN(rank)  AS rank_min,
    MAX(rank)  AS rank_max
FROM {{ ref('fact_standings_snapshot') }}
WHERE rank_description IS NOT NULL
GROUP BY league_id, rank_description
ORDER BY league_id, categoria, rank_min
