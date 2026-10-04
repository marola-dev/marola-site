# DESIGN.md: marola's visual system

The map is a data product. The score colours, the numbers and the sources carry the page; the
chrome around them stays quiet, neutral and consistent so they read in five seconds on a phone.
This file is the single source for tokens and components. `style.css`'s `:root` mirrors it.

It replaced, in PR #42, the Co2 editorial reference (Refero) the redesign started from: a
serif broadsheet look with five blues read as decoration on a map tool, and both `frontend-design`
and `design-taste-frontend` list its signatures (hairline rules, display serif, `·` meta strings)
as defaults to avoid.

## Principles

1. **Data first.** Colour on the page means a score. Chrome is neutral gray; one blue accent
   marks what you can act on.
2. **One of everything.** One accent, one control style, one radius scale, one type family.
3. **Elevation only where it is real.** Panels that float over the map get a soft shadow;
   nothing else does.
4. **Dense but calm.** It is a tool people check daily: small type with clear weight
   contrast, tight rows, generous gaps between groups.

## Colour

| Token | Value | Job |
|---|---|---|
| `--ink` | `#111820` | text, headings |
| `--muted` | `#56606c` | secondary text (6.3:1 on white) |
| `--bg` | `#ffffff` | page, panels, controls |
| `--surface` | `#f3f5f7` | utility strip, footer, hover, segmented tracks, chat answers |
| `--line` | `#e1e5ea` | dividers, panel borders |
| `--line-strong` | `#cbd2da` | control borders |
| `--sea` | `#cfe6f1` | the map before the base map loads |
| `--accent` | `#1b5fc1` | links, primary action fill, focus ring, slider, the "you" marker |
| `--accent-hover` | `#164e9e` | hover on accent |
| `--accent-soft` | `#e9f0fb` | pressed toggles, the visitor's chat messages |
| `--c70 … --cna` | score colours | data only: dots, chips, legend. A change needs a MIP note |
| `--flow-wind-0 … 5` | `#5b6db3` → `#a8566a` | the wind field, calm to 40 km/h (`flow.ts`, the key's ramp) |
| `--flow-wave-0 … 5` | `#2f5a9e` → `#c86e6e` | the wave field, flat to 3 m |
| `--sst-0 … 5`, `--anom-*` | GIBS-like | the satellite layers' key ramps, after GIBS's own palettes |
| `--glass`, `--glass-*` | `rgb(255 255 255 / .9)`, … | what floats over the map: layer rail, key, zoom buttons, popups |

The flow ramps are data too. They follow Windy's muted scales, which visitors already read; a
score is never told by the field's colour alone, because the beach dots sit on top with a ring
and the selected one with its number.
No other hex in a rule. The marker rim (`#1d2733`) and the score colours live in `view.ts`'s SVG,
where CSS variables do not reach.

## Type

Inter only, self-hosted (`vendor/fonts/inter-latin-wght-normal.woff2`, variable weight), never
from a CDN. Inter is the deliberate pick for a public-information, accessibility-first page.

| Role | Size / weight | Where |
|---|---|---|
| Page title | 34 px / 650, -0.025em (28 px on phones) | first heading of about/support |
| Wordmark | 22 px / 650, -0.02em (20 px) | header |
| Panel title | 20 px / 650 (18 px) | card h2, about section h2 |
| Body | 15 px / 400, 1.5 | map page; 16 px / 1.65 in reading columns |
| UI | 14 px / 500 | controls, list rows, card readings |
| Meta | 13 px / 400-500 | hour bar, legend, footer, labels |
| Caption | 12 px | ranks, chips, day dates |

`tabular-nums` on scores, hours and distances. Prose ≤ 65ch. Weight, not size, makes hierarchy.

## Space and shape

- 4 px grid: 4, 8, 12, 16, 24, 32, 48. Page gutter 24 px (16 px on phones).
- Radius: controls 8 px, panels 12 px, score chips and the chat toggle full pill. Nothing else.
- Shadow `--shadow-float` on list, card, chat panel, tooltip, chat toggle. No other shadows.

## Components

- **Utility strip** (`.sitenav`): 40 px, `--surface`, 13 px plain links; sections with no page
  are muted with "(em breve)", hidden on phones. Language toggle and repo link at right.
- **Header** (`.bar`): wordmark with the wave icon in accent, the one-line tagline beside it
  (under it on phones), controls at right (a 6-column grid on phones).
- **Control**: 36 px, 8 px radius, 1 px `--line-strong`, white, 14/500. Hover `--surface`.
  Pressed (`aria-pressed`, `aria-expanded`): `--accent-soft` fill, accent border and text.
  `:active` nudges 1 px down.
- **Area picker**: the control showing a two-letter code (FL, RJ, BA; `AREA_CODES` in `board.ts`), the full name in its title and accessible name.
- **Segmented** (day, language): a `--surface` track; the picked segment is white, raised.
- **Primary action**: accent fill, white text. One per surface (chat open, chat send).
- **Hour bar**: label, slider (accent), legend pushed right.
- **Panels**: white, 1 px `--line`, 12 px radius, `--shadow-float`; bottom sheets under 640 px.
- **Close buttons**: the control as a borderless 32 px square in `--muted`.
- **Beach marker**: a 16 px dot in its score colour, 2 px white ring, `#1d2733` rim; the selected
  beach is a 32 px badge with its score. No glyphs, halos or shadows. The legend draws the same dot.
- **Map**: Mapbox GL JS on the light `outdoors-v12` style (or `MAPBOX_STYLE`): sand, trails and relief read at a glance for beachgoers, zoom buttons top left (the layer rail takes the right), no
  rotation or pitch. Popups take the panel shape, without the arrow.
- **Layer rail** (`.flow`): Windy-style, top right of the map, in white glass; it scrolls on a map too short for it.
  Two toggles (praias, trilhas perto da costa) over a thin rule, then one round icon button per layer (vento, ondas,
  balneabilidade, satélite, temperatura do mar, anomalias, El Niño), no text: the word is the
  button's title and its screen-reader label. The four satellite layers are NASA GIBS rasters
  under the labels; El Niño zooms out to the Pacific and draws the Niño 3.4 box. For now only praias and balneabilidade are enabled: every other button (trilhas, vento, ondas, the four satellite layers, batimetria) is disabled at 45% opacity and titled "em breve", its code kept for when it ships; the map opens with no layer on, and a pressed layer button turns it off. The active one is in `--accent`; under them the
  active layer's key (ramp with 0 and max, or the fit/unfit dots) and its caption. Wind and waves are white particles over a
  field at 65% opacity (the light base map shows through), fading out 18 km past the last beach, with a thin dark coastline over
  it on Mapbox's own styles. Balneabilidade stops the particles, draws every sampling point in
  the area and dims the beach dots.
- **Icons**: Lucide line icons through `icon(name)` in `icons.ts` (ISC, `vendor/icons/LICENSE.lucide`),
  16 px, 1.75 stroke, in `--accent`; `aria-hidden` with the word next to it. Never emoji.

## Copy

Lowercase house style (with its exemptions in `style.css`). No em dash in visible copy: use a
colon, a semicolon, a comma or a period. At most one `·` per line, and only in compact metadata.

## Motion

Only state changes: colour and border 150 ms ease-out, the press 100 ms, all inside
`prefers-reduced-motion: no-preference`. No entrance animations. The one ambient motion is the
flow layer's particles, which are data (direction and speed); under `prefers-reduced-motion:
reduce` they are drawn once as still streaks.

## Not yet

A dark theme (page chrome and a dark base map such as Mapbox `dark-v11`). The map went light on
purpose: the audience is beachgoers, not forecasters, and a dark map read as too heavy for them.
