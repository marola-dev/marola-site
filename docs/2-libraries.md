# Libraries

Plain JavaScript, no framework and no build step ([`AGENTS.md`](../AGENTS.md)'s Code style
section): every file under `site/static/` ships to the browser exactly as it sits in the repo, and
`just site-build` only copies `site/static/.` into `site/dist/` — it does not bundle or transpile
anything. Everything below lives under `site/static/vendor/`, vendored rather than pulled from a
CDN, so the CSP in [design.md](1-design.md#csp-and-the-no-third-party-rule) can keep
`default-src 'self'`.

| Library | Version | Why vendored | Licence |
|---|---|---|---|
| Mapbox GL JS | 3.32.0 (the CSP build, `vendor/mapbox-gl-csp.js` + `vendor/mapbox-gl-csp-worker.js`) | The base map; its custom-layer API backs `flow.js`'s WebGL wind/wave particles. Needs a Mapbox account and `pk.` token at runtime regardless of vendoring ([tile policy](4-reference.md#tile-policy)) | Mapbox TOS (`vendor/LICENSE.mapbox-gl`): usable only with a Mapbox account in good standing, not a permissive open-source licence |
| Inter (variable weight) | self-hosted woff2 (`vendor/fonts/inter-latin-wght-normal.woff2`) | A public-information, accessibility-first page; never pulled from a font CDN (no third-party font origin) | SIL OFL 1.1 (`vendor/fonts/LICENSE.inter`) |
| Lucide icons | inlined per-icon through `icon(name)` in `app.js` | Line icons, 16 px, matching [`DESIGN.md`](../DESIGN.md)'s one-icon-style rule | ISC, plus MIT for the icons descended from Feather (`vendor/icons/LICENSE.lucide` lists which) |
| "Oceanwavescrushing" (waves.mp3) | re-encoded to 48 kbit/s mono | The `#sound` toggle's ambient loop | CC BY 3.0, via Luftrum → Blanket → marola's re-encode (`vendor/sounds/LICENSE.waves`) |

## What Mapbox replaced

The original map (MIP-0005) was Leaflet over OpenStreetMap's tile servers. [PR
#44](https://github.com/marola-dev/marola-site/pull/44) replaced it with Mapbox GL JS and added
the Windy-style layer rail; nothing under `site/static/vendor/` is Leaflet any more, and
`site/areas.json`'s `tiles`/`tiles_attribution` fields are vestigial for this repo
([reference](4-reference.md#area-fields)).

## The Elm page's libraries

`front/` is built by Vite. The npm packages are build tools only (`front/package-lock.json` pins them
and their hashes): Vite 7.3.7, vite-plugin-elm 3.0.1 and elm-test. The browser libraries the page loads
are vendored under `front/public/vendor/` and copied as they are; no npm package reaches the browser.
The Elm packages are in `front/elm.json`.

| Library | Version | Why | Licence |
|---|---|---|---|
| MapLibre GL JS | 6.17.0 (`vendor/maplibre/`: `maplibre-gl.mjs`, `maplibre-gl-worker.mjs`, `maplibre-gl-shared.mjs`, `maplibre-gl.css`) | The base map. It replaces Mapbox GL JS and needs no account or token. The files are the upstream `dist/` files, not edited. `INTEGRITY.txt` holds the npm sha512 of the tarball | BSD-3-Clause (`vendor/maplibre/LICENSE.maplibre-gl`) |
| elm/core, elm/browser, elm/html, elm/json, elm/svg | 1.0.5, 1.0.2, 1.0.0, 1.1.3, 1.0.1 | The language's own packages: the page, its views, its JSON decoders | BSD-3-Clause |
| elm-explorations/test | 2.2.1 | The tests (`just front-test`) | BSD-3-Clause |

`maplibre-gl-shared.mjs` is empty in 6.17.0 and nothing imports it. It stays so that the folder is
the upstream one. `maplibre_ffi.mjs` loads `maplibre-gl.mjs` with a dynamic `import()` of an
absolute path and sets the worker with `setWorkerUrl`.

## The Haskell packages

`back/pages` and `back/server` are one cabal project (`cabal.project`), and `cabal.project.freeze` pins
every package's version. The main ones:

| Package | Version | Why |
|---|---|---|
| warp, wai | 3.4.21, 3.2.5 | The HTTP server and its interface |
| sqlite-simple, direct-sqlite | 0.4.19.0, 2.3.29 | The contact messages, accounts and studies, in one SQLite file. direct-sqlite links the system SQLite (`+systemlib`), so a fix of SQLite is a system update |
| aeson | 2.2.5.1 | Reads the catalogs (both packages) and GitHub's answers |
| crypton | 1.0.6 | SHA-256 of a PDF and of keys, the CSRF HMAC, random tokens |
| brotli, zlib | 0.0.0.3, 0.7.1.1 | Response compression |
| http-client, http-client-tls | 0.7.19, 0.3.6.4 | The GitHub login |
| cryptohash-sha1 | 0.11.101.0 | The git blob id of MEMBERS.md (`back/pages`) |
| hspec | 2.11.18 | The tests (`just back-test`) |
