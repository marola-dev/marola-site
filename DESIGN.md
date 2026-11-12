# DESIGN.md: marola's visual system

The map is a data product. The score colours, the numbers and the sources carry the page. The
chrome around them stays quiet, neutral and consistent, so a visitor reads it in five seconds on a
phone.

This file is the one source for tokens and components. `front/public/style.css` is the one
stylesheet: the map page, the static pages and the server pages all load it. Its `:root` block
holds every token, and the tables below list them with their values. `just design-check` fails
when the two differ (see [How a change is checked](#how-a-change-is-checked)).

Three parts of the code draw what a visitor sees:

- The map page is the Elm page: `front/src` (the views) and `front/js` (the MapLibre and WebGL
  glue, reached through `front/ports.js`).
- The static pages (about, support, contact, news, members, privacy, takedown, 404) are rendered
  by `back/pages` from Markdown. `back/pages/src/Marola/Pages/Layout.hs` is their head, nav, header and footer.
- The study pages (`/submit`, `/studies`, `/studies/<id>`, `/account`, `/report/<id>`) are
  rendered by `back/server/src/Marola/Server/Views.hs` inside the same layout.

The page chrome and the map controls follow the rules below. A rule says what the CSS does now.
Where the code and a wish differ, the section [Known gaps](#known-gaps) says so.

## Principles

1. **Data first.** Colour on the page means a score. Chrome is neutral gray. One blue accent marks
   what you can act on.
2. **One of everything.** One accent, one control style, one radius scale, one type family.
3. **Elevation only where it is real.** A panel that floats over the map gets a soft shadow.
   Nothing else on the page does.
4. **Dense but calm.** It is a tool that people check every day: small type with a clear weight
   contrast, tight rows, wide gaps between groups.

## Colour

Every colour in a rule is a token below, with the exceptions in [Known gaps](#known-gaps). A token
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
| `--ink` | `#111820` | text, headings, the beach dot rim in CSS |
| `--muted` | `#56606c` | secondary text |
| `--bg` | `#ffffff` | page, panels, controls |
| `--surface` | `#f3f5f7` | utility strip, footer, hover, segmented tracks, chat answers, release cards |
| `--line` | `#e1e5ea` | dividers, panel borders |
| `--line-strong` | `#cbd2da` | control borders, quote rule |
| `--sea` | `#cfe6f1` | the map before the base map loads |
| `--accent` | `#1b5fc1` | links, primary fill, focus ring, slider, the "you" marker |
| `--accent-hover` | `#164e9e` | hover on accent |
| `--accent-soft` | `#e9f0fb` | pressed toggles, the visitor's chat messages, member initials |
| `--emergency` | `#c0262d` | the emergency button's phone icon, nothing else |

### Glass

| Token | Value | Job |
|---|---|---|
| `--glass` | `rgb(255 255 255 / .9)` | frosted white: layer rail, key, zoom buttons, popups, emergency button |
| `--glass-hover` | `rgb(17 24 32 / .06)` | hover on a zoom button |
| `--glass-line` | `rgb(17 24 32 / .12)` | border of glass |
| `--glass-ink` | `#111820` | text on glass |
| `--glass-muted` | `#56606c` | secondary text on glass |
| `--glass-unfit` | `#c0262d` | unfit text on glass |

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
| `--shadow-float` | `0 1px 2px rgb(17 24 32 / .06), 0 8px 24px -6px rgb(17 24 32 / .16)` | what floats over the map |
| `--r-control` | `8px` | controls, glass buttons, popups |
| `--r-panel` | `12px` | panels, cards, figures |
| `--sans` | `Inter, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif` | the one type family |

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

The score colours are data: dots, chips, legend. A change needs a MIP note. The flow ramps are data
too. They follow Windy's muted scales, which visitors already read. A score is never told by the
field's colour alone, because the beach dots sit on top with a ring, and the selected one with its
number.

Four colours are not in `:root`, because a CSS variable does not reach them:

- The beach dot rim `#1d2733` and its white ring are SVG attributes in `front/src/MapView.elm`.
- The selected trail line and the Niño 3.4 box use `#1d2733` in `front/js/maplibre_ffi.mjs`.
- The score colours and the flow ramps appear again as hex in `front/src/Config.elm`, where
  MapLibre and the WebGL layer need them as values.
- The page's `theme-color` meta is `#ffffff`.

Shadows, hovers and the raised segment use `rgb(... / alpha)` of `--ink` or white. They are not hex
and the check does not read them.

## Contrast

Ratios are WCAG 2.x relative luminance, computed from the values in the tables. The rule: text is
at least 4.5:1 on its background. A control's border or an icon that carries meaning alone is at
least 3:1.

| Text | On | Ratio | Result |
|---|---|---|---|
| `--ink` | `--bg` | 17.87:1 | pass |
| `--ink` | `--surface` | 16.35:1 | pass |
| `--muted` | `--bg` | 6.39:1 | pass |
| `--muted` | `--surface` | 5.85:1 | pass |
| `--muted` | `--accent-soft` | 5.58:1 | pass |
| `--accent` | `--bg` | 6.08:1 | pass |
| `--accent` | `--surface` | 5.56:1 | pass |
| `--accent` | `--accent-soft` | 5.31:1 | pass |
| `--accent-hover` | `--bg` | 8.02:1 | pass |
| `--accent-hover` | `--surface` | 7.34:1 | pass |
| white | `--accent` (the badge, a pressed layer button) | 6.08:1 | pass |
| white | `--accent-hover` (the badge on hover) | 8.02:1 | pass |
| `--emergency` and `--glass-unfit` | `--bg` | 5.90:1 | pass |
| `--c0` | `--bg` (unfit water text) | 5.19:1 | pass |
| `#137a5c` (the "proper" water text in the beach card) | `--bg` | 5.29:1 | pass |
| white | `--c0` (a score chip) | 5.19:1 | pass |
| white | `--c70` (a score chip) | 3.39:1 | fail |
| white | `--c1` (a score chip) | 3.76:1 | fail |
| white | `--cna` (a score chip) | 3.36:1 | fail |
| white | `--c40` (a score chip) | 2.06:1 | fail |
| `--line-strong` | `--bg` (a control border) | 1.53:1 | fail |

The four failing chips are real: the list and the card print the score in white on its band
colour at 12 to 13 px. The number is also in the row and in the card text, so no reading depends on
the chip colour alone. See [Known gaps](#known-gaps).

## Type

Inter only, self-hosted (`vendor/fonts/inter-latin-wght-normal.woff2`, variable weight), never from
a CDN. Inter is the deliberate pick for a public-information page that must be easy to read.

Sizes are `--fs-*` tokens. Each size has a `--tr-*` tracking that follows Inter's dynamic metrics
(`-0.0223 + 0.185 * e^(-0.1745 * px)` em): small text stays open, large text tightens. A rule that
sets a size sets its tracking too, because `letter-spacing` inherits as a length.

| Role | Size token | Size / weight / line-height | Where |
|---|---|---|---|
| Display | `--fs-display` | 36 to 56 px (`clamp`) / 700 / 1.05 | the first h2 of a reading column |
| Section | `--fs-28` | 28 px / 650 / 1.15 (24 px on phones, `--fs-24`) | h2 in a reading column |
| Wordmark | `--fs-22` | 22 px / 650 / 1.2 (20 px on phones, `--fs-20`) | header |
| Lede | `--fs-21` | 21 px / 400 / 1.45, `--muted` (19 px on phones, `--fs-19`) | the paragraph under a page title |
| Panel title | `--fs-20` | 20 px / 650 / 1.25 (18 px on phones, `--fs-18`) | card h2 |
| Quote | `--fs-19` | 19 px / 400 / 1.5 | a short cited quote in a reading column |
| Reading | `--fs-17` | 17 px / 400 / 1.6; h3 at 600 / 1.4 | the body of every page in a reading column |
| Body | `--fs-15` | 15 px / 400 / 1.5 | map page, panel titles in sos and chat, inline `code` |
| UI | `--fs-14` | 14 px / 500 | controls, list rows, card readings |
| Meta | `--fs-13` | 13 px / 400 to 500 | hour bar, legend, footer, labels, captions, popups |
| Caption | `--fs-12` | 12 px | ranks, chips, day dates, layer rail |
| Fine | `--fs-11` | 11 px | map attribution, the layer key on phones |

Headings get `text-wrap: balance` and `optimizeLegibility`. Reading paragraphs get `text-wrap:
pretty`. The page has `font-kerning: normal`. Scores, hours and distances use `tabular-nums`.
Prose stays within 65 characters where it can (the reading column is 40 rem). The area code in the
picker keeps a wider tracking of +0.02em.

The map page is a dense tool: weight, not size, makes its hierarchy, and it stays between 12 and
22 px. The reading pages are where size works: a display title, a muted lede, 28 px section heads
with 72 px above them (56 px on phones), and figures and quotes that take the full column.

## Space and shape

- 4 px grid: 4, 8, 12, 16, 24, 32, 48. The page gutter is 24 px (16 px on phones).
- Radius: controls 8 px (`--r-control`), panels 12 px (`--r-panel`). Smaller radii exist inside a
  control: 6 px for a segment, 4 px for inline `code` and a key ramp, 10 px for a chat message. A
  full pill (999 px) is the score chip, the chat toggle and the release tag. A circle is the layer
  button, the "you" marker and a member's mark.
- Shadow `--shadow-float` on what floats over the map: list, card, chat panel, emergency panel,
  popup, glass controls, chat toggle. The raised segment of a segmented control has its own
  1 px shadow. No other element has a shadow.

## Focus, target size and motion for the keyboard

- Focus ring: `:focus-visible` shows a 2 px `--accent` outline with a 2 px offset (1 px offset on a
  text field). Never remove it. Never replace it with a colour change alone. `--accent` on
  `--bg` is 6.08:1.
- Minimum target: 24 px by 24 px (WCAG 2.2, criterion 2.5.8), and no control is smaller. A
  control is 36 px high (30 px inside a segmented track, 24 px in the language switch on the strip).
  A map control is 32 px (the emergency button, a close button, a layer button on a phone). What a
  thumb taps first on a phone is 44 px: the emergency numbers and the footer folds.
- Every control has a name a screen reader can read. An icon-only button keeps its word in a
  visually hidden `span` and in `title`.
- A state is never told by colour alone: a pressed control has `aria-pressed` or `aria-expanded`
  and a different fill; a disabled layer has `disabled` and a title that says it is not built yet ("em breve" in pt-BR).

## Components: the map page

- **Utility strip** (`.sitenav`): 40 px high, `--surface`, 13 px plain links. A section with no page
  yet is muted text with "(em breve)". The language switch and the LinkedIn and GitHub links sit at
  the right. On phones the strip is one row that does not wrap, and it hides the muted sections and
  the links to members, studies, research and contribute (about links them).
- **Header** (`.bar`): the wordmark with the wave icon in `--accent`, the one-line tagline beside
  it (under it on phones), the controls at the right. On phones the controls are one row that does
  not wrap: the area picker, the day buttons, the icon buttons.
- **Control**: 36 px, 8 px radius, 1 px `--line-strong` border, `--bg`, 14 px / 500. Hover:
  `--surface` fill. Pressed (`aria-pressed`, `aria-expanded`): `--accent-soft` fill, `--accent`
  border and text. `:active` nudges it 1 px down. Disabled layer buttons are at 45% opacity.
- **Area picker** (`#area`): a `select` that shows the two-letter code of the area (for example FL),
  with the full name in its accessible name. It is the one control with no case change and a +0.02em
  tracking.
- **Segmented** (the day buttons, the language switch): a `--surface` track with a 1 px `--line`
  border. The picked segment is `--bg` with a 1 px `--line` border and a 1 px shadow.
- **Primary action**: `--accent` fill, white text, one per surface: the chat toggle and the chat
  send button.
- **Emergency button** (`#sos`): a map control in `--glass`, 32 px high, 13 px, Lucide's phone icon
  in `--emergency`, at the top centre of the map, above every panel (z-index 1001). Its panel is
  18 rem wide under the button. Under 641 px it is a bottom sheet. The numbers are 193, 190, 192,
  185 and 199, each a `tel:` row of at least 44 px with the number at weight 650, then a 12 px note.
  The panel fades in 150 ms. It comes from Carlos Toledo's swell-floripa (#76).
- **Hour bar**: a label, the slider (`accent-color: --accent`), the legend pushed to the right.
- **Panels** (`.list`, `.card`): `--bg`, 1 px `--line`, `--r-panel`, `--shadow-float`. Under 641 px
  they are bottom sheets. The list is 22 rem wide on a desktop, the card 26 rem.
- **Close button**: the control as a borderless 32 px square in `--muted`.
- **Beach marker** (`.wave`): a 16 px dot in its band colour, a 2 px white ring, a `#1d2733` rim. The
  selected beach is a 32 px badge with its score number. A past hour keeps the dot at 45% fill
  opacity with a dashed ring. No glyphs, halos or shadows. The legend draws the same dot at 8 px.
- **Water-sampling marker** (`.wpoint`): Lucide's droplet, 18 px (22 px on the water layer), filled
  with the point's status (`--c70` proper, `--c0` unfit, `--cna` no classification), with a
  `--ink` rim and a `--bg` stroke, so a sampling point never reads as a beach. On the water layer
  the beach dots drop to 40% opacity.
- **"You" marker** (`.here`): a 12 px `--accent` dot with a 2 px `--bg` border.
- **Map**: MapLibre GL JS 6.17.0, self-hosted under `vendor/maplibre/`, on OpenFreeMap's `liberty`
  style (`Config.styleUrl`). Zoom buttons at the top left (the layer rail takes the right). The
  attribution is 11 px, bottom right. The `--sea` colour shows until the tiles load.
- **Popups** (`.maplibregl-popup`): the panel shape in glass, 13 px, no arrow, no pointer events.
  The beach popup (`.aspects`) is a two-column grid of readings, up to 22 rem wide. In the beach
  card the same grid shows without its head.
- **Layer rail** (`.flow`): at the top right of the map, in glass, scrolls on a map too short for
  it. Order: two toggles (beaches, trails), the trail-list button, a 1 px rule, then one round
  36 px icon button per layer (wind, waves, bathing water, clouds, sea temperature, anomaly,
  El Niño) and bathymetry. No button shows text: the word is the button's `title` and its hidden
  label. In the current build only the bathing-water layer is enabled (`Config.enabledLayers`).
  The other layer buttons are disabled at 45% opacity and titled "em breve". The map opens with no
  layer on, and a pressed layer button turns it off. The pressed button is a `--accent` circle with
  white icon.
- **Layer key** (`.flowkeys`, `.flowkey`): at the bottom left, in glass, 13 rem wide (7.5 rem on
  phones, where the caption hides). A ramp 8 px high with its two ends, or the fit and unfit dots,
  then a caption.
- **Flow layer** (wind and waves, `flow_layer_ffi.mjs`): a WebGL layer. The field is drawn at 65%
  opacity, so the light base map shows through, and particles run over it. Its edge fades. Under
  `prefers-reduced-motion: reduce` the particles are drawn once as still streaks. It is built, but
  its layer buttons are disabled in the current build.
- **Footer** (`.footer`): `--surface`, 13 px. The status line (freshness and linked sources)
  always shows. The day's sea lore and the score note fold behind compact controls (32 px, 13 px;
  on a phone 44 px, 15 px, with the sign in a 20 px `--accent` circle). The plus turns into a minus.
  They are closed by default. Open, a control takes the pressed look and the map keeps its height.
  A third control, "artistas locais", is a placeholder: muted, `aria-disabled`, titled "em breve".
  From 840 px the controls sit at the right of the status line. Narrower, they take their own row.
- **Icons**: Lucide line icons (ISC, `vendor/icons/LICENSE.lucide`) through `Icons.icon` in
  `front/src/Icons.elm`. 16 px, 1.75 stroke, `--accent`, `aria-hidden`, with the word next to
  it. Never emoji.

## Components: pages and forms

The static pages and the study pages share one reading column and the chrome of the strip, the
header and the footer. They carry no script (see [No inline style, no script on content
pages](#no-inline-style-no-script-on-content-pages)).

- **Reading column** (`main.about > article.about-body`): 40 rem wide, 17 px / 1.6. Headings and
  rhythm are in [Type](#type).
- **Header on a content page**: the wordmark, the tagline, and one control: the link back to the
  map. There is no area picker and no day buttons.
- **Footer on a content page**: the same `.footer` with two paragraphs. The first is the privacy
  sentence. The second holds three links, "submit", "privacy", "takedown", with a literal `·`
  between them. Links are `--accent` on `--surface` (5.56:1).
- **Form** (`form.contact`): a grid with a 12 px gap, at most 520 px wide. The submit button is the
  plain control, not the primary one, and it sits at the start of the row. The same class styles
  the contact form, the submit form, the studies filter (a `GET` form with two selects), the
  account forms and the report form.
- **Form field** (`label` in `form.contact`): a grid with a 4 px gap. The label text is a `span`
  at the body size. The hint is a `small` (13 px) under it, in the text colour (not `--muted`). The
  control follows the hint. Text fields and text areas: `font: inherit`, 8 px 10 px padding, 1 px
  `--line-strong` border, `--r-control`, `--bg`, `--ink`, no case change. Focus: the 2 px `--accent`
  ring with a 1 px offset. A `select` is the plain control (36 px). A text area resizes vertically.
  States: hover on a `select` uses the control hover. Disabled and read-only fields are not used.
- **Error text** (`p.field-error[role="alert"]`): one paragraph under the field it names, or above
  the submit button for an error of the request. It has no CSS rule yet, so it shows as body text.
  The markup sets no `aria-invalid` and no `aria-describedby`. See [Known gaps](#known-gaps).
- **File input** (`input[type="file"]`, `accept="application/pdf"`): it takes the text-field rule
  above, and the browser draws its button. The hint under the label gives the limit.
- **Checkbox** (the "rights" field): the browser's own box, then the sentence and two links. It
  takes the text-field rule, and the browser draws the box.
- **Honeypot** (the report form): a text input with `hidden`, `tabindex="-1"`, `aria-hidden="true"`
  and `autocomplete="off"`. It is never visible.
- **"Not reviewed" badge** (`span.release-tag`): `--accent` fill, white text, 15 px / 600, pill,
  2 px 10 px padding, no case change. White on `--accent` is 6.08:1. It shares the class with the
  release tag in the news posts. It says "sem revisão" or "not reviewed", and it appears in the list
  row and under the title of a study, followed by the notice "Not reviewed. Not medical advice."
- **Key box** (the new API key, shown once): an `h3`, a sentence that says the key is not shown
  again, and the key in `code` inside a `p`. `code` is 15 px, `--surface` fill, 1 px 5 px padding,
  4 px radius, no case change. It has no border and no copy button.
- **Tombstone card** (a hidden study): the page of a study the board hid. An `h2`, a sentence, and
  a `dl` with the id, the SHA-256 hash, the dates and the reason, the id and the hash in `code`. No
  text of the study, no link to the file. The page has `noindex`. It has no card border or fill: it
  is a plain reading column.
- **Study row** (the list at `/studies`): an `li` inside `ul.members`, with an `h3` that links to
  the study, a `p` with the authors, and a `p` with area, topic, date, the badge and the first 12
  characters of the hash. `ul.members` has a top rule and no bullets. The row has no bottom rule,
  because that rule belongs to `.member`, which this row does not use.
- **Study page header** (`/studies/<id>`): the title as the display h2, a line with the badge and
  the notice, a list of the authors (an ORCID is a link with `rel="noopener noreferrer nofollow
  ugc"`), and a line with area, topic and date. Then the sections as h3: abstract, sources, code,
  licence, AI declaration, the file, and the "report this study" link.
- **Report form** (`/report/<id>`): the form above with a reason `select`, a details text area of 5
  rows and 1000 characters, the error paragraph and the submit button.
- **Pager** (`/studies`): one link, "Mais antigos" or "Older", in a paragraph under the list. It
  carries `before`, `area` and `topic` in its query. There is no numbered pager and no link back.
- **Release card** (`.release`, news posts): `--surface` fill, 1 px `--line`, `--r-panel`, with the
  tag as a pill at the top.
- **Member row** (`.member`, the members page): a 48 px circle at the left (the avatar or the
  initials in `--accent` on `--accent-soft`), then the name at weight 600 and three muted lines.

## Copy

Lowercase house style, set once with `text-transform: lowercase` on `body`. The exemptions are in
`style.css`: beach names, provider names, the agency's verbatim PROPRIA and IMPROPRIA verdict, text
in `code`, and the text of a form field. No em dash in visible copy: use a colon, a semicolon, a
comma or a period. At most one `·` per line, and only in compact metadata.

## Motion

Only state changes: colour and border 150 ms ease-out, the press 100 ms. All of it sits inside
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
   The script also fails when an `ALLOW` entry no longer occurs, so the list can only shrink.

`just quality` runs it. The check does not look at the prose, at the contrast table or at the
components. When you change a colour, recompute the contrast rows by hand and update them. When you
add a component, add its section here.

Layout is not in that check, because the repo's stub DOM has no layout. `scripts/nav_measure.sh`
loads every static page at 390 and 375 px in a real Chromium and fails when the utility strip is
wider than the screen. Run it by hand after a change to the strip (it is not in `just quality`).

## Known gaps

The code and this file disagree with the rules above in these places. Each is a debt, not a
decision.

- **Score chips fail contrast**: white on `--c70`, `--c1`, `--cna` and `--c40` is below 4.5:1. The
  marker's number for `--c40` has a `dark` class that no CSS rule uses.
- **Control borders** are `--line-strong` at 1.53:1 on `--bg`, below the 3:1 for a boundary.
- **Hex in `style.css`** outside `:root`: `#fff` (text on a filled accent or band colour),
  `#b4bec9` (the hover border of a control) and `#137a5c` (the "proper" water text). They are the
  `ALLOW` list of the check.
- **No rule** for these classes, which the markup emits: `field-error`, `trail`, `trail-card`,
  `trail-foot`, `trail-group`, `trail-note` and the `trails` variant of the list. They render with
  default styles.
- **No `aria-invalid`** and no `aria-describedby` on a field with an error.
- **Two `·` per line** in the footer links and in the study row, against the copy rule above.
- **Long unbroken text** (an API key of 56 characters, a SHA-256 of 64) in `code` has no wrap rule
  and may overflow a 390 px column.

## Not yet

- **A dark theme.** The page and the base map are light on purpose: the audience is beachgoers, and
  a dark map read as too heavy for them. There is no `prefers-color-scheme` rule and no dark tokens.
- **Print.** There is no `@media print` rule. A printed page is the screen page.
