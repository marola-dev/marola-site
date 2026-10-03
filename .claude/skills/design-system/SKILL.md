---
name: design-system
description: Use before any visual change to marola's frontend (site/static/*.html, style.css, app.js markup, the chat widget, 404.html) to apply DESIGN.md, the Co2 editorial style reference — tokens, type, components, do's and don'ts
---

# design-system: apply DESIGN.md to marola's frontend

## Overview

`DESIGN.md` at the repo root is the style reference for everything a visitor sees: the Co2
"climate atlas in winter light" — paper-white fields, hairline rules, pill navigation, light serif
statements, and saturated colour kept for classification only. This skill maps it onto marola's
page. Pair it with `site-frontend` (the recipe: look first, verify, screenshots); this one says
what the result should look like.

## Before touching CSS

1. Read `DESIGN.md` whole: the colour table, the type scale, the components and the do's and
   don'ts. Pick the named component for each element you change; don't invent one.
2. Read the `:root` block of `site/static/style.css`. The DESIGN.md tokens already live there
   under short names; reuse them instead of pasting hex codes.

## How DESIGN.md maps onto marola

| DESIGN.md | marola |
|---|---|
| Gt Alpina Standard (proprietary) | **Cormorant Garamond** 300/400, self-hosted in `site/static/vendor/fonts/` (`--serif`) |
| Abacaxilatinweb / Abacaxilatin (proprietary) | **Inter** variable, self-hosted (`--sans`) |
| Editorial Ink `#181b22` | `--ink`: all text, control outlines, icons |
| Paper White / Soft Canvas / Washed Gray | `--bg` and `--panel` / `--soft` (footer) / `--wash` (hover) |
| Rule Gray `#d9d9d9` | `--line`: every divider and panel hairline |
| Cyan Wash | `--cyan`: the chosen day (a filter), the empty map, assistant chat bubbles |
| Mint Wash | `--mint`: the selected state only (current page pill, pressed language, pressed sound) |
| Climate Blue | `--accent`: link underlines, focus ring, `::selection`, the "you" marker in `app.js` |
| System colour markers (violet, orange, teal, purple) | marola's five **score tokens** `--c70 … --cna`. They are data, stay as they are, and are the only saturated colour on the page |
| Global Pill Navigation | `.sitenav` links; a section with no page yet is plain muted text, no pill |
| Transparent Outline Pill | `select` and `button` in the header |
| White Data Card | `.list` and `.card` over the map: 16 px radius, 1 px `--line`, no shadow |
| Hero Editorial Heading | the wordmark (56 px, 38 px under 640 px) and the first `h2` of about/support (64 px) |
| Section heading 38 / 30 px | `.card h2`, the other about/support `h2`s |
| Blue Environmental Hero Image | the map itself is the page's one environmental visual |

## Rules that come from marola, not from DESIGN.md

- **No third-party requests.** Fonts are vendored woff2 plus their OFL licence, loaded with
  `@font-face` from `vendor/fonts/`. Never link Google Fonts or a CDN: the CSP is `default-src
  'self'`, and the page promises none.
- **Contrast ≥ 4.5:1.** Climate Blue text on white is about 3:1, so links stay ink with a blue
  underline. Muted Steel is for dark cards; secondary text on white uses `--muted` (`#5b5e66`).
- **The score colours do not change.** They are the legend and the markers. A change there is a
  scoring-communication change and needs a MIP note.
- **Bottom sheets under 640 px keep 24 px padding**, the one exception to DESIGN.md's 32 px card
  padding: 32 px leaves a 390 px phone too little line for the readings.
- **The lowercase house style stays**, with its exemptions (`site_check.js` asserts them).
- **The map gets the space.** On `index.html` the header stays compact enough that the map starts
  above the fold at 390 × 844.

## Checklist

- Serif only for headings at 30 / 38 / 56 / 64 px, weight 300. Never a sans display heading.
- Sans at 14 (meta) / 16 (nav, controls) / 18 (reading copy) px; weights 400, 500, 600.
- Radii: 999 px pills and nav, 8 px filled chips and buttons, 16 px cards, 32 px large panels,
  0 px images.
- Spacing on the 8 px grid; 64 px between editorial sections.
- No `box-shadow` on cards or panels, no gradients, no thick or dark borders.
- Mint marks a selected state, never the default action.
- `node scripts/site_check.js`, then screenshots at 390 px and 1280 px before and after, in the PR.

## Red flags

A hex code in a rule instead of a token · a shadow "to lift" a panel · a gradient · Climate Blue
as a text colour · serif body copy · Inter or Cormorant from a CDN · a score colour reused as
decoration · mint on every button · a pill around a disabled nav item.
