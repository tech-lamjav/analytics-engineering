# Coding Standards

Two independent dbt projects (`dbt_nba/`, `dbt_futebol/`) targeting BigQuery. There is
no application code here — these standards describe dbt/SQL work. Generic OO code-smell
heuristics (long parameter lists, feature envy, message chains, etc.) do not apply to
SQL models; review against the rules below instead.

## Layout and naming

- Three layers per project: `models/staging/`, `models/intermediate/`, `models/marts/`.
- Prefixes — dbt_nba: `stg_`, `int_`, `dim_` (dimensions), `ft_` (facts).
  dbt_futebol: `stg_futebol_`, `int_futebol_`, `dim_`, `fact_`.
- One model per file; model name equals file name.
- Singular tests live in `<project>/tests/` and are named `assert_<expectation>.sql`.
- Snapshots (dbt_futebol only) live in `<project>/snapshots/`.

## Materializations

- Project defaults (`dbt_project.yml`): staging = view, intermediate = view,
  marts = table.
- **dbt_nba: intermediates must stay views.** Never override an NBA `int_` model to
  table — the prod schema-drift sync depends on it.
- dbt_futebol: intermediates declare `materialized=` explicitly per model (the score
  engine uses a mix of tables and views); keep the explicit declaration when editing.
- dbt_futebol marts that are date-snapshotted or large declare `partition_by` /
  `cluster_by` in config; preserve them.

## Model SQL style

- Start every model with a `{{ config(...) }}` block containing at minimum a
  `description`. dbt_nba marts also carry
  `labels={'domain': 'bi', 'category': 'analytics'}` — keep that on new NBA marts.
- CTE pipeline shape: import CTE(s) first (`SELECT ... FROM {{ ref('...') }}` /
  `{{ source(...) }}`), then transformation CTEs, then a final `SELECT` (typically
  `SELECT * FROM <last_cte>`).
- Relations only via `ref()` / `source()` — never hardcoded table names. Sources are
  declared in `models/staging/sources.yml`; only staging models read sources.
- UPPERCASE SQL keywords, snake_case identifiers. Inline comments explain business
  rules (PT-BR in futebol, EN in NBA — match the project).
- Cast/rename at staging (`CAST`/`SAFE_CAST` with typed aliases); downstream layers
  should not re-cast raw fields.
- Timezones: store timestamps in UTC; Brasília (UTC-3) values are separate display
  columns (e.g. suffixed `_brasilia`).
- Futebol score engine: missing data must resolve to FALSE (`COALESCE(..., FALSE)`),
  never a NULL propagated into the Score ("degradação graciosa").

## Documentation and tests (mandatory on every model change)

- Every model has an entry in its layer's schema YAML (`models.yml` or
  `_<prefix>__models.yml`) with a description and column descriptions. **Any model
  change must update that entry and re-evaluate tests** — add or adjust
  `not_null` / `unique` / `accepted_values` / `relationships` /
  `dbt_utils.unique_combination_of_columns`, or a singular `assert_*.sql`, as needed.
- Long-form business context goes in the model's `config(description=...)`
  doc-string (futebol convention) — keep it in sync with behavior changes.
- `dbt-labs/dbt_utils` is the only package; do not add packages casually.

## Workflow

- Run dbt from inside the project directory (`dbt_nba/` or `dbt_futebol/`) with
  `DBT_PROFILES_DIR` pointing at the repo root (`profiles.yml` lives there).
- Validation bar for changes: `dbt parse` (static), then
  `dbt run --select <model>` + `dbt test --select <model>`; `dbt build` for the full
  graph when the change is cross-cutting.
- After executing a change plan, validate the result with real queries against
  BigQuery (e.g. via the Python venv), not just green dbt runs.
