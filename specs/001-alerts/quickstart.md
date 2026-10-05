# Quickstart: checking the alerts feature

## A. Without the bucket (any machine)

```bash
# in a marola-app checkout
sbt "oods/testOnly marola.oods.alerts.*"      # captured INMET CAP + Open-Meteo answers, a local lake
```

```bash
just quality
node scripts/site_check.js                     # alerts.html against specs/001-alerts fixture
just site-serve                                # http://localhost:8000/alerts.html with site/fixtures/alerts/rj.json
```

## B. The first real run (the maintainer's machine or CI; this sandbox cannot reach INMET or B2)

1. `curl -A 'Mozilla/5.0 marola.dev' https://apiprevmet3.inmet.gov.br/avisos/rss | head` answers.
2. Fetch one CAP by id and check for `<geocode>` with IBGE codes (research R1's "to verify").
3. Dispatch `alerts-etl.yml` with `backfill: true, max_minutes: 30` in marola-oods; `fetch_run`
   shows `partial` or `ok`.
4. `exports/alerts/rj.json` contains the 2026-09-29 alerts (R2), each with a verdict.
5. A second dispatch with nothing new creates no DuckLake snapshot (SC-004).
