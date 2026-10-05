# Contract: the workflows

## `alerts-etl.yml` (marola-oods)

Spec 001's writing-job steps (catalog download, run, maintain, catalog upload, export), its
`OODS_*` mapping, `permissions` and the shared concurrency group, unchanged:

```yaml
on:
  schedule:
    - cron: "50 2-23/3 * * *"  # 25 min before each of site.yml's builds (15 */3)
  workflow_dispatch:
    inputs:
      backfill: { type: boolean, default: false }
      max_minutes: { type: number, default: 300 }
concurrency:
  group: oods-lake
  cancel-in-progress: false
```

The run step:

```bash
uf=$(jq -r 'join(",")' etl/alert-states.json)     # ["RJ"] at first
oods alerts --uf "$uf" ${BACKFILL:+--backfill --max-minutes "$MAX_MINUTES"}
oods alerts-check --uf "$uf"
oods export --alerts "$uf"
```

`etl/alert-states.json` (marola-oods) is the only place a state is added (US4). The backfill is a
human's `workflow_dispatch`, never scheduled.

## `site.yml` (marola-site)

One step after "Add the smoke-test, coverage and stats data", with a **read-only** B2 key scoped
to `exports/` (secret `BACKBLAZE_SITE_APP_KEY`, variable `BACKBLAZE_SITE_KEY_ID`; a person creates
both):

```yaml
      - name: Add the alerts export (B2, if reachable)
        env:
          AWS_ACCESS_KEY_ID: ${{ vars.BACKBLAZE_SITE_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.BACKBLAZE_SITE_APP_KEY }}
        run: |
          mkdir -p site/dist/alerts
          for uf in $(jq -r '.[]' site/alert-states.json); do
            aws s3 cp --endpoint-url https://s3.us-east-005.backblazeb2.com --region us-east-005 \
              "s3://br-open-ocean-data-storage/exports/alerts/${uf,,}.json" site/dist/alerts/ \
              || echo "no alerts export for $uf — the page says so"
          done
```

A failed copy never fails the deploy (FR-010). The publish allowlist gains `alerts.html` and
`alerts/`. `site/alert-states.json` (`["RJ"]`) is the page's state picker and the copy loop.
