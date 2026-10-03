---
name: design-system
description: Use before any visual change to marola's frontend (site/static/*.html, style.css, app.js markup and markers, the chat widget, 404.html) to apply DESIGN.md, the Co2 editorial style with marola's blue adaptations
---

# design-system: apply DESIGN.md to marola's frontend

## Overview

`DESIGN.md` at the repo root is the style reference for everything a visitor sees. It opens with
**marola adaptations**, which win over the Co2 reference below them (obtained from Refero's
style library): blue is the primary, one control style everywhere, a compact header, line icons
instead of emoji, beaches as dots. Pair this skill with `site-frontend` (the recipe: look first,
verify, screenshots); this one says what the result should look like.

## Before touching CSS

1. Read `DESIGN.md`: the adaptations first, then the reference's type scale, components and
   do's and don'ts. Pick the named component for each element; don't invent one.
2. Read the `:root` block of `site/static/style.css` and reuse its tokens; never paste a hex
   code into a rule.

## Tokens

| Token | Value | Job |
|---|---|---|
| `--ink` | `#181b22` Editorial Ink | body text |
| `--muted` | `#5b5e66` | secondary text on white (Muted Steel fails 4.5:1 there) |
| `--navy` | `#0b3d8c` Abyss Blue | serif headings, wordmark, primary-action fill, marker rim |
| `--blue-ink` | `#1659c0` Harbor Blue | links, selected fill, line icons, slider |
| `--accent` | `#4098ff` Climate Blue | hover/focus rings, link underlines, rules, the wordmark's wave; never text |
| `--ice` | `#eef6ff` Ice Blue | header band, footer, hover fill |
| `--cyan` | `#dff9ff` Cyan Wash | empty sea under the map, chat answers |
| `--line` | `#d9d9d9` Rule Gray | every border and divider |
| `--c70 … --cna` | score colours | data: legend, dots, chips. Never decoration, never changed without a MIP note |
| `--serif` / `--sans` | Cormorant Garamond / Inter | self-hosted in `vendor/fonts/` |

Mint Wash is not used. Green on the page means a good score, nothing else.

## The one control

`select`, `button` and `.sitenav > a` share one rule in `style.css`: 36 px tall (32 px under
640 px), 999 px radius, 1px `--line`, white fill, 16 px (14 px) Inter. Hover: `--ice` fill and
`--accent` border. Selected (`aria-pressed`, `aria-expanded`, `aria-current="page"`, `.on`):
`--blue-ink` fill, white text. Primary action (chat open/send): `--navy` fill. Segmented groups
(`.segmented`, `.lang`): one outlined pill holding borderless inner pills. Close buttons: the same
control as a 32 px circle. A new control reuses this rule; it does not get its own look.

## Header

Nav pills on an `--ice` band; under them the 38 px serif wordmark (30 px on phones) with a 14 px
one-line tagline, controls on the same row; then the hour bar on white. The map must start above
the fold at 390 × 844. Nav sections with no page yet are muted text, hidden under 640 px.

## Icons

No emoji anywhere a visitor looks. Use `icon(name)` in `app.js` (Lucide's shapes, ISC licence in
`vendor/icons/LICENSE.lucide`), or the same inline `<svg class="ic">` markup in HTML, with the
label in its own `<span data-i18n>` so a language flip keeps the icon. A shape Lucide lacks is
drawn on its 24 px grid with round caps. The icon is `aria-hidden`; its word always follows.
`site_check.js` reads icons as `[name]` and fails a tooltip that carries an emoji.

## Map markers

A beach is a 16 px dot filled with its score colour, a 2 px white ring and an `--navy` rim; the
selected beach is a 32 px badge with its score in the middle (ink text on the 40–69 yellow,
white on the rest). No wave glyphs, halos, shadows or opacity in the marker SVG. The legend key
in `index.html` draws the same dot.

## Rules that come from marola

- **No third-party requests**: fonts and icons are vendored; the CSP is `default-src 'self'`.
- **Contrast ≥ 4.5:1** for text; Climate Blue never carries text.
- **Bottom sheets under 640 px keep 24 px padding** (32 px elsewhere).
- **The lowercase house style stays**, with its exemptions (`site_check.js` asserts them).

## Checklist

- Serif only for headings at 30 / 38 / 56 / 64 px, weight 300, in `--navy`.
- Sans at 14 / 16 / 18 px; weights 400, 500, 600.
- Radii: 999 px controls, 16 px cards, 32 px large panels, 0 px images.
- No `box-shadow` on cards or panels, no gradients, no thick or dark borders.
- `node scripts/site_check.js`, `python3 scripts/i18n_bundle.py --check`, then before/after
  screenshots at 390 px and 1280 px in the PR.

## Red flags

An emoji in markup or copy · a control styled on its own · green or mint as a highlight · Climate
Blue as text · a hex code in a rule · a shadow or gradient · a wave or pin glyph back on the map ·
a font or icon set from a CDN · a 56 px headline on the map page.
