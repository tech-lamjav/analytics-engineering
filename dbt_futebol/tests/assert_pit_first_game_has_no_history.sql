{{ config(tags=['guarda']) }}
{%- set eixos = taskf_eixos() %}
-- Guard de regressão da Task 0 (look-ahead).
-- No PRIMEIRO jogo de um time numa (competição, temporada) não existe passado: played_total tem
-- de ser 0 e rank/médias têm de ser NULL. Era exatamente aqui que o modelo antigo entregava a
-- temporada FECHADA (played_total=38, tabela final) a um jogo da rodada 1.
-- Falha = alguma fonte voltou a ser lida sem âncora no kickoff.
{#-
    ⚠️ "PRIMEIRO JOGO" É RELATIVO À CÉLULA (task [F], issue #49, ADR 0007), e a partição abaixo
    segue os dois eixos porque o join do modelo segue. Em produção nada muda: no default a
    partição é (team_id, competition_id, season) e o SQL compilado é IDÊNTICO ao de antes.

    Por que não deixar o guard falhar fora do default e mandar excluí-lo. Sob `pit_escopo: todas`
    ele acusa 224 linhas — e elas são o mecanismo da medição FUNCIONANDO: o primeiro jogo de Copa
    do Brasil de um time passa a carregar até 17 partidas de Brasileirão, o de Sudamericana até
    25. É a hipótese da spec virando número. Mas guard vermelho por desenho é guard que se exclui
    da linha de comando, e aí a célula inteira roda SEM guarda de look-ahead — justamente o defeito
    (Task 0) que contaminou a medição que esta task existe para refazer. Com a partição seguindo a
    célula, a invariante continua sendo asserida nas quatro, e a única exclusão que a medição
    precisa é a Costura A, que é default-only por definição.

    Verificado nas quatro células: 0 violações.
#}

WITH primeiro_jogo AS (
    SELECT
        fixture_id,
        team_id,
        competition,
        season,
        kickoff_utc,
        played_total,
        {%- if eixos.recorte == 'ultimos_10' %}
        {#- A contagem DISPONÍVEL (#54) só existe sob recorte de contagem, e entra na guarda pelo
            mesmo motivo que a usada: ela sai de uma window function calculada ANTES do QUALIFY, e
            uma partição errada ali contaria partida posterior ao kickoff sem que o played_total
            (que passa pelo mesmo join) precisasse mudar. -#}
        played_total_disponivel,
        {%- endif %}
        rank,
        goals_for_avg_home
    FROM {{ ref('int_futebol_team_form_pit') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY team_id{% if eixos.escopo == 'da_competicao' %}, competition_id{% endif %}{% if eixos.recorte == 'temporada' %}, season{% endif %}
        ORDER BY kickoff_utc
    ) = 1
)

SELECT *
FROM primeiro_jogo
WHERE played_total != 0
   {%- if eixos.recorte == 'ultimos_10' %}
   OR played_total_disponivel != 0
   {%- endif %}
   OR rank IS NOT NULL
   OR goals_for_avg_home IS NOT NULL
