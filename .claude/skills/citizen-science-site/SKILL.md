---
name: citizen-science-site
description: Use when adding or reviewing a page, section or panel on marola.dev, to keep it an open-source citizen-science site people can trust and join: sources, method, freshness, limits, privacy, licence and how to contribute visible
---

# citizen-science-site: a public, checkable, joinable site

## Overview

marola publishes beach scores built from public data by open code. Visitors trust it only if they
can see where each number comes from and how old it is, and contributors join only if the way in
is obvious. Use this with `site-frontend` and `DESIGN.md` (how it looks) and `ptbr-humanizer` (how the Portuguese
reads); this skill is about what must be on the page.

## What every page carries

| Item | Where today | Rule |
|---|---|---|
| Data sources, linked | footer status line (`footer.generated`), card "fonte", about | Every number on screen traces to a named, linked provider |
| Freshness | footer "atualizado em", card sample dates, "laudo antigo" note | Show when the data was computed and when a sample was taken; flag stale data in words |
| Method | about "como funciona a pontuação", docs.marola.dev | One click from the map to how the score is made |
| Limits | legend "sem dados", note codes, about | Say what is missing or estimated; never fill a gap silently |
| Privacy | footer, about "privacidade" | "sem cookies e sem rastreamento próprio" stays visible, and about names what Mapbox, the base map, receives; location never leaves the browser |
| Open code and docs | nav "docs", GitHub pill, footer link | Repo and docs reachable from every page |
| Money | support page | Costs and donations are public and checkable |
| Contribute | docs, GitHub | A visitor can find the issue tracker and the docs from the page they are on |

## Rules

- **No claim without a source.** A new panel that shows a number names its provider and date.
- **Official verdicts verbatim.** PRÓPRIA/IMPRÓPRIA as the agency writes them, with the sample
  point and date.
- **Safety first, plainly.** Unfit water is red with the reason; an emergency or safety note is
  never softened or hidden behind a hover.
- **No dark patterns**: no cookie banner tricks, no tracking pixels, no sign-up walls, and no
  third-party request beyond Mapbox's base map and NASA GIBS's satellite layers (which about's privacy section names).
- **"Em breve" is honest.** Unbuilt sections are muted text, not dead links.
- **Accessible by default**: contrast ≥ 4.5:1, every control has a name, icons are
  `aria-hidden` with a word next to them, the page works at 390 px.

## Review checklist

Before calling a visible change done: can a first-time visitor answer, from the page alone,
"where does this number come from?", "how old is it?", "what does it not know?", "is anyone
tracking me?" and "how do I help or check the code?" If one answer needs a guess, fix the page.
