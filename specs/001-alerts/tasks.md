# Tasks: alerts

Ordered; `[P]` can run beside the previous task. Every task is one PR in the repo named. None
starts before `agent-ready` on marola-dev/marola-site#10 (phase 0).

## Phase 0 — gates (people)

- [ ] 001-T001 Confirm Q8's reading (backfill before September 2026)
- [ ] 001-T002 Add `agent-ready` to #10
- [ ] 001-T003 Create the read-only R2 token `marola-site-read` (Object Read, this bucket); set `CLOUDFLARE_R2_READ_ACCESS_KEY_ID` and `CLOUDFLARE_R2_READ_SECRET_ACCESS_KEY` (secrets) and `CLOUDFLARE_R2_ACCOUNT_ID` (variable) in marola-site
- [ ] 001-T004 Spec 001's store exists in the bucket (marola-oods spec 001, phases 0–1)

## Phase 1 — the page on a fixture (marola-site) 🎯 MVP

- [ ] 001-T010 `site/fixtures/alerts/rj.json`: two 2026-09-29 alerts (one `confirmed`, one pending) and one `not_checkable`, valid against `contracts/alerts-export.schema.json`
- [ ] 001-T011 `site_check.js`: failing assertions first (nav link on every page, one card per alert with event, severity, window, municipalities, verbatim `lang="pt-BR"` text, `https://` link, verdict label; no non-self fetch)
- [ ] 001-T012 `alerts.html` + `alerts.js` + styles, through the `site-frontend` skill; screenshots at 390 and 1280 px
- [ ] 001-T013 `site/i18n` keys (`alerts.*`), `nav.alerts` becomes a link, `nav.soon` dropped from it
- [ ] 001-T014 `site.yml` allowlist: `alerts.html`, `alerts.js`, `alerts/`; README and `docs/1-design.md` updated

## Phase 2 — ingest (marola-app, then marola-oods)

- [ ] 001-T020 `InmetCap` parser from captured CAP files, incl. `Update`/`Cancel`, multi-state, no-polygon
- [ ] 001-T021 `municipios.csv` resource and `Uf` lookup by IBGE code
- [ ] 001-T022 `InmetClient` with the UA, throttle, and a hand-written transport double
- [ ] 001-T023 `alert` table, upsert per state, no snapshot on a no-op (local lake)
- [ ] 001-T024 `oods alerts --uf`, `oods export --alerts`, CLI failures
- [ ] 001-T025 marola-oods: `etl/alert-states.json`, `alerts-etl.yml` (live only), image bump

## Phase 3 — the check (marola-app)

- [ ] 001-T030 `Thresholds` parser over every captured description template
- [ ] 001-T031 `AlertCheck` verdict rule (research R3), exact-value tests per quantity
- [ ] 001-T032 Open-Meteo series for N points, forecast vs archive by age; `alert_check`; `oods alerts-check`

## Phase 4 — wire the site (marola-site)

- [ ] 001-T040 `site.yml` copy step and `site/alert-states.json`; a failed copy still deploys

## Phase 5 — backfill

- [ ] 001-T050 `--backfill` by id blocks with `fetch_partition`, stop rule, `--max-minutes`
- [ ] 001-T051 First dispatch (a person); 2026-09-29's alerts on the live page

## Phase 6 — more states

- [ ] 001-T060 Each new state: one PR per repo adding it to both `alert-states.json`
