---
name: site-frontend
description: Use first for any change a visitor sees on marola.dev (site/static/*.html, app.js markup and markers, the Mapbox map and flow.js's wind and wave layers, style.css, the chat widget, 404.html, the copy) or when the page looks plain, inconsistent or generated; it orders the other frontend skills, Mapbox's included, and says which wins when they disagree
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
| `karpathy-guidelines` | how to change the code: surgical diffs, no speculative abstractions, a check per step | forrestchang/andrej-karpathy-skills, MIT (from Andrej Karpathy's notes on LLM coding) |
| `ptbr-humanizer` | every Portuguese string | here |
| `citizen-science-site` | sources, freshness, limits, privacy, contributing on the page | here |
| `news-post` | a news post: its files, format, reading time and build | here |
| `mapbox-web-integration-patterns` | Mapbox GL JS setup, lifecycle, token handling, common pitfalls (read its vanilla-JS parts) | mapbox/mapbox-agent-skills, MIT |
| `mapbox-web-performance-patterns` | load waterfall, markers vs layers, render cost, memory; check `flow.js` against it | mapbox/mapbox-agent-skills, MIT |
| `mapbox-data-visualization-patterns` | data-driven layers, heat and flow fields, animated data (the wind and wave layers) | mapbox/mapbox-agent-skills, MIT |
| `mapbox-cartography` | the base map: colour, hierarchy, labels over data | mapbox/mapbox-agent-skills, MIT |
| `mapbox-style-patterns` | layer recipes when a Studio style or a new map layer is designed | mapbox/mapbox-agent-skills, MIT |
| `mapbox-style-quality` | validating a style before `MAPBOX_STYLE` points at it: contrast, size, expressions | mapbox/mapbox-agent-skills, MIT |
| `mapbox-token-security` | the public token: scopes, URL restrictions, rotation; never an `sk.` token in the page | mapbox/mapbox-agent-skills, MIT |
| `mapbox-maplibre-migration` | the way out if Mapbox's price or licence stops fitting (MapLibre GL is BSD and keyless) | mapbox/mapbox-agent-skills, MIT |

The vendored skills stay byte-identical to upstream (their licences sit next to them); marola's
overrides live here, not in their files.

## marola wins over the vendored skills

1. **No framework, no build step, two third-party origins: Mapbox and NASA GIBS.** Ignore the Tailwind/React/Framer
   stack, `npm install` checks, picsum/Unsplash images and CDN fonts in `design-taste-frontend`,
   and the React/Vue/npm setup in the Mapbox skills. Plain CSS with the `:root` tokens; Mapbox GL
   JS is vendored (its CSP build, `vendor/mapbox-gl-csp*.js`), so scripts and the worker stay
   `'self'`; only the base map's style, tiles, fonts and the map-load count go to Mapbox's servers.
   The satellite layers (satélite, temperatura do mar, anomalias, El Niño) load NASA GIBS's
   public, keyless tiles, and only once a visitor picks one. Nothing else is fetched from another
   origin: no CDN, no other map or font provider.
2. **Inter is the font.** Taste discourages it by default but allows it for public-information,
   accessibility-first sites, which marola is. No serif.
3. **Lucide is the icon set**, chosen on purpose (the maintainer asked for an established set).
   The one custom shape (the jellyfish) is drawn on Lucide's grid.
4. **The score colours are data**, not an accent. "One accent" means `--accent`; green, yellow,
   orange and red never decorate.
5. **The map is light, like the chrome.** The base map is Mapbox's `outdoors-v12` (or the Studio
   style in `MAPBOX_STYLE`): the audience is beachgoers, and a dark Windy-like map read as too heavy
   for them. The rail, keys and popups are white glass. A dark theme is still DESIGN.md "Not yet",
   whatever taste says.
6. **Landing-page rules do not apply to the map**: hero, CTA, bento, testimonials, eyebrows.
   The map page has no hero; the about/support pages are reading columns.
7. **Lowercase house style stays**, with the exemptions `site_check.js` asserts.
8. **Copy**: no em dash anywhere a visitor reads (taste and `ptbr-humanizer` agree); `·` at most
   once per line.
9. **Karpathy's "if uncertain, ask"** means: on a visual fork, pick the DESIGN.md answer and say
   which; ask only when the change would alter scores, data or a public contract.
10. **Emil's "Initial Response" line** is for interactive chats; in a task, just apply the skill.

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
   then before/after screenshots in the PR body, pushed to the `pr-screenshots` branch and embedded
   by raw URL (AGENTS.md, "Screenshots in the PR"). No screenshot in the PR, not done.

## The map: Mapbox GL and the flow layer

- `app.js` owns the map (`ensureMap`): DOM markers for beaches, water points and "you" (so the
  score dot, its `aria-label` and keyboard focus stay plain HTML), a GeoJSON line layer for trails,
  and `hoverTip()` popups in place of Leaflet's sticky tooltips.
- `flow.js` is the Windy-like part: a Mapbox custom layer that draws, in WebGL, a colour field and
  moving particles for wind (km/h) or waves (m). The field is interpolated from the board's own
  beach readings, never a fetched weather grid, and fades out away from the beaches; the key says
  "estimated between beaches". `prefers-reduced-motion` freezes the particles. New layers follow
  `mapbox-data-visualization-patterns`, then this file's rules (the ramps are DESIGN.md tokens and
  never use the score colours).
- The token is `MAPBOX_PUBLIC_TOKEN` (a `pk.` token restricted to marola.dev), written into
  `mapbox-config.js` at deploy by `scripts/mapbox_config.sh`; the committed file stays empty.
  With no token there is no map (Mapbox GL's licence needs a Mapbox account) and the page says
  so and opens the list. `mapbox-token-security` decides anything about the token.
- `site_check.js` stubs `mapboxgl` (markers, popups, the custom layer without a GL context); the
  real look needs a browser with a token. The sandbox's Playwright cannot reach Mapbox, so a
  screenshot there answers `api.mapbox.com/styles/**` with a stand-in style and says so.

## Figma

`.mcp.json` registers Figma's remote MCP (`https://mcp.figma.com/mcp`, OAuth on first use, no
key in the repo). Use it to read a frame's tokens and spacing when a design arrives as a Figma
link; translate them into DESIGN.md tokens rather than pasting values.

## Red flags

A hex code in a rule · a second accent or a tinted band · a serif · a pill-shaped card or a
square button (radius scale broken) · a shadow on something that does not float · an emoji ·
an em dash in copy · a font or icon from a CDN · a control styled on its own · restyling without
opening the page · a Mapbox token in a committed file · a flow colour that could pass for a score.
