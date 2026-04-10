# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dbt (data build tool) project for NBA sports betting analytics. It ingests raw NBA data from Google Cloud Storage (sourced from the Balldontlie API and DraftKings), transforms it through BigQuery, and produces mart tables used for prop betting analysis.

## Commands

All dbt commands must be run from the `dbt_nba/` directory. The `profiles.yml` is at the repo root, so set `DBT_PROFILES_DIR` accordingly (it defaults to the repo root when running locally, since `profiles.yml` is there).

```bash
cd dbt_nba

# Install packages
dbt deps

# Run all models
dbt run

# Run a single model
dbt run --select dim_daily_opportunities

# Run a model and all its upstream dependencies
dbt run --select +dim_daily_opportunities

# Run tests
dbt test

# Run tests for a specific model
dbt test --select dim_stat_player

# Compile (check SQL without running)
dbt compile --select dim_daily_opportunities

# Generate docs
dbt docs generate --static

# Serve docs locally
dbt docs serve
```

The BigQuery target is `smartbetting-dados`, dataset `nba`, region `us-east1`. Local dev uses OAuth (`method: oauth`). CI uses a service account key (`BIGQUERY_SA_KEY` secret).

## Architecture

### Data Flow

```
GCS (NDJSON) → BigQuery External Tables → staging → intermediate → marts
```

Raw data sits in `gs://smartbetting-landingzone/nba/` as external tables declared in `models/staging/sources.yml`. No ingestion pipeline lives in this repo.

### Layer conventions

- **staging/** (`+materialized: view`): Flatten raw JSON structs, cast types, rename fields. One model per source table. Prefix: `stg_`.
- **intermediate/** (`+materialized: view`): Complex transformations — unpivoting (called "pilling" in this codebase), COM/SEM aggregations, game/team-level calculations. Prefix: `int_`.
- **marts/** (`+materialized: table`): Final tables consumed by BI/apps. Prefix `dim_` for dimension tables, `ft_` for fact tables.

### Key Domain Concepts

**COM/SEM analysis**: The core analytical pattern. "COM" = games where a trigger player *played*. "SEM" = games where the trigger player *did not play*. The pipeline identifies injured players ("triggers"), then measures how their teammates' stats change when the trigger is absent. This drives the betting opportunity scoring.

**Trigger player**: An injured/doubtful/questionable player whose absence may boost their teammates' stats and create betting value.

**Backup player**: A teammate with a positive SEM lift (higher stats when the trigger is out).

**Daily pipeline**: `int_daily_triggers` → `int_daily_360_analysis` → `dim_daily_opportunities`. This runs against `CURRENT_DATE()` and must be re-run daily before games start.

### Important Models

| Model | Purpose |
|---|---|
| `dim_players` | Master player table with injury status and team |
| `dim_teams` | Team standings, ratings (ORtg/DRtg), next opponent, injury report times in Brasília TZ |
| `dim_stat_player` | Player stat averages with z-score star ratings and backup performance when leader is injured |
| `ft_games` | All games with B2B flags and next-game flags |
| `ft_game_player_stats` | Historical player stats vs DraftKings betting lines (over/under outcomes) |
| `int_game_player_stats_pilled` | Long-format game stats (one row per player/game/stat_type) |
| `int_games_teams_pilled` | One row per team per game; computes B2B, last-5-games string |
| `int_daily_triggers` | Today's injured players with freshness/fatigue/participation filters |
| `int_daily_360_analysis` | COM vs SEM aggregates and line signal per trigger/backup pair |
| `dim_daily_opportunities` | Final scored opportunities (0–100) for today's slate |
| `dim_teammate_impact_360` | Full COM/SEM impact for all trigger/teammate pairs (no score filter, for Analise 360 UI) |

### Stat types

Stats follow the pattern `player_<stat>`: `player_points`, `player_rebounds`, `player_assists`, `player_threes`, `player_blocks`, `player_steals`, `player_turnovers`, `player_minutes`, `player_offensive_rebounds`, `player_defensive_rebounds`, `player_field_goal_percentage`, `player_free_throw_percentage`, and combo stats like `player_points_rebounds_assists`.

### Scoring logic (`dim_daily_opportunities`)

A weighted score (0–100) is computed from: gap vs line (30%), sample size (20%), trigger freshness (20%), opponent defensive rank (15%), ambient (10%), coefficient of variation (5%). Rows with score < 40 are excluded. Labels: ALTA CONFIANCA (≥80), MEDIA CONFIANCA (≥60), BAIXA CONFIANCA (≥40).

### Timezone notes

All game times are stored in UTC and converted to Brasília (UTC-3) for display. Injury report release times are 13:30 local team time converted to Brasília. DST adjustments are handled in `dim_teams`.

### Packages

- `dbt-labs/dbt_utils` v1.1.1 — used for `unique_combination_of_columns` tests and cross-database macros.

### CI/CD

GitHub Actions (`.github/workflows/deploy-dbt-docs.yml`) deploys static dbt docs to GitHub Pages on push to master when files under `dbt_nba/` change. Requires `BIGQUERY_SA_KEY` secret with a service account JSON.
