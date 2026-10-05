# Research: alerts sources

What is known about each candidate source. Nothing here was re-fetched on 2026-10-05: this
session's sandbox times out on every host below, so the facts come from MIP-0034 §4 (fetched
2026-09-07/08) and marola-dev/marola-site#10 (searched 2026-09-30).

## R1. INMET avisos

| | |
|---|---|
| Feed | `https://apiprevmet3.inmet.gov.br/avisos/rss`, RSS 2.0, live alerts only (expired items drop off) |
| Per alert | `…/avisos/rss/<id>` is an OASIS CAP 1.2 document: event, severity, urgency, certainty, onset, expires, description, instruction, `areaDesc`, and a polygon of `lat,lon` pairs |
| Severity | RSS `Perigo Potencial` / `Perigo` / `Grande Perigo`; CAP `Moderate` / `Severe` / `Extreme` |
| Event types seen | Baixa Umidade, Tempestade, Chuvas Intensas, Ventos Costeiros, Vendaval, Geada, Declínio de Temperatura, Acumulado de Chuva |
| Coverage | Metropolitana do Rio de Janeiro, Catarinense/Florianópolis, Sul Baiano and Metropolitana de Salvador all appear |
| History | No archive endpoint, but ids are dense and old ones stay served (`55000` → 2026-07-15, `50000` → 2025-02-28, `40000` → 2022-08-29), so a past alert can be fetched by id |
| JSON | `…/avisos/ativos` (GeoJSON polygon, IBGE municipality codes, INMET's colour); undocumented, so enrichment only |
| Licence | `<copyright>public domain</copyright>` plus "pode ser reproduzido desde que citada a fonte" |
| Trap | No response at all to curl's default User-Agent; a browser-like UA gets an immediate 200 |
| Key / cost | none |

## R2. The 2026-09-29 RJ alert

Not read at the source (#10's research was blocked too). Press titles name an INMET yellow
`Perigo Potencial` storm alert for Rio and nine other cities (rain to 50 mm/day, wind to 60 km/h,
hail, 09:25–23:59 per a search summary) and an orange `Perigo` storm alert (wind to 100 km/h).
Its INMET id, and so its CAP document, is not known yet (Q1).

## R3. Other sources, not verified

| Source | State | Status |
|---|---|---|
| Marinha do Brasil / CHM avisos de mau tempo | all coast | HTTP 403 (Cloudflare) to scripts; no feed (MIP-0034 §4.6, MIP-0062 §4.3) |
| Alerta Rio, COR | RJ (city) | not fetched |
| Defesa Civil RJ, SC, BA | per state | not fetched |

## R4. Data for the check

[NEEDS CLARIFICATION: depends on Q2. If the check compares forecast thresholds against recorded
values, the candidate is Open-Meteo's historical API, which marola already calls for forecasts.]
