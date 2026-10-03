---
name: site-frontend
description: Use first for any change a visitor sees on marola.dev (site/static/*.html, app.js markup and markers, style.css, the chat widget, 404.html, the copy) or when the page looks plain, inconsistent or generated; it orders the other frontend skills and says which wins when they disagree
---

# site-frontend: the entry point for marola's frontend

## Overview

The map is a data product: the score colours, numbers and sources are the design. `DESIGN.md`
holds the tokens and components; this skill is the recipe and the referee between the general
frontend skills vendored next to it, which were written for landing pages and React apps.

## Which skill, when

| Skill | Use it for | Source |
|---|---|---|
| `site-frontend` (this) | the recipe, marola's constraints, conflict rules | here |
| `DESIGN.md` | tokens, type scale, components | here |
| `frontend-design` | planning a direction before a bigger change; its critique pass | anthropics/skills, Apache-2.0 |
| `design-taste-frontend` | the anti-slop pre-flight: AI tells, contrast, layout discipline | Leonxlnx/taste-skill, MIT |
| `emil-design-eng` | polish of a component: states, press feedback, easing, review table | emilkowalski/skill, MIT |
| `review-animations` | any motion change (invoke it by name) | emilkowalski/skill, MIT |
| `break-ui` | stress a panel with worst-case data (long beach names, no data, 40 beaches) | emilkowalski/skill, MIT |
| `webapp-testing` | Playwright scripts against `just site-serve` | anthropics/skills, Apache-2.0 |
| `ptbr-humanizer` | every Portuguese string | here |
| `citizen-science-site` | sources, freshness, limits, privacy, contributing on the page | here |

The vendored skills stay byte-identical to upstream (their licences sit next to them); marola's
overrides live here, not in their files.

## marola wins over the vendored skills

1. **No framework, no build step, no third-party request.** Ignore the Tailwind/React/Framer
   stack, `npm install` checks, picsum/Unsplash images and CDN fonts in `design-taste-frontend`.
   Plain CSS with the `:root` tokens; the CSP is `default-src 'self'`.
2. **Inter is the font.** Taste discourages it by default but allows it for public-information,
   accessibility-first sites, which marola is. No serif.
3. **Lucide is the icon set**, chosen on purpose (the maintainer asked for an established set).
   The one custom shape (the jellyfish) is drawn on Lucide's grid.
4. **The score colours are data**, not an accent. "One accent" means `--accent`; green, yellow,
   orange and red never decorate.
5. **Dark mode is deferred** (taste calls it mandatory): the map tiles have no dark source yet.
   DESIGN.md "Not yet".
6. **Landing-page rules do not apply to the map**: hero, CTA, bento, testimonials, eyebrows.
   The map page has no hero; the about/support pages are reading columns.
7. **Lowercase house style stays**, with the exemptions `site_check.js` asserts.
8. **Copy**: no em dash anywhere a visitor reads (taste and `ptbr-humanizer` agree); `·` at most
   once per line.
9. **Emil's "Initial Response" line** is for interactive chats; in a task, just apply the skill.

## The recipe

1. **Look first.** `just site-build floripa && just site-serve` (or copy a `site/dist/`), then
   screenshot 390 × 844 and 1280 × 800 with the Playwright MCP (`.mcp.json`) or a
   `webapp-testing` script. Write down at most five concrete problems.
2. **Plan** with `frontend-design`'s token step if the change is more than one component.
   Reuse DESIGN.md's tokens; a new token needs a job none does, and goes in DESIGN.md first.
3. **Build** in `style.css`, `index.html`, `app.js`. Markup the harness reads (`.sitenav` before
   `.bar`, `#lang` before `a.gh`, the dot marker, `[data-i18n]` leaves) stays.
4. **Pre-flight**: taste's section 9 (AI tells) and contrast checks, Emil's review table for the
   touched components, `break-ui` for a new panel.
5. **Copy** through `ptbr-humanizer`; edit `site/i18n/*.json`, run `python3 scripts/i18n_bundle.py`.
6. **Verify**: `node --check site/static/app.js`, `node scripts/site_check.js`,
   `node scripts/redirect_check.js`, `python3 scripts/i18n_bundle.py --check`, `ruff check .`,
   then before/after screenshots in the PR. No screenshot, not done.

## Figma

`.mcp.json` registers Figma's remote MCP (`https://mcp.figma.com/mcp`, OAuth on first use, no
key in the repo). Use it to read a frame's tokens and spacing when a design arrives as a Figma
link; translate them into DESIGN.md tokens rather than pasting values.

## Red flags

A hex code in a rule · a second accent or a tinted band · a serif · a pill-shaped card or a
square button (radius scale broken) · a shadow on something that does not float · an emoji ·
an em dash in copy · a font or icon from a CDN · a control styled on its own · restyling without
opening the page.
