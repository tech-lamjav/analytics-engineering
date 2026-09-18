{#-
  RESOLUÇÃO DE team_id TROCADO PELA API-FOOTBALL (AE#189).

  A API-Football troca o team_id de um clube por alguns dias sem aviso (ver
  seeds/_team_id_aliases.yml para o catálogo de trocas observadas). Este macro aplica
  o crosswalk na camada de staging, antes de qualquer join por team_id nos facts de
  jogo — assim `team_id = home_team_id`/`away_team_id` (e qualquer outro join por
  team_id) continua batendo mesmo durante a janela da troca.

  Subquery correlacionada em vez de JOIN: o seed tem poucas linhas (trocas são raras e
  catalogadas manualmente, uma por PR) e cada stg model já tem sua própria forma de FROM
  — um macro que precisasse de um JOIN explícito obrigaria reescrever o FROM de todo
  model que o usa. `COALESCE` cai pro id original quando não há alias (o caso comum).

  ⚠️ NÃO usar em stg_futebol_teams (dim_teams): lá 22722 precisa continuar existindo como
  o time real "Chapecoense B" que é — o crosswalk é só para os facts de jogo, onde um
  team_id fora do (home, away) do fixture é sinal de troca, não de time extra.
-#}
{% macro futebol_team_id_canonico(team_id_col) -%}
    COALESCE(
        (
            SELECT alias.team_id_canonico
            FROM {{ ref('team_id_aliases') }} AS alias
            WHERE alias.team_id_observado = {{ team_id_col }}
        ),
        {{ team_id_col }}
    )
{%- endmacro %}
