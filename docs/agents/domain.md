# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This repo is **multi-context**: `dbt_nba/` and `dbt_futebol/` are two independent dbt projects (separate `dbt_project.yml`, separate BigQuery datasets, separate domain vocabulary — NBA player-prop betting vs. football/soccer analytics). Treat each as its own context.

## Before exploring, read these

- **`CONTEXT-MAP.md`** at the repo root — points at one `CONTEXT.md` per context. Read the one relevant to the topic (`dbt_nba/CONTEXT.md` or `dbt_futebol/CONTEXT.md`).
- **`docs/adr/`** at the repo root — system-wide decisions (e.g. shared infra, deploy pipeline, repo-wide conventions).
- **`dbt_nba/docs/adr/`** or **`dbt_futebol/docs/adr/`** — context-scoped decisions for whichever project you're touching.

If any of these files don't exist yet, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions (deploy, shared infra)
├── dbt_nba/
│   ├── CONTEXT.md                     ← NBA prop-betting domain vocabulary
│   └── docs/adr/                      ← NBA-specific decisions
└── dbt_futebol/
    ├── CONTEXT.md                     ← futebol/soccer analytics domain vocabulary
    └── docs/adr/                      ← futebol-specific decisions
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the relevant `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids. Note that NBA and futebol contexts may define similar-sounding terms differently — don't assume a term from one context carries over to the other.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0002 (NBA intermediates stay views for the prod sync) — but worth reopening because…_
