{#
    FAMÍLIA DA COMPETIÇÃO — `ano_calendario` ou `split_year` —, DERIVADA do calendário e não
    digitada numa lista.

    Para que serve. A spec #49 (user story 12, e o critério de aceite da #53) pede o efeito da
    medição quebrado por família, porque as duas se comportam de maneira diferente sob o eixo de
    escopo NA JANELA MEDIDA: numa competição de ano-calendário o rótulo de `season` é o mesmo o
    ano inteiro, então juntar competições junta de fato; numa split-year a virada do rótulo cai
    dentro da janela congelada (16/06 a 04/08), e o histórico doméstico do time fica sob a
    temporada ANTERIOR — o filtro `l.season = a.season`, que o eixo de escopo não toca, corta o
    que o escopo juntou. É por isso que só a célula `ambos` alcança esse caso.

    ⚠️ Isto é específico da virada de temporada, não verdade geral: em janeiro um time de
    Bundesliga tem o campeonato nacional e a Champions sob o MESMO rótulo, e `escopo` junta os
    dois normalmente.

    POR QUE DERIVADA, E NÃO UMA LISTA DE SLUGS. Uma lista digitada envelhece: a Onda 2 acrescentou
    cinco ligas em três semanas e nada obrigaria a lista a andar junto — e o erro seria mudo, com
    a liga nova caindo na família errada e o número saindo com cara de certo. O critério é
    observável no próprio calendário: uma competição é split-year quando a MESMA `season`
    atravessa a virada do ano civil.

    ⚠️ A CLASSIFICAÇÃO LÊ TODO O `fact_fixtures`, JAMAIS A JANELA CONGELADA. Dentro dela a
    Champions só tem as qualificatórias de julho e agosto de 2026 e sairia classificada como
    ano-calendário — exatamente o contrário do que ela é. O sinal vem das temporadas inteiras,
    incluídas as backfilladas de 24/25 e os jogos FUTUROS já agendados. E basta UMA temporada
    atravessar para a competição ser split-year (`LOGICAL_OR`, não maioria): uma temporada
    truncada por ainda estar em curso não tem como rebaixar a classificação de uma competição
    cujo histórico já mostrou a virada.

    A evidência sai junto do rótulo — `temporadas_observadas`, `temporadas_atravessando` e as duas
    pontas do calendário — para que quem lê a tabela publicada possa conferir a classificação em
    vez de acreditar nela.

    ⚠️ O GRÃO É O SLUG (`competition`), NÃO O `competition_id`, e isso é deliberado. Quem consome
    a classificação junta pelo que tem na mão, e o `apostas` do task01_base() carrega só o slug —
    é ele, portanto, que precisa ser único aqui. O slug sai de um CASE sobre o league_id no
    `fact_fixtures`, então nada impede que dois IDs passem a cair no mesmo slug (uma fase
    classificatória cadastrada à parte, por exemplo); com o grão em (id, slug), esse dia
    duplicaria as linhas do consumidor em silêncio. Medido hoje: 13 competições, 1 para 1.
    `n_competition_ids` sai junto para que a hipótese continue conferível em vez de suposta.

    Emite DUAS CTEs no escopo do chamador — `fam_por_temporada` (o insumo) e `familia_competicao`
    (o resultado, uma linha por competição). Uma CTE do chamador com qualquer um dos dois nomes as
    sombreia em silêncio.

    Uso:

        WITH {{ taskf_familia_competicao() }}
        SELECT familia, COUNT(*) FROM ... JOIN familia_competicao USING (competition_id) ...
#}

{% macro taskf_familia_competicao() %}

fam_por_temporada AS (
    SELECT
        competition_id,
        competition,
        season,
        COUNT(*)          AS n_fixtures,
        MIN(kickoff_utc)  AS primeiro_kickoff,
        MAX(kickoff_utc)  AS ultimo_kickoff,
        EXTRACT(YEAR FROM MAX(kickoff_utc)) > EXTRACT(YEAR FROM MIN(kickoff_utc))
                          AS atravessa_a_virada
    FROM {{ ref('fact_fixtures') }}
    GROUP BY competition_id, competition, season
),

familia_competicao AS (
    SELECT
        competition,
        MIN(competition_id)               AS competition_id,
        COUNT(DISTINCT competition_id)    AS n_competition_ids,
        IF(LOGICAL_OR(atravessa_a_virada), 'split_year', 'ano_calendario') AS familia,
        COUNT(DISTINCT season)      AS temporadas_observadas,
        COUNT(DISTINCT IF(atravessa_a_virada, season, NULL)) AS temporadas_atravessando,
        SUM(n_fixtures)             AS fixtures_observados,
        MIN(primeiro_kickoff)       AS primeiro_kickoff,
        MAX(ultimo_kickoff)         AS ultimo_kickoff
    FROM fam_por_temporada
    GROUP BY competition
)

{% endmacro %}
