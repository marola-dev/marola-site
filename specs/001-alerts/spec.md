# Feature Specification: A list of past INMET alerts, each checked by marola

**Feature branch**: `claude/10-alerts-speckit`
**Created**: 2026-10-05
**Status**: Draft. The maintainer answered the open questions on 2026-10-05 (table below); one
reading is still to confirm (Q8).
**Issue**: marola-dev/marola-site#10
**MIP**: [MIP-0034](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0034-rss-feeds-and-content-syndication.md), amended with these decisions
**Input** (the maintainer, 2026-10-05): "The idea is to have a list of past alerts and the
alerts are checked by marola (OK, not OK). Go to a simple implementation first, taking into
consideration probably this solution will require alerts ingests per state, maybe related to
INMET." The list starts with the alerts Rio de Janeiro got on 2026-09-29 (#10).

## Decisions

| # | Question | Answer (2026-10-05) |
|---|---|---|
| Q1 | Which 2026-09-29 RJ alert | All of them: every INMET alert covering RJ on that day is in the list |
| Q2 | What the check compares | Once an alert expires, what INMET forecast (rain, wind, humidity, temperature) against what Open-Meteo recorded at the alert's places during its window |
| Q3 | Sources | INMET only |
| Q4 | States | RJ first; the store, the ingest and the page are selected and partitioned by state, so another state is one more value, not new code |
| Q5 | Alert types | Every INMET event |
| Q6 | Where | A new page, `alerts.html` |
| Q7 | Storage | The open ocean data store: a table in the DuckLake on Cloudflare R2, written by marola-app's `oods` module ([marola-oods spec 001](https://github.com/marola-dev/marola-oods/pull/3)) |
| Q8 | History | Kept forever, and backfilled before September 2026. **To confirm**: this spec reads "past alerts (before september 2026)" as "also load the alerts from before September 2026", as far back as INMET serves them (to 2022, [research R1](research.md#r1-inmet-avisos)) |
| Q9 | Language | The alert's text in Portuguese only, as INMET wrote it; page chrome through `site/i18n/` as every page |
| Q10 | Design record | This spec, with MIP-0034 amended (§5.2a) and MIP-0044 §11's "drop Alerts" note reversed |

## User Scenarios & Testing *(mandatory)*

### User Story 1 — a visitor sees RJ's past alerts and marola's check (Priority: P1) 🎯 MVP

A visitor opens `alerts.html` from the nav and sees every INMET alert for Rio de Janeiro state,
newest first: active ones on top, then the archive. Each past alert shows marola's verdict next to
INMET's own words.

**Why this priority**: it is the whole ask; everything else feeds it.

**Independent test**: with a fixture `alerts/rj.json` in `site/dist`, the page renders the
2026-09-29 alerts with every field below, makes no request but to its own origin, and works in
pt-BR and `?lang=en`.

**Acceptance scenarios**

1. **Given** the 2026-09-29 RJ alerts are in the store, **when** a visitor opens `alerts.html`,
   **then** each shows: INMET as issuer; the event (`Tempestade`); the severity as INMET names it
   (`Perigo Potencial`, `Perigo`, `Grande Perigo`) with INMET's colour; the valid-from and
   valid-to times in `America/Sao_Paulo`; the municipalities in RJ; INMET's description and
   instructions in Portuguese, unchanged; a link to INMET's page for that alert.
2. **Given** an alert has expired and been checked, **then** it shows marola's verdict
   (`confirmado` / `não confirmado`, i.e. OK / not OK), labelled as marola's check, with the
   values that decided it (e.g. "maior rajada medida: 72 km/h; previsto: 60–100 km/h").
3. **Given** an alert is still active, or expired less than the check's lag ago, **then** it
   shows "verificação pendente" and no verdict.
4. **Given** an alert names nothing the check can measure (hail alone, for instance), **then**
   it shows "sem verificação possível" and why, never a guessed verdict.
5. **Given** the last ingest is older than a day, **then** the page says when alerts were last
   fetched.

### User Story 2 — alerts arrive and get checked without anyone adding them (Priority: P1)

A scheduled job ingests INMET's alerts for each configured state into the store, and a second
step checks every alert whose window has closed.

**Independent test**: against a local lake and captured INMET and Open-Meteo answers, one run
inserts the alerts, a second identical run changes nothing, and a run after the window closes
writes the expected verdicts.

**Acceptance scenarios**

1. **Given** `--uf RJ`, **when** the job runs, **then** every live INMET alert with a
   municipality in RJ is in the `alert` table under `uf = 'RJ'`, and nothing outside RJ is
   written.
2. **Given** INMET updates or cancels an alert already stored, **then** the stored row follows
   INMET (its CAP `msgType` and `references`), keeping when it changed.
3. **Given** an alert expired at least the check's lag ago and has no verdict, **then** the
   check writes one `alert_check` row.
4. **Given** INMET is unreachable, **then** the run records the failure in `fetch_run`, writes
   nothing else, and the site keeps the last export.

### User Story 3 — RJ's history before September 2026 (Priority: P2)

A one-off, resumable backfill loads RJ's past alerts by walking INMET's alert ids back to the
oldest one it serves, and checks each of them against Open-Meteo's archive.

**Independent test**: a backfill over a captured id range stores exactly the RJ alerts in it,
resumes where a killed run stopped, and a re-run writes nothing.

### User Story 4 — a second state (Priority: P3)

Adding SC or BA is a value in `etl/alert-states.json` (marola-oods) and the site's page picker;
no code changes.

### Edge cases

- An alert covers several states: one row per state it covers; each state's page lists it, and
  each state's check uses that state's places.
- An alert's window spans midnight or several days: checked over the whole window.
- INMET answers nothing to a default User-Agent ([research R1](research.md#r1-inmet-avisos)): the
  client always sends one.
- Open-Meteo has no data yet for the window: the check waits (stays pending) and retries on the
  next run.
- A description whose numbers do not parse: "sem verificação possível", the raw text still shown.

## Requirements *(mandatory)*

### Functional requirements

- **FR-001**: The store has an `alert` table partitioned by `uf` and the year of the alert's
  onset, keyed `(alert_id, uf)` ([data-model.md](data-model.md)).
- **FR-002**: `oods alerts --uf <UF>[,<UF>…]` loads INMET's live alerts for those states;
  `oods alerts --uf RJ --backfill` walks ids back, resumable (contracts/cli.md).
- **FR-003**: A state is in an alert iff one of the alert's municipalities (IBGE code) is in that
  state. The state list comes from the IBGE code's first two digits (RJ = 33).
- **FR-004**: INMET's text is stored and shown unchanged: event, severity, description,
  instructions, area description. Nothing is translated or summarised.
- **FR-005**: `oods alerts-check` writes one verdict per `(alert_id, uf)` once the window has
  closed and Open-Meteo has the data, by the rule in [research R3](research.md#r3-the-check).
- **FR-006**: The verdict is `confirmed`, `not_confirmed` or `not_checkable`, with the observed
  and forecast values that decided it, the check points used and the rule version.
- **FR-007**: `oods export` writes `exports/alerts/<uf>.json` per state; marola-site's build
  copies it into `site/dist/alerts/` with a read-only key; the page reads only that file.
- **FR-008**: `alerts.html` lists one state at a time (RJ only at first), active alerts first,
  then the archive by onset, newest first.
- **FR-009**: The nav's `alertas em breve` becomes a link to `alerts.html` on every page.
- **FR-010**: A failed ingest or export never fails a site deploy; the page shows the export's
  `generated_at`.
- **FR-011**: The page fetches nothing from any host but its own; CSP unchanged.

### Key entities

- **Alert**: one INMET alert in one state: id, event, severity (INMET's words and CAP's enum),
  colour, onset, expires, municipalities, polygon, description, instructions, link, status.
- **Alert check**: marola's verdict on one alert in one state, with its evidence.
- **Fetch run**: spec 001's `fetch_run`, with `job = 'alerts'` or `'alerts-check'`.

## Success criteria *(mandatory)*

- **SC-001**: A visitor reaches the 2026-09-29 RJ alerts and their verdicts from the nav in two
  clicks.
- **SC-002**: A new INMET alert for RJ is on the page within one ingest interval plus one site
  build (≤ 6 h with the schedules in [plan.md](plan.md)).
- **SC-003**: Every alert expired more than 2 days ago has a verdict or a stated reason why not.
- **SC-004**: An identical re-run of the ingest or the check creates no DuckLake snapshot.

## Assumptions

- INMET's CAP documents carry IBGE municipality codes as `<geocode>`; if not, the undocumented
  `avisos/ativos` JSON supplies them for live alerts ([research R1](research.md#r1-inmet-avisos)).
  To verify on the first real fetch: this sandbox cannot reach INMET.
- The site build gets a read-only R2 token (`marola-site-read`) (spec 001's phase 6). Creating it is a
  person's act.
- The DuckLake, its catalog round trip and the `oods-lake` concurrency group are spec 001's; this
  spec adds tables and a workflow, and changes nothing in that layout.

## Out of scope

- Changing the swim score because of an alert (MIP-0034 §5.2, MIP-0062).
- The live banner on the map (MIP-0034 §5.2).
- Push or Telegram notifications.
- Sources other than INMET (Marinha/CHM, Defesa Civil, Alerta Rio).
- An English translation of alert text.
