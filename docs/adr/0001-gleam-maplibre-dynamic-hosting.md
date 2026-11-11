# ADR-0001: Gleam, MapLibre and a server on the BEAM

| | |
|---|---|
| **Status** | Proposed |
| **Date** | 2026-11-11 |

## Context

marola.dev is a static site. Its code is plain JavaScript with no framework and no build step.
The map uses Mapbox GL JS. That library needs an account, a token and a billing setting.

Three things in the code are weak points:

- `app.js` builds HTML strings by hand and escapes them with its own `esc()`.
- The link of the day's sea lore goes into an `href` with no check of its scheme.
- A change of the map library or of the board shape has no type check to catch a mistake.

The owner wants trail routes on the map and a server in place of static hosting.
The board generator is a Docker image outside this repository. It already writes an optional
`trails` array.

## Decision

1. Write the site in Gleam. `app/shared` has the types and the pure functions.
   `app/client` runs on JavaScript. `app/server` runs on Erlang.
   The client uses Lustre for the page.
2. Use MapLibre GL JS 6.x in place of Mapbox GL JS. It is open source (BSD-3-Clause).
   The page loads it as an ES module from `'self'`.
3. Use OpenFreeMap as the base map style. The style URL is one constant in one file.
4. Draw trails from OpenStreetMap data (ODbL 1.0). Fetch them once from Overpass.
   Group them by neighbourhood. Do not use Wikiloc: it has no public API and gives no licence to copy its tracks.
5. Run a Gleam server on piabrota2 at `marola.piabrota.art`. It serves the pages and the data.
6. Lock the Hex packages in `app/*/manifest.toml`.

This decision replaces the rule "plain JavaScript, no framework, no build step" in `AGENTS.md`.
The CSP stays strict: scripts load from `'self'` only.

## Consequences

- The page needs a build step. CI must run `gleam build` before it publishes the page.
- A server must run and be watched. Static hosting is no longer enough.
- The change of `.github/workflows/` needs a person. An agent writes a patch file, not the change.
- The page stops using the Mapbox token. The Mapbox bill and the token rules stop applying to the map.
- The page must show the OpenStreetMap credit. The ODbL requires it.
- `flow.js` must change. MapLibre calls a custom layer with `render(gl, options)` and a WebGL2 context.
  Mapbox called it with `(gl, matrix)`.
- The golden file `app/shared/test/golden.json` keeps the old behaviour as the test of the new code.
  `scripts/golden.js` reads the old files, so it works only while they exist.
- Decoders turn a value outside a closed set into an `Unknown(String)` variant. The page does not crash on a new value.
- `app/shared` uses `math:sin` and `Math.sin` through `marola/math.gleam`. `gleam_stdlib` has no trigonometry.
  This is the only code for one target in the package.

## Alternatives

- Keep plain JavaScript and change only the map library. The diff is small.
  The hand-written HTML stays, and no type checks the board.
- Keep Mapbox. It needs a token and billing, and its licence ties the map to a Mapbox account.
- Keep static hosting. It costs least. It does not give the server the owner asked for.
- Use Wikiloc for trails. It has no public API and no open licence. Nobody read its full terms.

## Not verified

- The OpenFreeMap style URL. Nobody fetched it. The code has one constant to change.
- The MapLibre matrix units for the flow layer. `flow.js` draws in mercator units from 0 to 1.
  No test in a browser shows that MapLibre's `modelViewProjectionMatrix` expects those units.
- A Nix build that fetches the Hex packages offline from `manifest.toml`.
  nix-os `site/default.nix` does this for its own site. Nobody built it for this repository.
- The browser. The JavaScript tests run on Node. No browser ran the compiled code.
- The flow field. `flow.js` stores values as 32-bit floats. The Gleam port uses 64-bit floats.
  The tests accept a relative difference of 1e-5.
