# DESIGN.md: marola's visual system

The map is a data product. The score colours, the numbers and the sources carry the page. The
chrome around them is ink: a dark frame that makes the light map the bright thing on the page, so
a visitor reads it in five seconds on a phone.

The look is "ink and sea". marola is a sibling of the owner's other sites, and these rules are
borrowed from <https://piabrota.art/style.css>: the ink ground and its steps (`--bg`, `--surface`,
`--raised`, `--line`, `--ink`, `--muted`), the one blue (`--sea`), the red and the green that read
on ink (`--emergency`, `--ok`), the three type families and their jobs, the pill control whose
border turns to the accent and lifts 1 px on hover, the segmented pill track, the status pill (a
dot and a word), the metric row (a big numeral over a small muted label), the uppercase eyebrow,
the `§ 01` counter and the one radial glow at the top left of the header. marola keeps what is its
own: the name, the "m" wave logo, the logo's cyan as the accent, the score colours and the data.

This file is the one source for tokens and components. `front/public/style.css` is the one
stylesheet: the map page, the static pages and the server pages all load it. Its `:root` block
holds every token, and the tables below list them with their values. `just design-check` fails
when the two differ (see [How a change is checked](#how-a-change-is-checked)).

Three parts of the code draw what a visitor sees:

- The map page is the Elm page: `front/src` (the views) and `front/js` (the MapLibre and WebGL
  glue, reached through `front/ports.js`).
- The static pages (about, support, contact, news, members, privacy, takedown, 404) are rendered
  by `back/pages` from Markdown. `back/pages/src/Marola/Pages/Layout.hs` is their head, top bar, page bar and
  footer.
- The study pages (`/submit`, `/studies`, `/studies/<id>`, `/account`, `/report/<id>`) are
  rendered by `back/server/src/Marola/Server/Views.hs` inside the same layout.

The page chrome and the map controls follow the rules below. A rule says what the CSS does now.
Where the code and a wish differ, the section [Known gaps](#known-gaps) says so.

## Principles

1. **Data first.** Colour on the page means a score. Chrome is ink and gray. One cyan accent marks
   what you can act on, and one blue fill marks the one primary action.
2. **One of everything.** One accent, one control shape, one radius scale. Three type families,
   each with one job: Fjalla One names things, Inter says things, JetBrains Mono measures things.
3. **Elevation only where it is real.** A panel that floats over the map gets a soft shadow.
   Nothing else on the page does.
4. **Dense but calm.** It is a tool that people check every day: small type with a clear
   contrast of family and weight, tight rows, wide gaps between groups.

## Colour

Every colour in a rule is a token below. A token
row has the token in backticks, then its value in backticks, as `:root` writes it. The check reads
these rows. Do not change a row without the same change in `:root`.

### Score

| Token | Value | Job |
|---|---|---|
| `--c70` | `#1b9e77` | score 70 to 100 (good); data only |
| `--c40` | `#e6ab02` | score 40 to 69 (fair) |
| `--c1` | `#d95f02` | score 1 to 39 (poor) |
| `--c0` | `#d7191c` | score 0, or water unfit by the agency |
| `--cna` | `#8c8c8c` | no data ("sem dados") |

### Neutral and accent

| Token | Value | Job |
|---|---|---|
| `--bg` | `#0B0D12` | page, top bar, tool row, the pressed layer button, ink text on a score colour |
| `--surface` | `#14171F` | panels, controls, tracks, footer, chat answers, release cards |
| `--raised` | `#1A1E28` | hover on a row, the raised segment |
| `--line` | `#2A303C` | hairlines, panel borders |
| `--line-strong` | `#3A4252` | control and field borders, the empty state's dashes, the "404" numeral |
| `--ink` | `#EDEFF3` | text, headings |
| `--muted` | `#9AA3B2` | secondary text, icons at rest |
| `--accent` | `#3DD6F5` | the logo's cyan: links, focus ring, pressed text and border, slider, the "you" marker |
| `--accent-hover` | `#8BE9FB` | hover on a link |
| `--accent-soft` | `rgb(61 214 245 / .12)` | pressed fill, the visitor's chat messages, member initials, the new API key |
| `--sea` | `#0B5FA5` | the one primary fill (chat toggle and send, the release tag, a reading page's primary pill and submit button), and the header's glow |
| `--sea-hover` | `#0E6DBB` | hover on the primary fill |
| `--on-fill` | `#ffffff` | text on `--sea` and on `--c0`; the white ring of a marker on the map |
| `--map-sea` | `#cfe6f1` | the map before the base map loads |
| `--emergency` | `#FF6B5E` | the emergency button's phone icon, and unfit or improper water text on ink |
| `--ok` | `#3FB950` | the "proper" water text on ink |
| `--warn` | `#E3B341` | the dot of the "not reviewed" status pill and the edge of its banner; never text, never a score |

### Glass

| Token | Value | Job |
|---|---|---|
| `--glass` | `rgb(11 13 18 / .88)` | ink glass: layer rail, key, zoom buttons, attribution, popups, emergency button |
| `--glass-hover` | `rgb(237 239 243 / .1)` | hover on a zoom button |
| `--glass-line` | `#2A303C` | border of glass |
| `--glass-ink` | `#EDEFF3` | text on glass |
| `--glass-muted` | `#9AA3B2` | secondary text on glass |
| `--glass-unfit` | `#FF6B5E` | unfit text on glass |

### Map layers

| Token | Value | Job |
|---|---|---|
| `--flow-wind-0` | `#5b6db3` | wind field and key ramp, step 0 of 5 (calm to 40 km/h) |
| `--flow-wind-1` | `#4a94a9` | wind field and key ramp, step 1 of 5 (calm to 40 km/h) |
| `--flow-wind-2` | `#4d9a6e` | wind field and key ramp, step 2 of 5 (calm to 40 km/h) |
| `--flow-wind-3` | `#8fa64a` | wind field and key ramp, step 3 of 5 (calm to 40 km/h) |
| `--flow-wind-4` | `#b5904a` | wind field and key ramp, step 4 of 5 (calm to 40 km/h) |
| `--flow-wind-5` | `#a8566a` | wind field and key ramp, step 5 of 5 (calm to 40 km/h) |
| `--flow-wave-0` | `#2f5a9e` | wave field and key ramp, step 0 of 5 (flat to 3 m) |
| `--flow-wave-1` | `#4a63b8` | wave field and key ramp, step 1 of 5 (flat to 3 m) |
| `--flow-wave-2` | `#6b55b3` | wave field and key ramp, step 2 of 5 (flat to 3 m) |
| `--flow-wave-3` | `#9150a8` | wave field and key ramp, step 3 of 5 (flat to 3 m) |
| `--flow-wave-4` | `#b4508c` | wave field and key ramp, step 4 of 5 (flat to 3 m) |
| `--flow-wave-5` | `#c86e6e` | wave field and key ramp, step 5 of 5 (flat to 3 m) |
| `--sst-0` | `#3b1d73` | sea temperature key ramp, after GIBS |
| `--sst-1` | `#2f5fb3` | sea temperature key ramp, after GIBS |
| `--sst-2` | `#33a3c8` | sea temperature key ramp, after GIBS |
| `--sst-3` | `#6cc46a` | sea temperature key ramp, after GIBS |
| `--sst-4` | `#f0d23c` | sea temperature key ramp, after GIBS |
| `--sst-5` | `#d9452b` | sea temperature key ramp, after GIBS |
| `--anom-cold` | `#2b5cb8` | anomaly key ramp, after GIBS |
| `--anom-mid` | `#f4f4f4` | anomaly key ramp, after GIBS |
| `--anom-warm` | `#c8322b` | anomaly key ramp, after GIBS |

### Shape and family

| Token | Value | Job |
|---|---|---|
| `--shadow-float` | `0 1px 2px rgb(0 0 0 / .3), 0 12px 32px -8px rgb(0 0 0 / .45)` | what floats over the map |
| `--r-control` | `999px` | controls, tracks, tags: a pill |
| `--r-panel` | `12px` | panels, cards, figures, popups, the key |
| `--r-inner` | `8px` | what sits inside a panel: the logo tile, the player's frame, a text field |
| `--display` | `"Fjalla One", "Arial Narrow", sans-serif` | names and numerals |
| `--sans` | `Inter, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif` | body and controls |
| `--mono` | `"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace` | hours, dates, distances, units, sources, section links |

### Type scale

| Token | Value | Job |
|---|---|---|
| `--fs-11` | `11px` | font size |
| `--fs-12` | `12px` | font size |
| `--fs-13` | `13px` | font size |
| `--fs-14` | `14px` | font size |
| `--fs-15` | `15px` | font size |
| `--fs-17` | `17px` | font size |
| `--fs-18` | `18px` | font size |
| `--fs-19` | `19px` | font size |
| `--fs-20` | `20px` | font size |
| `--fs-21` | `21px` | font size |
| `--fs-22` | `22px` | font size |
| `--fs-24` | `24px` | font size |
| `--fs-28` | `28px` | font size |
| `--fs-display` | `clamp(36px, 5vw + 12px, 56px)` | font size |
| `--tr-11` | `.005em` | tracking that goes with that size |
| `--tr-12` | `0em` | tracking that goes with that size |
| `--tr-13` | `-.003em` | tracking that goes with that size |
| `--tr-14` | `-.006em` | tracking that goes with that size |
| `--tr-15` | `-.009em` | tracking that goes with that size |
| `--tr-17` | `-.013em` | tracking that goes with that size |
| `--tr-18` | `-.014em` | tracking that goes with that size |
| `--tr-19` | `-.016em` | tracking that goes with that size |
| `--tr-20` | `-.017em` | tracking that goes with that size |
| `--tr-21` | `-.018em` | tracking that goes with that size |
| `--tr-22` | `-.018em` | tracking that goes with that size |
| `--tr-24` | `-.02em` | tracking that goes with that size |
| `--tr-28` | `-.021em` | tracking that goes with that size |
| `--tr-display` | `-.022em` | tracking that goes with that size |
| `--tr-fjalla` | `.01em` | tracking of Fjalla One at every size |
| `--tr-mono` | `0em` | tracking of JetBrains Mono at every size |
| `--tr-eyebrow` | `.16em` | tracking of an uppercase eyebrow |

The score colours are data: dots, chips, legend. A change needs a MIP note. The flow ramps are data
too. They follow Windy's muted scales, which visitors already read. A score is never told by the
field's colour alone, because the beach dots sit on top with a ring, and the selected one with its
number.

Some colours are not in `:root`, because a CSS variable does not reach them:

- The beach dot rim `#1d2733` and its white ring are SVG attributes in `front/src/MapView.elm`.
- The selected trail line and the Niño 3.4 box use `#1d2733` in `front/js/maplibre_ffi.mjs`.
- The score colours and the flow ramps appear again as hex in `front/src/Config.elm`, where
  MapLibre and the WebGL layer need them as values.
- The base map's colours are values in `scripts/basemap_style.mjs`, which writes them into
  `front/public/map/style.json`; MapLibre reads a style, not CSS ("The base map" below).
- piabrota's eye keeps its own four fills (`#BC2318`, `#F7F3EA`, `#2E9E4F`, `#0B0D12`) as SVG
  attributes in `front/src/View/Nav.elm`.
- The logo is `front/public/favicon.svg`, drawn as a CSS background on a white tile.
- The page's `theme-color` meta is `#0B0D12`.

Shadows use `rgb(0 0 0 / alpha)`. The header's glow is `color-mix` of `--sea`. They are not hex and
the check does not read them.

### The base map

The map is light under the ink chrome, and quiet, so that the beach dots, the flow ramps and the
satellite keys carry the colour. Its style is generated (`node scripts/basemap_style.mjs`) from
Protomaps' light flavor with the values below; change them there, never in `style.json`.

| Part | Value | Job |
|---|---|---|
| water, background | `#cfe6f1` | the sea, lakes and the ground behind every tile: `--map-sea`, so a tile that is still loading reads as water |
| earth | `#f4f2ec` | land |
| beach | `#f1dc98` | sand of a beach, the strongest fill on the map after the roads: this is a beach map |
| sand | `#f1e4b4` | dunes and other sand |
| park, wood, scrub | `#dcead3` to `#c3dfb9` | green, in two steps by zoom |
| buildings | `#e4e0d8` | building footprints, from zoom 14 |
| roads | `#ffffff` on a `#d6d0c3` or `#dcd7cc` casing | every road but a motorway |
| motorway | `#fbe7b0` on `#dfc98c` | the one coloured road |
| boundaries | `#9aa3ad` | country and state lines |
| city label | `#1d2733` with an earth halo | 13.5:1 on earth; the same ink as the marker rim |
| neighbourhood label | `#5b6672` with an earth halo | 5.2:1 on earth |
| road label | `#59626e`, `#6b7480` with a white halo | 6.2:1 and 4.7:1 on white |
| state, country label | `#7d8792`, `#59626e` | large upper-case text; the state name is 3.3:1 on earth |
| sea label | `#4d7a9c` italic | 3.5:1 on water; large, spaced text |
| beach label | `#7a5c12` italic with a white halo | a beach's name, from zoom 12; 5.6:1 on earth |

The labels are Noto Sans (Regular, Medium, Italic), drawn by MapLibre from glyph files, not Inter:
a map label is the map's voice, not the page's. A name is shown in Portuguese when the data has
one. The style has no icon: no POI, no road shield, no town dot.

## Contrast

Ratios are WCAG 2.x relative luminance, computed from the values in the tables. The rule: text is
at least 4.5:1 on its background. A control's border or an icon that carries meaning alone is at
least 3:1.

| Text | On | Ratio | Result |
|---|---|---|---|
| `--ink` | `--bg` | 16.88:1 | pass |
| `--ink` | `--surface` | 15.56:1 | pass |
| `--ink` | `--raised` | 14.47:1 | pass |
| `--muted` | `--bg` | 7.64:1 | pass |
| `--muted` | `--surface` | 7.04:1 | pass |
| `--muted` | `--raised` | 6.55:1 | pass |
| `--muted` at 80% (a section with no page yet) | `--bg` | 5.23:1 | pass |
| `--accent` | `--bg` | 11.23:1 | pass |
| `--accent` | `--surface` | 10.35:1 | pass |
| `--accent` | `--accent-soft` over `--surface` (a pressed control) | 8.15:1 | pass |
| `--accent-hover` | `--bg` | 14.02:1 | pass |
| `--accent-hover` | `--surface` | 12.92:1 | pass |
| `--on-fill` | `--sea` (the primary fill) | 6.57:1 | pass |
| `--on-fill` | `--sea-hover` | 5.35:1 | pass |
| `--emergency` | `--bg` | 6.96:1 | pass |
| `--emergency` | `--surface` (unfit water text) | 6.41:1 | pass |
| `--ok` | `--surface` (the "proper" water text) | 7.05:1 | pass |
| `--accent` | `--raised` | 9.63:1 | pass |
| `--ink` | `--accent-soft` over `--bg` (the new API key) | 13.73:1 | pass |
| `--warn` | `--surface` (the status dot, the banner's edge; not text) | 9.21:1 | pass |
| `--warn` | `--bg` (the status dot in the banner) | 9.99:1 | pass |
| `--line-strong` | `--bg` (the "404" numeral, decoration) | 1.93:1 | fail |
| `--glass-ink` | `--glass` over a white map | 12.47:1 | pass |
| `--glass-muted` | `--glass` over a white map | 5.64:1 | pass |
| `--glass-unfit` | `--glass` over a white map | 5.14:1 | pass |
| `--accent` | `--glass` over a white map (a pressed layer button is on `--bg`: 11.23:1) | 8.29:1 | pass |
| `--bg` | `--c70` (a score chip) | 5.74:1 | pass |
| `--bg` | `--c40` (a score chip) | 9.43:1 | pass |
| `--bg` | `--c1` (a score chip) | 5.17:1 | pass |
| `--bg` | `--cna` (a score chip) | 5.78:1 | pass |
| `--on-fill` | `--c0` (a score chip) | 5.19:1 | pass |
| `--line-strong` | `--surface` (a control border) | 1.78:1 | fail |
| `--accent` | `--map-sea` (the "you" marker with no ring) | 1.34:1 | fail |

A score chip prints its number in ink (`--bg`) on its band colour, and in white on the red, so all
five pass. The "404" numeral is decoration behind the sentence "not found", which is the h2 in
`--ink`; it is not the only carrier of anything. The numbers come from a small Node script that implements the WCAG formula, with a
colour that has an alpha composited over its ground first. The two failing rows are answered in
[Known gaps](#known-gaps): a control is told by its fill and its text too, and the "you" marker
has a white ring and an ink rim because its cyan does not read on the map alone.

## Type

Three families, all self-hosted as latin woff2 under `front/public/vendor/fonts/`, never from a
CDN (the CSP is `font-src 'self'`). All three are under the SIL Open Font License 1.1, and each
licence file sits beside its font and names the npm package and version it was copied from.

| Family | File | Job |
|---|---|---|
| Fjalla One 400 (`--display`) | `fjalla-one-latin-400-normal.woff2` | the wordmark, page titles and section heads of the reading pages, panel titles, beach names in the list and the card, member names, study titles, score and metric numerals, the emergency numbers. Line-height 1 to 1.2, tracking `--tr-fjalla`, never bold: the family has one weight |
| Inter, variable (`--sans`) | `inter-latin-wght-normal.woff2` | body text and controls |
| JetBrains Mono, variable 100 to 800 (`--mono`) | `jetbrains-mono-latin-wght-normal.woff2` | hours, dates, distances, units, sources, the status and credit lines, the section links, the legend, the language switch; on the reading pages the `§ 01` counters, a post's date and reading time, hashes, tags, status pills, inline `code`. Weight 400, or 500 for the hour label |

Sizes are `--fs-*` tokens. For Inter, each size has a `--tr-*` tracking that follows Inter's dynamic
metrics (`-0.0223 + 0.185 * e^(-0.1745 * px)` em): small text stays open, large text tightens. A
rule that sets a size sets its tracking too, because `letter-spacing` inherits as a length. Fjalla
and the mono face take `--tr-fjalla` and `--tr-mono` at every size.

| Role | Size token | Family / size / weight / line-height | Where |
|---|---|---|---|
| Display | `--fs-display` | Fjalla, 36 to 56 px (`clamp`) / 1.04 | the first h2 of a reading column (a post's title in its card is 30 to 42 px, a study's title 28 to 40 px) |
| Section | `--fs-28` | Fjalla, 28 px / 1.15 (24 px on phones, `--fs-24`), after a mono `§ 01` counter in `--accent` | h2 in a reading column |
| Card title, metric | `--fs-28` | Fjalla, 28 px / 1.1 (24 px on phones) | the beach card's h2 and its four numerals |
| Wordmark | `--fs-24` | Fjalla, 24 px / 1 (22 px on phones, `--fs-22`) | top bar |
| Score, panel title | `--fs-22` | Fjalla, 22 px / 1 | the list's score chip, the trails panel title, the emergency numbers |
| Lede | `--fs-21` | Inter, 21 px / 400 / 1.45, `--muted` (19 px on phones, `--fs-19`) | the paragraph under a page title |
| Beach name | `--fs-19` | Fjalla, 19 px / 1.15 | a list row |
| Quote | `--fs-19` | Inter, 19 px / 400 / 1.5 | a short cited quote in a reading column |
| Reading | `--fs-17` | Inter, 17 px / 400 / 1.65 (15 px on phones); h3 at 600 / 1.4 | the body of every page in a reading column |
| Body | `--fs-15` | Inter, 15 px / 400 / 1.5 | the page default, inline `code` |
| Card reading | `--fs-14` | Inter, 14 px / 400 | card rows, the lore, the emergency rows |
| UI | `--fs-13` | Inter, 13 px / 500 | controls, the tagline, popups, the card's aspects |
| Eyebrow | `--fs-12` | Inter, 12 px / 600, uppercase, tracking `--tr-eyebrow`, `--accent` | the line above a page title |
| Caption | `--fs-12` | mono or Inter, 12 px | section links, the hour label, metric labels, footer folds, a post's date, a study's facts |
| Fine | `--fs-11` | mono, 11 px | the legend, list and card metadata, the status and credit lines, eyebrows, map attribution |

Headings get `text-wrap: balance` and `optimizeLegibility`. Reading paragraphs get `text-wrap:
pretty`. The page has `font-kerning: normal`. Scores, hours and distances use `tabular-nums`.
The reading column is 44 rem, about 80 characters of the 17 px reading size. The area code in the
picker keeps a wider tracking of +0.02em.

The map page is a dense tool. Its hierarchy comes from the three families, then from size: a
Fjalla name or numeral is what the eye lands on, Inter explains it, mono dates and measures it.

## Space and shape

- 4 px grid: 4, 8, 12, 16, 24, 32, 48. The page gutter is 24 px (16 px on phones).
- Radius: controls are pills (`--r-control`, 999 px): every button, toggle, select, tag, chip and
  segmented track. Panels, cards, popups and the key are 12 px (`--r-panel`). What sits inside a
  panel is 8 px (`--r-inner`). Smaller radii: 4 px for inline `code` and a key ramp, 10 px for a
  chat message. A circle is the layer button, a close button, the "you" marker and a member's mark.
- Shadow `--shadow-float` on what floats over the map: list, card, chat panel, emergency panel,
  player, popup, glass controls, chat toggle. No other element has a shadow.
- Hover on a control: the border turns to `--accent` and the control lifts 1 px. A row hovers to
  `--raised`.

## Focus, target size and motion for the keyboard

- Focus ring: `:focus-visible` shows a 2 px `--accent` outline with a 2 px offset (1 px offset on a
  text field). Never remove it. Never replace it with a colour change alone. `--accent` on
  `--bg` is 11.23:1.
- Minimum target: 24 px by 24 px (WCAG 2.2, criterion 2.5.8), and no control is smaller. A
  control is 34 px high, 36 px on a phone (28 px inside a segmented track, 22 px inside the 28 px
  language switch, 28 px for a footer fold on a desktop).
  A map control is 32 px (the emergency button, a close button, a layer button on a phone). What a
  thumb taps first on a phone is 44 px: the emergency numbers and the footer folds.
- Every control has a name a screen reader can read. An icon-only button keeps its word in a
  visually hidden `span` and in `title`.
- A state is never told by colour alone: a pressed control has `aria-pressed` or `aria-expanded`
  and a different fill; a disabled layer has `disabled` and a title that says it is not built yet ("em breve" in pt-BR).

## Components: the map page

- **Top bar** (`header.top`): one bar, `--bg`, 48 px, with the glow of `--sea` at its top left. In
  order: the brand (`.brand`), the sections (`nav.sitenav`), the tools (`.navtools`). The brand is
  the logo tile (`span.logo`: `favicon.svg` on a white 30 px tile with an 8 px radius), "marola" in
  Fjalla inside the `h1`, then piabrota's eye (`a.piabrota`, 18 px). The sections are quiet mono
  links, 12 px, `--muted`, `--ink` on hover, `--accent` for the current page. A section with no
  page yet is dimmer text with "(em breve)". The tools are the language switch, LinkedIn and the
  repo link, pushed to the right. Under 1100 px the sections take their own row. On phones that row
  hides the muted section and the links to members, studies, research and contribute (about links
  them), and it scrolls sideways before it wraps.
- **Tool row** (`div.bar`): under the top bar, `--bg`. Row one: the controls at left (area, the
  Instagram link, days, near me, spotify, list), the legend at right. Row two: the hour label, the
  slider (up to 30 rem), and the one-line tagline at the right. Under 900 px the tagline is kept
  for screen readers only and the legend takes a third row that scrolls sideways. On phones the
  controls are one row that does not wrap, and the action buttons keep only their icon.
- **Control**: a 34 px pill (36 px on phones), 1 px `--line-strong` border, `--surface`, Inter 13 px
  / 500, its icon in `--muted`. Hover: `--accent` border, the icon in `--accent`, 1 px lift.
  Pressed (`aria-pressed`, `aria-expanded`): `--accent-soft` fill, `--accent` border and text.
  Disabled layer buttons are at 50% opacity.
- **Area picker** (`#area`): a `select` that shows the two-letter code of the area (for example FL)
  in mono, with the full name in its accessible name. It has no case change.
- **Segmented** (the day buttons, the language switch): a `--surface` pill track with a 1 px
  `--line` border. The picked segment is `--raised` with a 1 px `--line-strong` border and `--ink`
  text. The dates and the language codes are mono.
- **Primary action**: `--sea` fill, white text, one per surface: the chat toggle and the chat
  send button.
- **Emergency button** (`#sos`): a map control in `--glass`, a 32 px pill, 13 px, Lucide's phone
  icon in `--emergency`, at the top centre of the map, above every panel (z-index 1001). Its panel
  is 18 rem wide under the button, on `--surface`, titled in Fjalla. Under 641 px it is a bottom
  sheet. The numbers are 193, 190, 192, 185 and 199, each a `tel:` row of at least 44 px with the
  number in Fjalla 22 px, then a 12 px note. The panel fades in 150 ms. It comes from Carlos
  Toledo's swell-floripa (#76).
- **Hour bar** (`#hourbar`): its three children are laid out by the tool row's grid. The label is
  mono 12 px / 500. The slider has `accent-color: --accent`.
- **Legend** (`.legend`): status pills, each a band dot and its range or word in mono 11 px, on
  `--surface` with a 1 px `--line` border. The hover hint shows from 1400 px.
- **Panels** (`.list`, `.card`): `--surface`, 1 px `--line`, `--r-panel`, `--shadow-float`. Under
  641 px they are bottom sheets. The list is 22 rem wide on a desktop, the card 26 rem.
- **List row** (`.list ol li`): a grid. The rank as a mono counter (`01`, `02`), then the beach
  name in Fjalla 19 px (`.name`) over a mono line with the hour, the distance and the water status
  (`.meta`), then the score at the right edge (`.score`): a pill in the band colour with the number
  in Fjalla 22 px, ink on four bands and white on the red.
- **Beach card** (`.card`): the name in Fjalla 28 px; the headline (the score as a small band pill
  and the hour in mono); the metric row; the aspects grid of the tooltip; then the rows of
  readings, each label in mono 11 px.
- **Metric row** (`.metrics`): four cells (`.metric`), score, wind, waves and water temperature at
  the hour on show. Each is a Fjalla 28 px numeral with its unit in mono 11 px, over a 12 px muted
  label. The score has its band dot before it. A beach dark at that hour shows dashes.
- **Trails panel** (`.list.trails`): the title in Fjalla 22 px, each bairro as an uppercase eyebrow
  (Inter 600, 11 px, `--tr-eyebrow`), each route a full-width row with its difficulty as a small
  band pill, its name, and its length in mono at the right. The picked route takes `--accent-soft`.
  The foot (source, IBGE code) is mono 11 px.
- **Player** (`#player`): the playlist's frame in a `--surface` panel that hangs under the tool
  row at the right, with a mono link to open it in Spotify.
- **Close button**: the control as a borderless 32 px circle in `--muted`, `--raised` on hover.
- **Beach marker** (`.wave`): a 16 px dot in its band colour, a 2 px white ring, a `#1d2733` rim. The
  selected beach is a 32 px badge with its score number. A past hour keeps the dot at 45% fill
  opacity with a dashed ring. No glyphs, halos or shadows. The legend draws the same dot at 8 px.
- **Water-sampling marker** (`.wpoint`): Lucide's droplet, 18 px (22 px on the water layer), filled
  with the point's status (`--c70` proper, `--c0` unfit, `--cna` no classification), with a
  `--bg` rim and a white (`--on-fill`) stroke, so a sampling point never reads as a beach. On the water layer
  the beach dots drop to 40% opacity.
- **"You" marker** (`.here`): a 14 px `--accent` dot with a 2 px white ring and a 1.5 px ink rim.
- **Map**: MapLibre GL JS 6.17.0, self-hosted under `vendor/maplibre/`, on the site's own style
  (`Config.styleUrl`, `/map/style.json`), which stays light: see "The base map" under Colour. Zoom buttons at the top left (the layer rail takes
  the right), in ink glass; MapLibre draws their icons as dark images, so the CSS inverts them.
  The attribution is 11 px, bottom right, in ink glass: "© OpenStreetMap" and "Protomaps", each a
  link. The `--map-sea` colour shows until the tiles load, and it is the style's water, so the
  page's ground and the sea are one colour.
- **Popups** (`.maplibregl-popup`): the panel shape in ink glass, 13 px, no arrow, no pointer
  events. The beach popup (`.aspects`) has its head in Fjalla 17 px over a two-column grid of
  readings, up to 22 rem wide. In the beach card the same grid shows without its head.
- **Layer rail** (`.flow`): at the top right of the map, in glass, scrolls on a map too short for
  it. Order: two toggles (beaches, trails), the trail-list button, a 1 px rule, then one round
  36 px icon button per layer (wind, waves, bathing water, clouds, sea temperature, anomaly,
  El Niño) and bathymetry. No button shows text: the word is the button's `title` and its hidden
  label. In the current build only the bathing-water layer is enabled (`Config.enabledLayers`).
  The other layer buttons are disabled at 50% opacity and titled "em breve". The map opens with no
  layer on, and a pressed layer button turns it off. The pressed button is a solid `--bg` circle
  with an `--accent` ring and icon.
- **Layer key** (`.flowkeys`, `.flowkey`): at the bottom left, in glass, 13 rem wide (7.5 rem on
  phones, where the caption hides). A ramp 8 px high with its two ends in mono, or the fit and unfit dots,
  then a caption.
- **Flow layer** (wind and waves, `flow_layer_ffi.mjs`): a WebGL layer. The field is drawn at 65%
  opacity, so the light base map shows through, and particles run over it. Its edge fades. Under
  `prefers-reduced-motion: reduce` the particles are drawn once as still streaks. It is built, but
  its layer buttons are disabled in the current build.
- **Footer** (`.footer`): `--surface`. The status line (`#status`: freshness and linked sources)
  is mono 11 px and always shows. The day's sea lore and the score note fold behind compact pills
  (28 px, 12 px; on a phone 44 px, 14 px, with the sign in a 20 px `--accent` circle). The plus
  turns into a minus. They are closed by default. Open, a control takes the pressed look and the
  map keeps its height. A third control, "artistas locais", is a placeholder: muted,
  `aria-disabled`, titled "em breve". The footer ends with the credit line (`p.credit`), mono
  11 px: who makes marola, marola-dev, linked to the members page, and piabrota, linked to piabrota.art,
  the last one with the eye at 13 px. From 840 px the status and the credit sit at the left and
  the controls at the right. Narrower, the controls take their own row between the two lines.
- **Icons**: Lucide line icons (ISC, `vendor/icons/LICENSE.lucide`) through `Icons.icon` in
  `front/src/Icons.elm`. 16 px, 1.75 stroke, `--muted` at rest (`--accent` on a hovered or pressed
  control), `aria-hidden`, with the word next to it. Never emoji.

## Components: pages and forms

The static pages (`back/pages`) and the study pages (`back/server`) share the map page's chrome and
one reading column. They carry no script (see [No inline style, no script on content
pages](#no-inline-style-no-script-on-content-pages)). Each layout mirrors `View/Nav.elm` and
`View/Footer.elm` class for class.

- **Top bar** (`header.top`): the same as the map page's. The wordmark is a link to the map
  (`.brand h1 a`). The language switch is two plain links to the same page in each language.
- **Page bar** (`div.bar.pagebar`): where the map page has its tool row. One pill, "back to the
  map", with a mono arrow drawn by CSS, and the tagline at the right (hidden to the eye under
  900 px, like on the map page). There is no area picker and no day buttons.
- **Reading column** (`main.about > *`): 44 rem wide, centred, 17 px / 1.65 (15 px on a phone).
  `main` grows, so the footer sits at the foot of a short page. `main` also carries `p-<slug>`
  (`p-news`, `p-support`, `p-404`, `p-studies`), which is how the style sheet tells one page from
  another; a study's own page has none, because its address carries its id.
- **Eyebrow** (`p.eyebrow`, after piabrota.art's `.eyebrow`): "marola · " and the section's nav
  label, uppercase Inter 600 at 12 px, tracking `--tr-eyebrow`, `--accent`. The layout writes it
  above the article for a page of a nav section, of privacy and of takedown; the server writes it
  inside the article for submit, account, report and the message pages. The 404 page has none.
- **Title and lede**: the first `h2` of an article is the display title in Fjalla. A `p.lede`
  under it is 21 px in `--muted` (18 px on a phone).
- **Section head**: every later `h2` has a hairline above it and a mono counter before it, `§ 01`,
  `§ 02`, in `--accent` (after piabrota.art's `.sec-n`). The counter is a CSS counter that each
  article resets, so the Markdown carries no number. `h3` is Inter 600 at the reading size.
- **Inline code**: mono at .86 em, `--raised` fill, 1 px `--line`, 6 px radius, no case change,
  and it wraps anywhere, so a SHA-256 of 64 characters stays inside a 390 px column. `pre` and
  `table` have rules (a `--surface` block with a hairline; a mono header row and hairline rows),
  though the Markdown of today's pages makes neither.
- **Quote** (`blockquote`): a 2 px `--accent` rule at the left, 19 px text, the source in mono
  12 px `--muted`.
- **Figure**: the image is a link to itself in a 12 px hairline frame that turns `--accent` on
  hover; the caption is mono 12 px `--muted`. The umbrella diagram on the about page is drawn on
  its own dark ground (`#020617`), so it needs no light plate.
- **Definition list** (`dl`): terms in mono 12 px `--muted` at the left, their meaning at the
  right; one column on a phone. Used for the AI levels on `/submit` and the facts of a hidden
  study.
- **Card**: `--surface`, 1 px `--line`, `--r-panel`, no shadow. The cards are: a news post
  (`.p-news article.about-body`, with its title at 30 to 42 px, its date and reading time in mono
  under the title, then the lede), a release card inside a post (`.release`, on `--bg` so it reads
  inside the post's card, the tag a `--sea` pill in mono), a member (`.member`), a study
  (`.study`), a funding channel (the list items of `.p-support`), a panel (`.panel`, the login
  prompt of `/submit`) and the account's "logged in as" row (`.who`).
- **Member card** (`ul.members > li.member`): a grid of cards, two across in the column and one on
  a phone. A 48 px circle (the avatar, or the initials in Fjalla, `--accent` on `--accent-soft`),
  the name in Fjalla 20 px, the affiliation in `--muted` 14 px, the roles and the links in mono
  11 px. The links are `--ink` with no underline until hovered. Names wrap anywhere.
- **Funding channel** (`.p-support .about-body li`): the channel's name in Fjalla 22 px across the
  whole card, with a mono arrow at the right; a channel that is not open yet is `--muted` with its
  "soon" in mono.
- **Status pill** (`span.status`, after piabrota.art's `.status`): a dot and a word in mono 11 px
  in a hairline pill. `.status.warn` has the `--warn` dot and says "sem revisão" or "not
  reviewed"; `.status.off` is `--muted` and marks a hidden study or a revoked key.
- **Notice banner** (`p.notice[role="note"]`): the "not reviewed" pill, then the sentence "Not
  reviewed. Not medical advice.", in a `--surface` card whose edge is `--warn` mixed 45% into
  `--line`. It is under the title of the study list and of every study.
- **Tag** (`span.tag`): a study's area and topic, mono 12 px in a hairline pill.
- **Facts line** (`p.meta`, `p.post-date`): mono 12 px `--muted`, tabular numerals: a post's date
  and reading time; a study's pill, tags, date and the first 12 characters of its hash; the full
  SHA-256 and who sent it on the study's page.
- **Pill link** (`a.pill`): a link that acts takes the shared control's shape. `a.pill.primary`
  and a form's submit button take the `--sea` fill with `--on-fill` text (6.57:1): one filled
  action per page (submit a study, log in with GitHub, open the PDF, send). The filter button, the
  account's row buttons and "older" stay plain pills.
- **Study card** (`ul.studies > li.study`): the title in Fjalla 22 px as a link in `--ink`
  (`--accent` on hover), the authors in `--muted`, then the facts line. Titles and names keep the
  case their author gave them and wrap anywhere.
- **Empty state** (`p.empty`): a dashed `--line-strong` frame with one mono sentence, when a list
  of studies has no row.
- **Study page** (`/studies/<id>`): the title as `h2.study-title` (28 to 40 px, the author's
  letter case), the banner, the authors (an ORCID is a mono link with `rel="noopener noreferrer
  nofollow ugc"`), the tags and the date, then the sections as h3: abstract, sources, code,
  licence, AI declaration, the file. "Open the PDF" is the primary pill, and "report this study" a
  plain one.
- **Tombstone** (a hidden study): the title, a `.status.off` pill, one sentence, and a `dl.facts`
  with the id, the SHA-256, the dates and the reason. No text of the study, no link to the file,
  and `noindex`.
- **Account page**: the `.who` card (the login in bold, the log out button), then `ul.rows`: one
  hairline row per key or study, its text at the left and its one action at the right (revoke,
  withdraw) or a `.status.off` pill. A new key is shown once in `p.key`: ink on `--accent-soft`
  with an `--accent` border (13.73:1), wrapping anywhere. Deleting the account is
  `form.contact.danger`: a frame whose edge is `--emergency` mixed 45% into `--line`, and a button
  with an `--emergency` border and text (6.96:1 on `--bg`) and no fill.
- **Form** (`form.contact`): a grid with an 18 px gap, at most 34 rem wide. The same class styles
  the contact form, the submit form, the report form, the account's confirmation and the filters.
- **Form field** (`label` in `form.contact`): the label text is a `span` in Inter 600 at 13 px,
  the hint a `small` in `--muted` under it, then the control. Text fields and text areas: 15 px,
  9 px 12 px padding, `--surface` fill, 1 px `--line-strong` border, `--r-inner`, no case change.
  Hover turns the border `--muted`; focus draws the 2 px `--accent` ring with a 1 px offset and
  turns the border `--accent`. A `select` is the shared pill control, at least 16 rem wide (the
  whole row on a phone). A text area resizes vertically. Disabled and read-only fields are not
  used.
- **Filters** (`form.contact.filters`, `/studies`): a `GET` form in a hairline frame, the two
  selects side by side under mono labels and a plain "filter" pill at the end of the row.
- **Error text** (`p.field-error[role="alert"]`): `--emergency` at 13 px under the field it names
  (6.96:1 on `--bg`), or above the submit button for an error of the request. The markup sets no
  `aria-invalid` and no `aria-describedby`. See [Known gaps](#known-gaps).
- **File input**: the field's frame, with the browser's button drawn as a `--raised` pill.
- **Checkbox** (the "rights" field): 18 px, `accent-color: var(--accent)`, then the sentence and
  two links.
- **Honeypot** (the contact and report forms): a text input with `hidden`, `tabindex="-1"`,
  `aria-hidden="true"` and `autocomplete="off"`. It is never visible.
- **Pager** (`/studies`): one plain pill, "Mais antigos" or "Older", under the list. It carries
  `before`, `area` and `topic` in its query. There is no numbered pager and no link back.
- **404** (`.p-404`): the numeral "404" in Fjalla, 96 to 176 px, in `--line-strong`, drawn by CSS
  behind the title "not found" and its sentence with the two ways out.
- **Message page** (a refusal or a failure from the server): the eyebrow "marola", the title, and
  one sentence as the lede.
- **Footer on a content page**: the same `.footer` as a plain block. The privacy sentence, then
  three links, "submit", "privacy", "takedown", with a literal `·` between them, then the credit
  line (`p.credit`) as on the map page, its "crew" link going to the members page in the page's
  language. Links are `--accent` on `--surface` (10.35:1).

## Copy

Lowercase house style, set once with `text-transform: lowercase` on `body`. The exemptions are in
`style.css`: beach names, provider names, the agency's verbatim PROPRIA and IMPROPRIA verdict, text
in `code`, and the text of a form field. No em dash in visible copy: use a colon, a semicolon, a
comma or a period. At most one `·` per line, and only in compact metadata.

## Motion

Only state changes: colour, border and the 1 px hover lift, 150 ms ease-out. All of it sits inside
`prefers-reduced-motion: no-preference`. A footer panel and the emergency panel fade in under their
control (150 ms, 4 px) and close at once. No entrance animations. The one ambient motion is the flow
layer's particles, which are data (direction and speed). Under `prefers-reduced-motion: reduce`
they are drawn once as still streaks.

## No inline style, no script on content pages

A content page has no `<script>` and no `style=` attribute. The server sends a Content-Security-
Policy with `script-src 'self'` and `style-src 'self'` (the header is built in `back/server/src/Marola/Server/Security.hs`
and the map page repeats it in a meta tag). An inline script or an inline style is blocked by the
browser, so the markup must not rely on one. A colour that depends on data, such as a band, is a
class (`c70`, `f-c70`), never a `style` value. The only scripts are the module of the map page and
MapLibre's worker, both from `'self'`. A page that needs behaviour is a form that posts to the server.

## How a change is checked

`just design-check` runs `scripts/design_check.js` (Node, no packages) after its own self-test. It
reads this file and `front/public/style.css` and fails when:

1. a custom property in `:root` is not in a token table here;
2. a token row here is not in `:root`, or has a different value;
3. `style.css` has a hex colour outside `:root`, other than the entries of the script's `ALLOW` list.
   The script also fails when an `ALLOW` entry no longer occurs, so the list can only shrink. It is
   empty now: every colour in a rule is a token.

`just quality` runs it. The check does not look at the prose, at the contrast table or at the
components. When you change a colour, recompute the contrast rows by hand and update them. When you
add a component, add its section here.

Layout is not in that check, because the repo's stub DOM has no layout. `scripts/nav_measure.sh`
loads every static page at 390 and 375 px in a real Chromium and fails when the sections row (`.sitenav`) is
wider than the screen. Run it by hand after a change to the top bar (it is not in `just quality`).

## Known gaps

The code and this file disagree with the rules above in these places. Each is a debt, not a
decision.

- **Control borders** are `--line-strong` at 1.78:1 on `--surface`, below the 3:1 for a boundary.
  The control is also told by its fill, its text and its icon.
- **The accent on the light map**: `--accent` on the map's water is 1.34:1, so nothing cyan sits
  on the map without an ink or white edge (the "you" marker has both).
- **Two layouts**: `back/pages/src/Marola/Pages/Layout.hs` and `back/server/src/Marola/Layout.hs`
  are two copies of the same chrome, and `front/src/View/Nav.elm` is a third. A change to the top
  bar or the credit line is made three times.
- **A page title has one tone**: piabrota.art's titles are two-tone (a first clause in `--ink`,
  the rest in `--muted`). A title here is one line of Markdown or one study title, with no markup
  to split it, so it is all `--ink` and the muted lede under it carries the second tone.
- **The news page is every post in full**, each in its card, newest first. There is no index of
  posts and no page per post.
- **The logo tile is a CSS background**, not inline SVG: `favicon.svg` weighs 110 kB. It is
  decoration beside the word "marola", and it does not show if images are blocked.
- **The marker's number** for `--c40` has a `dark` class that no CSS rule uses, and the selected
  badge prints its number in Inter, not Fjalla.
- **The player covers the top of the layer rail** while it is open on a desktop.
- **No rule** for these classes, which the markup emits: `trail-card` and `trail-note`. They
  render with the styles they inherit.
- **No `aria-invalid`** and no `aria-describedby` on a field with an error.
- **Two `·` per line** in the footer links and in the study row, against the copy rule above.

## Not yet

- **A light theme.** The chrome is ink and the base map is light, in every colour scheme. There
  is no `prefers-color-scheme` rule; `html` declares `color-scheme: dark` so the browser's own
  controls (the select menu, the slider track, scrollbars) match the ink.
- **Print.** There is no `@media print` rule. A printed page is the screen page.
