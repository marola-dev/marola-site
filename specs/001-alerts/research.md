# Research: alerts

This session's sandbox times out on INMET and Open-Meteo alike, so nothing here was re-fetched on
2026-10-05. INMET facts come from MIP-0034 §4.1 (fetched 2026-09-07/08) and marola-dev/marola-site#10
(searched 2026-09-30); Open-Meteo facts from its public docs and from marola-app, which already
calls it. Each "to verify" item is checked by the first real run (quickstart.md).

## R1. INMET avisos

| | |
|---|---|
| Feed | `https://apiprevmet3.inmet.gov.br/avisos/rss`, RSS 2.0, live alerts only (expired items drop off) |
| Per alert | `…/avisos/rss/<id>` is an OASIS CAP 1.2 document: event, severity, urgency, certainty, onset, expires, description, instruction, web, `areaDesc`, a polygon of `lat,lon` pairs |
| Severity | RSS `Perigo Potencial` / `Perigo` / `Grande Perigo`; CAP `Moderate` / `Severe` / `Extreme`; INMET's colour (`aviso_cor`) in the JSON below |
| Event types seen | Baixa Umidade, Tempestade, Chuvas Intensas, Ventos Costeiros, Vendaval, Geada, Declínio de Temperatura, Acumulado de Chuva (plus Onda de Calor and others in other seasons) |
| History | No archive endpoint, but ids are dense and old ones stay served (`55000` → 2026-07-15, `50000` → 2025-02-28, `40000` → 2022-08-29; `1000` → 500), so a past alert is fetched by id |
| JSON | `…/avisos/ativos`: `{"hoje": [...], "futuro": [...]}` with a GeoJSON polygon, `municipios` with IBGE codes, `estados`, `aviso_cor`. Undocumented, so enrichment only |
| Licence | `<copyright>public domain</copyright>` plus "pode ser reproduzido desde que citada a fonte": the page names INMET and links each alert |
| Trap | No HTTP response at all to curl's default User-Agent; a browser-like UA gets an immediate 200 |
| Key / cost | none |

**Decision**: CAP by id is the record (it is the same for live and past alerts, so the live
ingest and the backfill share one parser). The RSS lists the live ids; the backfill walks ids
downward. `avisos/ativos` adds the colour and municipality codes for live alerts when it answers.

**To verify**: whether CAP carries IBGE codes as `<geocode>` (FR-003 needs them for past alerts,
which `avisos/ativos` no longer lists); the id density, so the backfill's stop rule (R5) is right.
If CAP has no codes, a past alert's states come from its polygon against IBGE state boundaries,
and its municipalities from `areaDesc`.

## R2. The 2026-09-29 RJ alerts

Not read at the source. Press titles name an INMET yellow `Perigo Potencial` storm alert for Rio
and nine other cities (rain to 50 mm/day, wind to 60 km/h, hail, 09:25–23:59 per a search
summary) and an orange `Perigo` storm alert (wind to 100 km/h). The maintainer wants all of them
(Q1), so no id is hand-picked: the backfill (US3) loads every alert whose window touches RJ, and
the acceptance check is that both appear.

## R3. The check

**Decision**: an alert is `confirmed` when, at any of its check points (R4) and any hour of its
window, Open-Meteo recorded a value at or above the **lower bound** of at least one quantity
INMET forecast; `not_confirmed` when none did; `not_checkable` when INMET's text names no quantity
the table below measures.

| INMET wording (parsed from `description`) | Open-Meteo hourly variable | Compared |
|---|---|---|
| `… mm/h` | `precipitation` | hourly max ≥ lower bound |
| `… mm/dia` | `precipitation`, summed per local day | daily sum ≥ lower bound |
| `ventos … km/h` | `wind_gusts_10m` | max ≥ lower bound |
| `umidade relativa … %` | `relative_humidity_2m` | min ≤ upper bound (the alert is about low humidity) |
| `temperatura … °C` (heat, cold, frost) | `temperature_2m` | max ≥ / min ≤ the bound, by event |
| hail, lightning, anything else | none | not checked |

INMET's descriptions are templates per event and severity ("Chuva entre 20 e 30 mm/h ou até 50
mm/dia, ventos intensos (40-60 km/h)"), so a small parser of `entre X e Y`, `até Y`, `X-Y`, with
the unit, covers them. Every verdict stores the parsed bounds, the observed extremes, the check
points and a `rule_version`, so a later, stricter rule can re-check the archive without losing
the old verdicts.

"Any point, any hour, any quantity" is deliberately lenient: an alert is a forecast for a region,
and a warning that came true in one municipality came true. Its limit is that a model grid
smooths local extremes (a 9 km cell under a thunderstorm), so `not_confirmed` means "Open-Meteo's
model did not see it", and the page says so.

**Alternatives rejected**: comparing against marola's swim score (answers a different question);
a person marking each alert (the maintainer picked the automatic check, Q2); INMET's own station
network (a second source, and stations are sparse away from capitals).

## R4. Open-Meteo for observed values

| Use | Endpoint | Why |
|---|---|---|
| Alerts that closed in the last ~3 months | `https://api.open-meteo.com/v1/forecast` with `start_date`/`end_date` in the past | the same API marola-app calls; past hours are the model's best analysis |
| The backfill (2022 → 2026) | `https://archive-api.open-meteo.com/v1/archive` (ERA5 / ERA5-Land) | reanalysis, the stable record; about 5 days behind real time |

Both take several comma-separated coordinates in one request, `timezone=America/Sao_Paulo`, and
the hourly variables in R3; units are mm, km/h, %, °C by default. Free without a key for
non-commercial use (marola-app already relies on that). **Lag**: a live alert is checked 2 days
after it expires (SC-003), when the forecast API's past hours have settled.

**Check points**: the seats of the alert's municipalities in that state, from IBGE's municipality
table (code, name, lat, lon), vendored once into marola-app as a resource. RJ has 92
municipalities, so an alert has at most 92 points: one Open-Meteo request per alert.

**To verify**: the archive's coverage date for the most recent backfilled alerts; Open-Meteo's
licence line on the page (CC BY 4.0 attribution, as the map already gives it).

## R5. Ingest per state

**Decision**: one job, `oods alerts --uf RJ`, scheduled every 3 hours, aligned with `site.yml`.
It lists the RSS, fetches each new or changed id's CAP (≥ 250 ms apart, browser-like UA), keeps
the ones with a municipality in a requested state, and upserts per `(alert_id, uf)` in one
DuckLake transaction. The backfill walks ids downward from the newest stored, records the last id
done in `fetch_partition` (`partition_key = 'id:<n>'` per block of 500), stops after 200
consecutive 404/500 answers, and is budgeted by `--max-minutes` like spec 001's backfills.

**Why per state and not per area**: INMET alerts are regional (a mesoregion or more), the
maintainer wants selection and partitioning by state (Q4), and a state is also how agencies
partition water quality in spec 001. The page shows a state; the map areas sit inside one.

## R6. Storage: the DuckLake, not `site-data`

**Decision** (Q7): two tables in spec 001's DuckLake, and one JSON export per state the site
build reads. The alerts job joins the `oods-lake` concurrency group and the catalog round trip
unchanged. Partitioning by `uf` and year keeps a state's history in its own Parquet files, so an
export of RJ reads only RJ.

Sizes: INMET issues on the order of 100 alerts a day nationwide; RJ's share is a few a day, so
about 1,000–2,000 RJ rows a year, a few MB with polygons. Far inside R2's free 10 GB-month, and R2 charges no egress for the site build's reads.

## R7. Other sources (not used, recorded so nobody re-checks them blind)

| Source | State | Status |
|---|---|---|
| Marinha do Brasil / CHM avisos de mau tempo | all coast | HTTP 403 (Cloudflare) to scripts; no feed (MIP-0034 §4.6, MIP-0062 §4.3) |
| Alerta Rio, COR | RJ (city) | not fetched |
| Defesa Civil RJ, SC, BA | per state | not fetched |
