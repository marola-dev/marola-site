# ADR-0008: An embeddable map

| | |
|---|---|
| **Status** | Proposed (accepted when the owner merges it) |
| **Date** | 2026-11-17 |
| **Builds on** | [ADR-0005](0005-elm-and-haskell.md) (the Elm page) and [ADR-0006](0006-self-hosted-basemap.md) (the site's own base map), which the embed reuses as they are |

## Context

Other sites want marola's map, not marola's whole page: a partner's page (OpenDiving's logbook, a
city portal), a blog post about a beach, the studies' own pages. Today they can only link to
marola.dev. The page cannot be framed either: the server answers every request with the one CSP of
`Marola.Csp` (`frame-ancestors 'none'`), so a browser refuses to draw marola.dev inside another
site — a deliberate choice, kept until there was a reason to open it.

An embeddable map would let a site show the sea conditions of its own area without sending the
visitor away, and would spread the map with no tracking of our own: the page has no cookies, no
accounts and no third-party requests besides NASA GIBS and the Spotify player the visitor opens.

## Decision

1. **The embed is an iframe of a chrome-less page on marola.dev, not a script or a web component.**
   An embedding site writes `<iframe src="https://marola.dev/embed?area=floripa&layer=water">`. No
   JavaScript of marola's runs on the embedding site, and none is added to this repository: the
   embedder owns their iframe tag, exactly as Spotify's player is embedded in marola (ADR-0005's
   ports rule stands; the embed needs no new port and no new file under `front/js/`).
2. **`/embed` serves the same Elm bundle with the chrome off.** The page reads `?embed=1` (already
   the pattern of `?area=`, `?day=` and `?layer=`) and hides the navigation, the tool row and the
   footer; the stage stays: the map, the layer rail, the trails panel and the beach card, the
   emergency button and the "not a lifeguard" notice (the safety parts are not optional), the
   attribution (OSM, Protomaps, MapLibre — the licences require it stays visible), and the language
   switch. One bundle, one build, no `embed.html` of its own.
3. **The server owns who may frame the page.** `/embed` answers with the CSP of `Marola.Csp`
   except `frame-ancestors`, which the allowlist of a new setting (`MAROLA_EMBED_FROM`, one origin
   per line, empty by default) writes: an origin not on the list gets `frame-ancestors 'none'`,
   so the embed is refused closed, not open. Every other page keeps `frame-ancestors 'none'`.
   The allowlist is a file the box owns, like its other secrets, never a wildcard.
4. **No postMessage API in this run.** The embedder sets what the URL already carries (area, layer,
   day, language); the embed reads its size from its own CSS (100% of the iframe) and sends nothing
   back. A `postMessage` protocol (the embedder changes the area without a reload, the embed posts
   its height) is a later ADR's to propose, when a partner asks for it.

## Consequences

- The embed is free: no account, no key, no bill. GIBS answers the satellite layers keylessly, and
  the base map is the site's own PMTiles file.
- The rate is the visitor's browser, not marola's: each embed loads the map as a first visitor
  would. The base map is one file read by byte range, so an embed costs what a visit costs.
- A partner with a very different look gets the map with marola's look. That is the point: the map
  stays recognisable and attributed; theming the embed would be another ADR.
- `?embed=1` on a page the server frames with the allowlist open is a public URL: anything the
  chrome-less page shows is public on marola.dev too, so the embed hides nothing.

## The plan: eight tasks, one session each

Each task is one pull request sized for one GLM-5 session: the files it touches, the checks it
must pass, and nothing else. The order is the order of the list; a task starts only when the one
before it is merged (the phase discipline of AGENTS.md).

| # | Task | Files | Checks |
|---|---|---|---|
| 1 | Elm: read `?embed=1` into the model; the chrome-less view (no nav, no tool row, no footer; the stage, the language switch, the emergency button and the notice stay) | `front/src/Params.elm`, `Model.elm`, `Update.elm`, `View/Page.elm` | `just front-test` (a new test: the flag hides the chrome), `just front-fmt` |
| 2 | CSS: the embed's layout (the map full height, the rail and the panels over it, the phone sizes) | `front/public/style.css`, `DESIGN.md` | `just design-check`, `just front-check` |
| 3 | The check: a `front_check.js` scenario for `?embed=1` (the map, the rail, the SOS button; no nav, no footer, no player) | `scripts/front_check.js` | `node scripts/front_check.js` (in CI's front job) |
| 4 | Server: the `/embed` route serving the map page, the CSP of `/embed` from `MAROLA_EMBED_FROM` (empty: `frame-ancestors 'none'`), every other page unchanged | `back/server/src/Marola/Csp.hs`, `App.hs`, `Files.hs`, `Config.hs` | `just back-test` (HeaderSpec: the header of `/embed` and of the other pages), `just back-fmt` |
| 5 | Server: the OpenAPI route of the CSP contract (the openapi.json's description of the embed) | `back/server/src/Marola/Server/OpenApi.hs` | `just back-test` (OpenApiSpec) |
| 6 | The sandbox: `/embed` documented on the site (`docs/4-reference.md`, the README's site table), and a live example page under `/partners` listing the embed for a partner to copy | `docs/4-reference.md`, `README.md`, `site/content/pages/partners.*.md` | `just quality` (docs-lint), `just pages-parity` |
| 7 | The smoke: `marola-tools smoke` covers `/embed` (a 200, the CSP's frame-ancestors from the setting) | `back/tools/src/Marola/Tools/Smoke.hs` | `just server-smoke`, `just package-smoke` |
| 8 | The pin: piabrota/nix-os's `marola-site.nix` passes `MAROLA_EMBED_FROM` from the box's file to the unit | `piabrota/nix-os` `marola-site.nix` (its own PR there) | nix-os's deploy build |

A task may fail on a detail of the one before it; that is a fix to that task's PR, not a ninth.

**Deviation, 2026-11-25.** Tasks 1–4 and 6 shipped together in one pull request, for the first
partner (Canto das Águas), which needed the embed in one piece rather than after four merges: the Elm
flag and the chrome-less view, the CSS, the `front_check.js` scenario, `/embed` with
`MAROLA_EMBED_FROM`, and the docs in `README.md` and `docs/4-reference.md`. Tasks 5 (the OpenAPI
description), 7 (the smoke) and 8 (the nix-os pin) follow the table as written.
