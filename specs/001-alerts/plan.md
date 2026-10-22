# Implementation plan: a list of past INMET alerts, each checked by marola

**Branch**: `claude/10-alerts-speckit` | **Date**: 2026-10-05 | **Spec**: [spec.md](spec.md)
**MIP**: [MIP-0034 §5.2a](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0034-rss-feeds-and-content-syndication.md) | **Builds on**: [marola-oods spec 001](https://github.com/marola-dev/marola-oods/pull/3) (the DuckLake on Cloudflare R2)

## Summary

Three repos, one data path. marola-app's `oods` module ingests INMET's CAP alerts per state into
two new DuckLake tables, checks each expired alert against Open-Meteo, and exports one JSON per
state. marola-oods runs it every 3 hours (`alerts-etl.yml`, in the shared `oods-lake` group).
marola-site copies the export into `site/dist/alerts/` at build time and renders it on a new
`alerts.html`. The simple first version is RJ only, with every INMET event, Portuguese alert text,
and the whole history INMET still serves.

## Technical context

| | |
|---|---|
| **App** | Scala 3 / Kyo in marola-app's `oods` module, beside spec 001's code; JDK XML parsing for CAP; marola-app's `Http` and Open-Meteo client |
| **Store** | spec 001's DuckLake (`duckdb_jdbc`, `ducklake`, `httpfs`), two new tables |
| **Site** | plain JS, a new `alerts.html` + `alerts.js`, `style.css`, `site/i18n/` keys; no new origin, CSP unchanged |
| **Workflows** | marola-oods `alerts-etl.yml`; marola-site `site.yml` gains one copy step |
| **Credentials** | spec 001's ETL key (marola-oods); a new read-only key for marola-site (a person creates it) |
| **Testing** | munit with captured CAP/RSS/Open-Meteo answers and a local lake; `site_check.js` assertions on `alerts.html` with a fixture export |
| **Scale** | RJ: a few alerts a day, ~1–2k a year, ~4 years of backfill |

## Constitution check

marola-site's [constitution](../../.specify/memory/constitution.md), and spec 001's for the app
and oods parts.

| Gate | Status | What clears it |
|---|---|---|
| I.1 Cost | ✓ | INMET and Open-Meteo are free and keyless; the alerts add a few MB and a few thousand operations a month to R2, far inside its free tier; use above it is billed to the maintainer's account, so spec 001's size checks cover these tables too |
| I.2 No secrets | ✓ | keys are Actions secrets; the site's key is read-only and never reaches the page |
| I.3 agent-ready | ✗ | #10 has no `agent-ready`; the maintainer adds it once this spec is accepted |
| I.5 Phase | ✗ | the store is spec 001's Phase 2 exception (MIP-0075 §11); this spec needs nothing beyond it |
| II The page | ✓ | the page reads `alerts/<uf>.json` from its own origin |
| III Boundaries | ✓ | code in marola-app, schedule in marola-oods, page in marola-site; the export crosses as a bucket object |
| III Failed fetch | ✓ | a missing export leaves the page with the last one, or an empty-state line |
| IV Data honesty | ✓ | INMET's text verbatim with its link; the verdict labelled as marola's, with its evidence and its limit (R3) |

## Project structure

```text
specs/001-alerts/                 this spec (marola-site)
  spec.md  plan.md  research.md  data-model.md  quickstart.md  tasks.md
  contracts/cli.md  contracts/workflow.md  contracts/alerts-export.schema.json

marola-app/oods/src/
  main/scala/marola/oods/alerts/
    InmetCap.scala          pure: CAP XML → Alert (one per state it covers)
    InmetClient.scala       RSS ids, CAP by id, avisos/ativos best-effort; browser-like UA
    Thresholds.scala        pure: description → forecast bounds (research R3)
    AlertCheck.scala        pure: bounds + observed series → Verdict
    AlertLoad.scala         plan → fetch → upsert per state; backfill by id blocks
    AlertCheckLoad.scala    due alerts → Open-Meteo → alert_check
  main/resources/ibge/municipios.csv   code, name, uf, lat, lon (IBGE)
  main/resources/sql/views.sql         + alert views
  test/…/alerts/*Spec.scala            captured answers → exact rows and verdicts

marola-oods/
  .github/workflows/alerts-etl.yml
  etl/alert-states.json                ["RJ"]

marola-site/
  site/static/alerts.html, alerts.js   the page
  site/alert-states.json               ["RJ"]
  site/fixtures/alerts/rj.json         the page's fixture (2026-09-29 shape)
  site/i18n/{pt-BR,en,context}.json    alerts.* keys; nav.alerts becomes a link
  .github/workflows/site.yml           copy step + allowlist
  scripts/site_check.js                alerts.html assertions
```

## Phases

0. **Gates (people)**: `agent-ready` on #10; spec 001's store exists (its phases 0–1); a read-only
   R2 token for marola-site; Q8's reading confirmed.
1. **Page on a fixture (marola-site)**: `alerts.html` renders `site/fixtures/alerts/rj.json`; nav
   link; i18n; `site_check.js`. Ships alone: with no export the page says alerts are not loaded
   yet. This is the first PR and needs nothing from the other repos.
2. **Ingest (marola-app + marola-oods)**: CAP parser, client, `alert` table, `oods alerts --uf
   RJ`, export, `alerts-etl.yml` live-only.
3. **Check**: thresholds parser, Open-Meteo series, `alert_check`, `oods alerts-check`.
4. **Wire the site**: `site.yml` copy step with the read-only key; the page reads the real export.
5. **Backfill**: `--backfill` over RJ's history, checked against the archive endpoint.
6. **More states**: a value in `etl/alert-states.json` and `site/alert-states.json`.

## Complexity tracking

| Choice | Why | Simpler alternative rejected because |
|---|---|---|
| The DuckLake instead of JSON on `site-data` | the maintainer's pick (Q7): one store for marola's open data, partitioned by state | — |
| One row per (alert, state) | partition by state (Q4) and a check per state's places | one row with a state list cannot be partitioned by state |
| CAP by id for live and past alerts | one parser for both paths | RSS for live + something else for history is two parsers |
| A verdict table with `rule_version` | the rule will change; old verdicts stay explainable | overwriting verdicts loses why the page said what it said |
