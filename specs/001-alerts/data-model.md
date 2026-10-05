# Data model: alerts

Two tables added to the open ocean data store's DuckLake ([marola-oods spec 001's
data-model](https://github.com/marola-dev/marola-oods/pull/3)), one export per state, and the
page's view of it. `fetch_run` and `fetch_partition` are spec 001's, reused with
`job = 'alerts' | 'alerts-check'` and `source_id = 'inmet-avisos'`.

## The bucket's tree (additions only)

```text
s3://br-open-ocean-data-storage/
  lake/main/alert/uf=RJ/year=2026/…parquet          alert, partitioned by uf, year(onset)
  lake/main/alert_check/uf=RJ/year=2026/…parquet    alert_check, same partitioning
  exports/alerts/rj.json                            the page's data for RJ (contracts/alerts-export.schema.json)
```

## Tables

| Table | One row is | Key | Rows |
|---|---|---|---|
| `alert` | an INMET alert in one state | `(alert_id, uf)` | ~1–2k a year for RJ |
| `alert_check` | marola's verdict on one alert in one state, for one rule version | `(alert_id, uf, rule_version)` | one per alert |

```mermaid
erDiagram
  alert ||--o{ alert_check : "checked by"
  alert {
    bigint alert_id PK "INMET id, the n in /avisos/rss/n"
    text uf PK "IBGE state abbreviation, RJ"
    int year "partition: year(onset) in America/Sao_Paulo"
    text event "CAP event, verbatim: Tempestade"
    text severity_label "INMET: Perigo Potencial | Perigo | Grande Perigo"
    text severity "CAP: moderate | severe | extreme"
    text color "INMET aviso_cor, #FFFE00; NULL when unknown"
    timestamptz onset
    timestamptz expires
    text status "active | updated | cancelled (from CAP msgType/references)"
    bigint replaced_by "the id that updated or cancelled this one, or NULL"
    text area_desc "CAP areaDesc, verbatim"
    list municipalities "list of (ibge_code, name), only this uf's"
    list polygon "list of (lat, lon), the whole alert's"
    text description "verbatim"
    text instruction "verbatim"
    text link "INMET's page for this alert"
    timestamptz sent "CAP sent"
    timestamptz first_seen "when marola first stored it"
    timestamptz updated_at "when a stored column last changed"
  }
  alert_check {
    bigint alert_id PK
    text uf PK
    int rule_version PK "1 = research R3"
    int year "partition, same as alert"
    text verdict "confirmed | not_confirmed | not_checkable"
    text reason "for not_checkable: no measurable quantity | unparsed text"
    json forecast "parsed bounds: [{quantity, low, high, unit}]"
    json observed "per quantity: {max or min, at point, at hour}"
    text endpoint "forecast | archive"
    int points "check points used"
    timestamptz checked_at
  }
```

## Enums (persisted by label, never ordinal)

| Enum | Labels |
|---|---|
| `Severity` | `moderate`, `severe`, `extreme` (CAP); `unknown` if CAP has another value |
| `AlertStatus` | `active`, `updated`, `cancelled` |
| `Verdict` | `confirmed`, `not_confirmed`, `not_checkable` |
| `Quantity` | `rain_hour`, `rain_day`, `wind_gust`, `humidity`, `temperature_max`, `temperature_min` |

`active` is INMET's state, not time: whether an alert is live now is `now ∈ [onset, expires)`,
computed at export.

## Lifecycles

- **Insert**: a new `(alert_id, uf)`.
- **Update**: INMET's CAP `Update` names the ids it replaces; the old row gets `status = 'updated'`
  and `replaced_by`, the new id is its own row. `Cancel` sets `status = 'cancelled'`. A cancelled
  or replaced alert is still listed, marked, and is never checked.
- **Same content**: no write, so no snapshot (SC-004).
- **Check**: written once per `(alert_id, uf, rule_version)` when `expires + 2 days ≤ now` (live)
  or at backfill time (archive). Never updated; a new rule version adds rows.
- **Delete**: never. History is kept forever (Q8). DuckLake snapshot expiry (spec 001, 30 days)
  removes old *versions*, not rows.

## The export, per state

`exports/alerts/<uf>.json`, schema in
[contracts/alerts-export.schema.json](contracts/alerts-export.schema.json): `generated_at`, `uf`,
and every alert of that state with its latest-rule check, newest onset first. Polygons are left
out (the page draws none), so RJ's whole history stays a few hundred KB.
