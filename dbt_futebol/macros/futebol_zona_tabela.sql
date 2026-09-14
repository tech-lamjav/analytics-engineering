{#- AE#160 (spec #157) — mapeia `fact_standings_snapshot.rank_description` para a zona de
    tabela em disputa: título/vaga continental, promoção doméstica, playoff/classificação
    genérica, ou rebaixamento. É o insumo da premissa "Decisão" do catálogo de handicap de
    escanteios (mata-mata OU reta final de liga com posição em jogo, AE#162).

    NÃO cria seed novo por campeonato — deriva só do TEXTO que a API-Football já traz em
    produção. Inventariado em 14/09/2026 sobre as 11 competições com standings
    (`fact_standings_snapshot`, 22.070 linhas): 10.054 com rank_description NULL (time em zona
    NEUTRA, sem nada em jogo — a própria API só preenche a descrição quando a posição carrega
    stake) e 12.016 com algum texto. O piso é então "sem seed": rank_description NÃO-NULO já É
    o sinal de disputa; este macro só refina QUE TIPO de disputa, para diagnóstico e para a
    régua de aceite poder citar a origem de cada corte.

    QUATRO categorias, checadas NESTA ORDEM (relegation e continental têm prioridade sobre o
    prefixo genérico "Promotion" — "Promotion - Champions League (...)" é vaga_continental, não
    promocao):

    1. rebaixamento        — contém "Relegation" (com ou sem sufixo de liga/grupo).
    2. vaga_continental     — contém o nome de uma competição continental (Champions/Europa/
                              Conference League, Libertadores, Sudamericana, ou "UEFA"/"ECL"),
                              INDEPENDENTE de vir prefixado por "Promotion -".
    3. promocao             — contém "Promotion" mas SEM nome de competição continental (ex.:
                              "Promotion", "Promotion - Serie A Betano", "Promotion Play-offs"
                              da Série B/C — subir de divisão doméstica).
    4. classificacao        — QUALQUER OUTRO texto não-nulo (ex.: "Playoffs", "Play Offs",
                              "Qualifying", "Round of 32", "Possible Advanced" — labels
                              genéricos de avanço de fase em copas/grupos, sem nome de
                              competição anexado no texto). Catch-all deliberado: garante que
                              todo rank_description não-nulo caia em alguma categoria (nunca
                              NULL quando a API sinalizou stake), robusto a variação futura de
                              rótulo sem exigir manutenção deste macro.

    `rank_description IS NULL` -> categoria NULL -> sem disputa (zona neutra).

    Ver inventário completo (por league_id) no PR da AE#160; verificação manual amostrada
    contra os valores reais de cada competição documentada lá. -#}
{% macro futebol_zona_tabela(coluna) -%}
    CASE
        WHEN {{ coluna }} IS NULL THEN NULL
        WHEN {{ coluna }} LIKE '%Relegation%' THEN 'rebaixamento'
        WHEN {{ coluna }} LIKE '%Champions League%'
          OR {{ coluna }} LIKE '%Europa League%'
          OR {{ coluna }} LIKE '%Conference League%'
          OR {{ coluna }} LIKE '%Libertadores%'
          OR {{ coluna }} LIKE '%Sudamericana%'
          OR {{ coluna }} LIKE '%UEFA%'
          OR {{ coluna }} LIKE '%ECL%'
        THEN 'vaga_continental'
        WHEN {{ coluna }} LIKE '%Promotion%' THEN 'promocao'
        ELSE 'classificacao'
    END
{%- endmacro %}


{#- Booleano de conveniência p/ a premissa "Decisão": qualquer categoria = posição em jogo. -#}
{% macro futebol_zona_tabela_em_disputa(coluna) -%}
    ({{ futebol_zona_tabela(coluna) }} IS NOT NULL)
{%- endmacro %}
