# Context Map

## Contexts

- [NBA Player Props](./dbt_nba/CONTEXT.md) — NBA player-prop betting analytics: COM/SEM
  impact analysis of injured players and daily scored opportunities
- [Futebol Value Betting](./dbt_futebol/CONTEXT.md) — football (soccer) pre-match value
  betting: a deterministic score engine (Motor de Score) over odds and match data

## Relationships

- **NBA ↔ Futebol: independent.** Two separate dbt projects with separate BigQuery
  datasets (`nba`, `futebol`) and no cross-project refs. They share only repo-level
  infra (root `profiles.yml`, Python venv, Docker build scripts).
- **Pattern precedent, not dependency**: the futebol score engine deliberately mirrors
  the NBA daily-opportunities architecture (weighted 0–100 score → confidence bands →
  eliminatory gate), but weights, thresholds and vocabulary are context-local.
- **Term collisions**: both contexts define `dim_players`/`dim_teams` models and a
  0–100 "score" with confidence bands — same words, different meanings and thresholds
  (NBA: 80/60/40; futebol: 60/40). Never carry a definition across contexts.
