# ADR-0007: Elm or Haskell; JavaScript only when it is 100% necessary

| | |
|---|---|
| **Status** | Proposed (the owner set the rule on 2026-11-12, marola-dev/marola-site#199; accepted when he merges it) |
| **Date** | 2026-11-12 |
| **Builds on** | [ADR-0005](0005-elm-and-haskell.md), which chose Elm and Haskell for the new site but left the scripts and harnesses around it in Node |

## Context

ADR-0005 moved the page to Elm and the server and pages to Haskell. The code around them did not
move: the design check, the offline fixtures, the generator of the Elm test fixtures, the server
smoke checks and the fake GitHub were Node scripts, and the page sent its requests and its focus
through ports.js although Elm does both. On 2026-11-12, about 5,800 lines of JavaScript
outside the vendored folders were tracked (`git ls-files '*.js' '*.mjs'`, through `wc -l`), and the owner
asked for a hard rule: "Elm or Haskell. JS only when 100% necessary."

## Decision

1. **New code is Elm (the page) or Haskell (the server, the pages, every script, check and test
   harness).** Shell stays for glue that only calls other tools.
2. **JavaScript is allowed only where nothing else can run**: the glue around a library or a
   browser API with no Elm or Haskell binding (MapLibre GL JS, its WebGL custom layer,
   geolocation, `localStorage`, `history`, the document's `lang`, `alert`); a tool that reads only
   JavaScript (Vite's config); a check that must execute the compiled page (`front_check.js`); a
   generator that must call a JavaScript-only package (`basemap_style.mjs`, `@protomaps/basemaps`);
   vendored third-party code; and the legacy page (`site/static/`) with its checks until the
   owners cut over. TypeScript counts as JavaScript.
3. **The list is a file, and a check holds it**: `scripts/js-allowlist.tsv` names every
   JavaScript file git tracks with its reason; `marola-tools js-check` (`just js-check`, in
   `just quality` and CI) fails on a file that is not listed and on an entry that matches no file,
   so the list only shrinks.
4. **What moved, on 2026-11-12**: `design_check.js` to `marola-tools design-check`;
   `site_fixtures.mjs` to `marola-pages fixtures`; `front/tests/gen-fixtures.mjs` to
   `marola-tools elm-fixtures`; `server_smoke*.mjs`, `fake_github.mjs` and the inline script of
   `package_smoke.sh` to `marola-tools smoke*`, `fake-github` and `package-smoke`; the page's
   requests to elm/http and its focus to `Browser.Dom`. Each kept its behaviour: the same checks
   with the same labels, the same files (the JSON's key order aside), the same 68 Elm tests.

## Consequences

- A contributor needs GHC and cabal for the checks, not Node; Node stays for Vite, elm-test,
  `front_check.js` and the legacy page.
- `back/tools` is a third cabal package in the root `cabal.project`, built from the same freeze.
- The legacy page's JavaScript is listed, not moved: it is deleted with the cutover, not ported.
- `front/js/maplibre_ffi.mjs` and `flow_layer_ffi.mjs` stay; any logic in them that is not a call
  into MapLibre or WebGL is a candidate to move into Elm.
