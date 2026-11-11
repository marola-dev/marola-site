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

## The F# client's libraries

`app/Client` has no bundler and no npm. The browser libraries that it loads are vendored under
`app/Client/public/vendor/`. The .NET packages come from NuGet. Each `packages.lock.json` pins every
package and its hash, and `just app-test` restores in locked mode.

| Library | Version | Why | Licence |
|---|---|---|---|
| MapLibre GL JS | 6.17.0 (`vendor/maplibre/`: `maplibre-gl.mjs`, `maplibre-gl-worker.mjs`, `maplibre-gl-shared.mjs`, `maplibre-gl.css`) | The base map. It replaces Mapbox GL JS and needs no account or token. The files are the upstream `dist/` files, not edited. `INTEGRITY.txt` holds the npm sha512 of the tarball | BSD-3-Clause (`vendor/maplibre/LICENSE.maplibre-gl`) |
| Thoth.Json.Core | 0.10.1 (NuGet) | The board and trail decoders in `app/Shared`. One decoder runs on .NET and on Fable | MIT |
| Thoth.Json.Newtonsoft | 0.5.0 (NuGet) | Reads JSON on .NET, for the .NET test run only | MIT |
| Thoth.Json.JavaScript | 0.6.0 (NuGet) | Reads JSON on Node, for the Fable test run only | MIT |
| Expecto | 10.2.3 (NuGet) | The test framework on .NET. `Microsoft.NET.Test.Sdk` 17.14.1 and `YoloDev.Expecto.TestSdk` 0.15.5 let `dotnet test` find the tests | Apache-2.0 (Expecto), MIT (the two others) |
| Fable.Mocha | 2.17.0 (NuGet) | The test framework under Fable. It has the Expecto API, so both runs compile the same test files | The nuspec links the licence file in its repository; nobody read it here |

`maplibre-gl-shared.mjs` is empty in 6.17.0 and nothing imports it. It stays so that the folder is
the upstream one. `maplibre_ffi.mjs` loads `maplibre-gl.mjs` with a dynamic `import()` of an
absolute path and sets the worker with `setWorkerUrl`.

## The server's packages

`app/Server` uses the ASP.NET Core shared framework (Kestrel, the rate limiter, response compression,
the logging console): no package for those. The NuGet packages are these, and
[ADR 0002](adr/0002-dotnet-server.md) says why the list is short.

| Package | Version | Why | Licence |
|---|---|---|---|
| Microsoft.Data.Sqlite | 10.0.15 | The contact messages, in one SQLite file. It is the smallest way to a transactional store with no server process | MIT |
| SQLitePCLRaw.lib.e_sqlite3 | 2.1.14 | The native SQLite library. Microsoft.Data.Sqlite pulls 2.1.11, which carries SQLite before 3.50.2 (CVE-2025-6965) and fails the NuGet audit (NU1903). 2.1.14 carries SQLite 3.54.0 | Apache-2.0 (the wrapper), public domain (SQLite) |
| Microsoft.AspNetCore.TestHost | 10.0.0 | `app/Server.Tests` only: runs the real pipeline in memory, with a peer address the test chooses | MIT |

`app/Server.Tests` also uses Expecto, `Microsoft.NET.Test.Sdk` and `YoloDev.Expecto.TestSdk`, as in the
table above. Its `packages.lock.json` and the server's pin every package and its hash.
