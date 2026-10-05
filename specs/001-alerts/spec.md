# Feature Specification: A list of past official alerts, each checked by marola

**Feature branch**: `claude/10-alerts-speckit`
**Created**: 2026-10-05
**Status**: Draft, open questions unanswered. Nothing below a `[NEEDS CLARIFICATION]` marker is
decided.
**Issue**: marola-dev/marola-site#10
**Input** (the maintainer, 2026-10-05): "The idea is to have a list of past alerts and the
alerts are checked by marola (OK, not OK). Go to a simple implementation first, taking into
consideration probably this solution will require alerts ingests per state, maybe related to
INMET." The first entry is the alert Rio de Janeiro got on 2026-09-29 (#10).

## What exists today

- The nav on `index.html`, `about.html` and `support.html` shows `alertas em breve`, a disabled
  item (`nav.alerts`, `nav.soon` in `site/i18n/`).
- No code fetches, stores or shows an alert anywhere in marola. MIP-0034 §4.1 and §5.2 designed
  an INMET banner on the map (never built); MIP-0044 §11 proposes dropping the `Alerts` nav item.
- What is known about the sources is in [research.md](research.md).

## Open questions

Each is asked in the thread with a recommendation; none is answered yet.

| # | Question | Recommended | Answer |
|---|---|---|---|
| Q1 | Which 2026-09-29 RJ alert is the first entry: INMET's yellow `Perigo Potencial` storm, the orange `Perigo` one reported by the press, or both? Link? | both | [NEEDS CLARIFICATION] |
| Q2 | What does "checked by marola (OK / not OK)" compare? (a) the issuer's forecast thresholds against Open-Meteo's recorded values once the alert expires; (b) whether marola's swim score flagged the same hours; (c) a person marks each one | (a) | [NEEDS CLARIFICATION] |
| Q3 | Which sources first: INMET only; plus Marinha/CHM; plus Defesa Civil RJ and Alerta Rio | INMET only | [NEEDS CLARIFICATION] |
| Q4 | Which states first: RJ only, or RJ, SC and BA | RJ only | [NEEDS CLARIFICATION] |
| Q5 | Which alert types: every event covering an area, or only sea and coast ones | every event | [NEEDS CLARIFICATION] |
| Q6 | Where the list lives: a new `alerts.html` page, or a panel on the map | `alerts.html` | [NEEDS CLARIFICATION] |
| Q7 | Storage for the first version: JSON on `site-data` from a marola-site workflow, or the B2 DuckLake via marola-app's `oods` module | `site-data` JSON | [NEEDS CLARIFICATION] |
| Q8 | Retention: every alert forever, or the last N months | forever | [NEEDS CLARIFICATION] |
| Q9 | English: chrome only, or also a marked translation of each alert's text | chrome only | [NEEDS CLARIFICATION] |
| Q10 | Design record: this spec plus a one-line MIP-0044 §11 update, or a MIP / MIP-0034 amendment first (#10 asks for the latter) | this spec | [NEEDS CLARIFICATION] |

## User Scenarios & Testing *(mandatory)*

### User Story 1 — a visitor sees past alerts for their area (Priority: P1)

A visitor opens the alerts list and sees the official alerts issued for a marola area, newest
first, starting with Rio de Janeiro's alert of 2026-09-29.

**Acceptance scenarios**

1. **Given** the 2026-09-29 RJ alert is recorded, **when** a visitor opens the list, **then** it
   shows that alert with its issuer, its severity as the issuer names it, its event, its area,
   its validity window and a link to the issuer's page.
2. Where the list is and which areas it covers: [NEEDS CLARIFICATION: Q4, Q6]

### User Story 2 — each alert carries marola's check (Priority: P1)

Each past alert shows marola's verdict, `OK` or `not OK`, next to the issuer's own words and
labelled as marola's.

**Acceptance scenarios**: [NEEDS CLARIFICATION: Q2 decides what the check compares, when it
runs, and what `OK` means]

### User Story 3 — new alerts arrive without anyone adding them (Priority: P2)

A scheduled job ingests alerts per state, so the list grows on its own.

**Acceptance scenarios**: [NEEDS CLARIFICATION: Q3, Q4, Q5, Q7]

### Edge cases

- The issuer's feed is unreachable: the list shows the last good data and when it was fetched;
  the deploy does not fail (constitution III).
- An alert is updated or cancelled by its issuer after it was recorded. [NEEDS CLARIFICATION]
- An alert covers more than one marola area.

## Requirements *(mandatory)*

### Functional requirements

- **FR-001**: The site lists official alerts for marola's areas, including past ones.
- **FR-002**: The 2026-09-29 RJ alert is in the list. [NEEDS CLARIFICATION: Q1]
- **FR-003**: Each alert shows the issuer's words unchanged and a link to the issuer's page.
- **FR-004**: Each alert carries marola's `OK` / `not OK` check, labelled as marola's.
  [NEEDS CLARIFICATION: Q2]
- **FR-005**: Alerts are ingested per state. [NEEDS CLARIFICATION: Q3, Q4, Q7]
- **FR-006**: The page fetches nothing from any host but its own (constitution II).

### Key entities

- **Alert**: one issuer warning. Fields beyond issuer, severity, event, area, validity window and
  source link: [NEEDS CLARIFICATION: Q5, Q9]
- **Check**: marola's verdict on one alert. [NEEDS CLARIFICATION: Q2]

## Success criteria *(mandatory)*

- **SC-001**: A visitor can find the 2026-09-29 RJ alert and marola's check of it from the nav.
- **SC-002**: [NEEDS CLARIFICATION: freshness target for new alerts, once Q7 is answered]

## Out of scope

- Changing the swim score because of an alert (MIP-0034 §5.2, MIP-0062).
- Push or Telegram notifications.
- Any source not verified as fetchable and licensed for reuse.
