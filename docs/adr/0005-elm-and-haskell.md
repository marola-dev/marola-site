# ADR-0005: Elm for the page, Haskell for the server and the pages

| | |
|---|---|
| **Status** | Accepted (Hoffmann, 2026-11-12) |
| **Date** | 2026-11-12 |
| **Supersedes** | the language choices of [ADR-0001](0001-fsharp-fable-maplibre-dynamic-hosting.md), [ADR-0002](0002-dotnet-server.md) and [ADR-0003](0003-pages-in-fsharp.md) |

## Context

ADRs 0001 to 0003 wrote the new site in one language: the map page compiled to JavaScript, the
server and the static pages on the server's runtime. The site was then ported, part by part, to Elm
(the map page) and Haskell (the static pages and the server), and the two builds lived side by side
until the ports matched: the pages byte for byte (`scripts/pages_parity.sh`, 23 of 23 files at
efaaea3), the page under the same smoke test (`scripts/front_check.js`), the server under the same
end-to-end run (`scripts/server_smoke.sh`) and the ported test suites. The owner chose which build
stays. It is a decision inside this repo, so it is an ADR, not a MIP.

## Decision

1. **The map page is Elm** (0.19.1), in `front/`, bundled by Vite. Elm owns the model, `update` and
   the views; every effect leaves through a port to `front/ports.js`, which calls MapLibre and the
   flow layer in `front/js/`. The browser libraries stay vendored in `front/public/vendor/`.
2. **The server is Haskell** (GHC 9.6, warp, wai, SQLite through sqlite-simple), in `back/server`.
   It keeps ADR-0002's contract: the routes, the `MAROLA_*` variables, the headers and CSP, the rate
   limits, the SQLite schema, the PDF intake and the board's commands, on `127.0.0.1` behind nginx.
3. **The static pages are Haskell**, in `back/pages` (`marola-pages site <out>`), rendered from the
   same Markdown, catalogs and MEMBERS.md at build time, as ADR-0003 decided.
4. **One build**: `scripts/site_build.sh` assembles `dist/` (the page, the pages, the assets and
   `csp.txt` from `marola-server csp`); the server serves it by default. The cabal project is the
   root `cabal.project`, with one freeze file.
5. **One Nix package** keeps the interface piabrota/nix-os uses: `bin/marola-server` and
   `share/marola/dist`.
6. **The repo keeps the name marola-site.**
7. The earlier code is removed, not kept beside the port.

What stands from the earlier ADRs: MapLibre and OpenFreeMap with no token, NASA GIBS, a server
behind nginx in place of static hosting (0001); the server's contract (0002); pages from Markdown with
no script and no inline style (0003); study submission (0004).

## Consequences

- One language per side, and no runtime to install on the host: the server is a native binary.
- The pure code of the page is pure by the language, not by a convention a script counts.
- The old tool checks go: the .NET and Fable test runs, the formatter, the NuGet lock files and
  audit, and the effect-count ratchet. `just front-test` (elm-test) and `just back-test` (hspec)
  replace the tests; nothing yet replaces a formatter check or a package audit for Elm and Haskell.
- `cabal.project.freeze` pins versions, not hashes, and the Nix build takes its Haskell packages from
  nixpkgs, so the two can differ.
- The Nix package was rewritten without a build: its npm and Elm hashes wait for a first build with
  network ([5-hosting](../5-hosting.md#build-with-nix)).
