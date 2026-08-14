# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Isolamento por worktree

**Trabalho de mais de um passo neste repositório roda em git worktree.** Chame `EnterWorktree`
no início da sessão, antes de editar qualquer arquivo.

Motivo: em 2026-08-05 duas sessões escreveram `int_futebol_odds_devig.sql` ao mesmo tempo. A
segunda sobrescreveu a primeira, e só foi percebido porque um `dbt test` pegou o arquivo no
meio da escrita e devolveu um erro de sintaxe inexplicável. `git status` de uma sessão não
distingue o que ela escreveu do que outra escreveu — worktree separa as duas árvores e o
problema deixa de existir.

Não vale a pena para pergunta de uma resposta só (ler um modelo, rodar uma query).

**Setup da árvore nova.** `.venv/`, `target/` e `dbt_packages/` são gitignored, então o
worktree nasce sem os três — e o `../.venv/bin/dbt` que este arquivo usa mais abaixo não
resolve lá dentro. O `profiles.yml` é versionado e vem junto.

```bash
ln -s /caminho/do/repo/original/.venv .venv
cd dbt_futebol && DBT_PROFILES_DIR=.. ../.venv/bin/dbt deps
```

**⚠️ Worktree isola o disco, não o BigQuery.** Os targets `dev` e `prod` do `profiles.yml`
apontam para o **mesmo** dataset (`futebol`, `nba`) — não há dataset por pessoa. Duas sessões
em worktrees diferentes rodando `dbt run` materializam na mesma tabela: a segunda ganha e a
primeira não recebe sinal nenhum. Conflito de arquivo é barulhento e o worktree o elimina;
clobber de tabela é **mudo** e o worktree não encosta nele. **Só uma sessão roda `dbt run` por
vez**, com ou sem worktree.

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

### ⚠️ Deploy dos modelos: mergear NÃO é deployar

Os modelos rodam de uma **imagem Docker pré-buildada**, não do master. Depois de todo merge
que toca as paths comportamentais de um projeto dbt:

```bash
./build-and-push.sh dbt_futebol   # ou dbt_nba
```

Esse comando agora faz build + push + `gcloud run jobs update` (digest **e** carimbo de
procedência) num passo só. Não existe mais um segundo comando manual — foi o segundo passo
esquecido que deixou o fix do de-vig 2 dias fora de produção e o `dbt_nba` 6 semanas atrás
do master.

**A fase de guardas dbt não pega isso**: ela roda da mesma imagem, então imagem velha causa o
bug e apaga o detector. Quem pega é `.github/workflows/deriva-imagem.yml`, de hora em hora,
de fora da imagem. Para conferir na hora:

```bash
./scripts/checa_deriva.sh
```

Ver `docs/adr/0001-carimbo-de-procedencia-da-imagem-dbt.md`.

## Agent skills

### Issue tracker

Issues live in GitHub (`tech-lamjav/analytics-engineering`), managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`) plus the `wayfinder:*` set exist in the GitHub repo. See `docs/agents/triage-labels.md`.

### Domain docs

Multi-context layout: root `CONTEXT-MAP.md` plus per-project `CONTEXT.md`/`docs/adr/` under `dbt_nba/` and `dbt_futebol/` (they're independent domains). See `docs/agents/domain.md`.

### Skill adaptations (dbt repo)

No TS/npm toolchain here — translate skill assumptions as follows:

- "Typecheck" → `dbt parse` (fast static check) or `dbt compile --select <model>`.
- "Run the tests" → `dbt test` (schema + singular tests). For TDD red-green, write a dbt unit test (YAML `unit_tests:` block) or a `tests/assert_*.sql` that fails first.
- dbt tests assert via SQL against the warehouse by design — that is the test interface here, not a "bypasses the interface" anti-pattern.
- "Prototype" → `dbt show --inline "..."`, a scratch BigQuery query, or a throwaway Python script. UI prototyping is N/A.
- Coding standards for review live in `CODING_STANDARDS.md` at the repo root.

### User-invoked skills (recommend when relevant)

The mattpocock-skills plugin also ships slash commands Claude cannot invoke itself (user-invoked only, so they don't appear in the model's skill list). **Always recommend the fitting one when the moment calls for it** — e.g. suggest `/grill-with-docs` when the user is weighing a decision worth persisting, `/wayfinder` when an effort is big and fuzzy, `/to-tickets` once a spec is settled:

- `/triage` — triage open GitHub issues using `docs/agents/triage-labels.md`
- `/to-spec` — turn a discussed idea into a spec published as a GitHub issue
- `/to-tickets` — break a spec into dependency-ordered tickets
- `/wayfinder` — map + tickets for a large or uncertain effort
- `/implement` — execute a `ready-for-agent` ticket end to end
- `/grill-with-docs` — grilling session that persists decisions to `CONTEXT.md`/ADRs
- `/improve-codebase-architecture` — architecture review (reads CONTEXT/ADRs, HTML report)
- `/ask-matt` — router that picks the right skill for the situation
- `/grill-me`, `/handoff`, `/teach`, `/writing-great-skills` — productivity extras
- `/setup-matt-pocock-skills` — already run here; re-run only to switch issue tracker
