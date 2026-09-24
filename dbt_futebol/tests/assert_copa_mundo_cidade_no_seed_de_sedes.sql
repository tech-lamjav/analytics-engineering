{#-
    TODO JOGO DE COPA DO MUNDO TEM A CIDADE NO SEED DE SEDES (AE#200).

    Sob `pit_mando: neutro_copa` o int_futebol_team_form_pit decide casa/fora/neutro de cada jogo
    de Copa pelo join `venue_city` → `futebol_copa_mundo_sedes`. Cidade fora do seed não dá erro:
    o LEFT JOIN devolve anfitrião NULL e o jogo vira campo neutro CALADO — inclusive o de um
    anfitrião em casa, que é exatamente o caso que o eixo existe para acertar. A API grava a mesma
    sede com grafias diferentes (21 para 16 sedes em 24/09/2026), então uma grafia nova é o modo
    de falha provável, e não o exótico. Cidade NULL cai no mesmo buraco e também reprova.

    Falha = uma linha por jogo de Copa cuja cidade o seed não conhece.

    ⚠️ SEM a tag `guarda`, de propósito. A fase de guardas do workflow_futebol_odds roda
    `tag:guarda` contra o dataset de produção, onde o seed não existe enquanto `neutro_copa` for
    só medição — a guarda sairia vermelha por erro de relação, e não por dado. Ela roda junto com
    a medição (ver analyses/ae200_campo_neutro.sql). Quem virar o default da AE#200 promove esta
    guarda a `tag:guarda` no mesmo commit, e carrega o seed em produção antes.
-#}

SELECT
    f.fixture_id,
    f.kickoff_utc,
    f.home_team_id,
    f.away_team_id,
    f.venue_city
FROM {{ ref('fact_fixtures') }} f
LEFT JOIN {{ ref('futebol_copa_mundo_sedes') }} sd
    ON sd.venue_city = f.venue_city
WHERE f.competition = 'copa_mundo'
  AND sd.venue_city IS NULL
