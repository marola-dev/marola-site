# Contract: the `oods` commands for alerts (marola-app)

Added to spec 001's `marola.oods.Main` ([marola-oods spec 001, contracts/cli.md](https://github.com/marola-dev/marola-oods/pull/3)),
with its settings (`OODS_*`), exit codes and `fetch_run` row unchanged.

```text
oods alerts --uf RJ[,SC,…] [--backfill] [--max-minutes 300] [--now <iso>]
oods alerts-check --uf RJ[,SC,…] [--lag-days 2] [--rule-version 1] [--now <iso>]
oods export --alerts RJ[,SC,…]
```

| Command | Reads | Writes | Exit 0 when |
|---|---|---|---|
| `alerts` | INMET RSS + CAP per id (and `avisos/ativos`, best-effort) | `alert` upserts per `(alert_id, uf)`, one transaction per state; `fetch_run`; with `--backfill`, `fetch_partition` per 500-id block | every requested state committed, or nothing changed |
| `alerts-check` | `alert` rows due (R3's lag) without a verdict for `--rule-version`; Open-Meteo (forecast or archive by age) | `alert_check` inserts, one transaction per state; `fetch_run` | every due alert has a verdict or stays pending because Open-Meteo has no data yet |
| `export --alerts` | `alert` ⟕ latest `alert_check` per state | `exports/alerts/<uf>.json` (lower-case uf), valid against [alerts-export.schema.json](alerts-export.schema.json) | every file written |

Failures use spec 001's failure enum, plus:

| Case | Exit | Meaning |
|---|---|---|
| `InmetSilent` | 3 | INMET accepted the connection and sent nothing (wrong User-Agent, or an outage) |
| `UnknownUf` | 2 | a `--uf` value is not one of the 27 IBGE states |
| `OpenMeteoRefused` | 3 | 429 or 5xx from Open-Meteo after 3 attempts; the due alerts stay pending |

`--now` exists for tests; the default is the injected clock.
