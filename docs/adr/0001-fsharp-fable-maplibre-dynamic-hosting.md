# ADR-0001: F# with Fable, MapLibre and a .NET server

| | |
|---|---|
| **Status** | Superseded in part by [ADR-0005](0005-elm-and-haskell.md) (2026-11-12): the language. MapLibre, OpenFreeMap and the dynamic host stand |
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

1. Write the site in F#. `app/Shared` has the types and the pure functions. It uses no .NET-only
   API, so .NET and Fable both compile it. `app/Client` is compiled to JavaScript by Fable and uses
   Elmish for the page. `app/Server` runs on .NET.
2. Take the tools from Nix, not from the network. The dev shell has `dotnet-sdk_10`, `fable` and
   `fantomas` from the flake's `nixpkgs`. Never run `dotnet tool install`. The owner wrote "Fable 5.2".
   The pinned `nixpkgs` has Fable 5.26.0, with .NET SDK 10.0.403 and Fantomas 7.0.3 (checked on
   2026-11-11 against `nixpkgs` revision `f4a03c0`). This ADR records 5.26.0.
3. Lock the NuGet packages. Each project has `RestorePackagesWithLockFile` and a committed
   `packages.lock.json`. The recipes restore with `RestoreLockedMode`. The packages are in
   [the libraries page](../2-libraries.md#the-f-clients-libraries).
4. Decode the board with Thoth.Json.Core. One decoder runs on .NET and on Fable. The primitives in
   `app/Shared/Decoders.fs` read a JSON number only, because Thoth's own `int` and `float` accept a
   string such as "48".
5. Model every closed set as a union with an `Unknown of string` case where the board may carry a
   new value. Use records for the beach, the hour, the trail, the area and the board. Use `Result`
   or `option` for a data error, not `null` and not an exception.
6. Test every pure function twice. Expecto runs the tests on .NET. Fable compiles the same test files
   and Node runs them. Both read `app/Tests/golden.json`, which `scripts/golden.js` writes from the
   old JavaScript.
7. Use MapLibre GL JS 6.x in place of Mapbox GL JS. It is open source (BSD-3-Clause).
   The page loads it as an ES module from `'self'`. Two hand-written JavaScript files stay in
   `app/Client/ffi/`, and F# calls them.
8. Use OpenFreeMap as the base map style. The style URL is one constant in one file.
9. Draw trails from OpenStreetMap data (ODbL 1.0). Fetch them once from Overpass.
   Group them by neighbourhood. Do not use Wikiloc: it has no public API and gives no licence to copy its tracks.
10. Run a .NET server on piabrota2 at `marola.piabrota.art`. It serves the pages and the data.

This decision replaces the rule "plain JavaScript, no framework, no build step" in `AGENTS.md`.
The CSP stays strict: scripts load from `'self'` only.

## Consequences

- The page needs a build step. CI must run `fable` before it publishes the page.
- A server must run and be watched. Static hosting is no longer enough.
- The change of `.github/workflows/` needs a person. An agent writes a patch file, not the change.
- The page stops using the Mapbox token. The Mapbox bill and the token rules stop applying to the map.
- The page must show the OpenStreetMap credit. The ODbL requires it.
- `flow.js` must change. MapLibre calls a custom layer with `render(gl, options)` and a WebGL2 context.
  Mapbox called it with `(gl, matrix)`.
- The golden file `app/Tests/golden.json` keeps the old behaviour as the test of the new code.
  `scripts/golden.js` reads the old files, so it works only while they exist.
- Decoders turn a value outside a closed set into an `Unknown` case. The page does not crash on a new value.
- Each shell downloads the NuGet packages again, because `NUGET_PACKAGES` points into the shell's
  temporary folder. The restore is the only download besides the Nix store.
- Number text comes from two runtimes. `Parse.shortest` uses `ToString("R")` on .NET and JavaScript's
  `String(n)` under Fable. `Parse.tryFloat` and `Parse.tryInt` check the shape first, so both read the
  same text. The golden tests are the proof.

## Alternatives

- Gleam with Lustre, on JavaScript and Erlang. The first attempt in this branch (commits `6c984ec` and
  `2007743`) had the types, the decoder, the pure functions and a Lustre map page, with the golden
  parity tests green on both targets. It was dropped because the owner chose F#. The Gleam code was the
  specification for this port and is not in the tree.
- Keep plain JavaScript and change only the map library. The diff is small.
  The hand-written HTML stays, and no type checks the board.
- Keep Mapbox. It needs a token and billing, and its licence ties the map to a Mapbox account.
- Keep static hosting. It costs least. It does not give the server the owner asked for.
- Use Wikiloc for trails. It has no public API and no open licence. Nobody read its full terms.

## Not verified

- The OpenFreeMap style URL. Nobody fetched it. The code will have one constant to change.
- The MapLibre matrix units for the flow layer. `flow.js` draws in mercator units from 0 to 1.
  No test in a browser shows that MapLibre's `modelViewProjectionMatrix` expects those units.
- A Nix build that fetches the NuGet packages offline from the lock files. Nobody built it.
- The browser. The Fable tests run on Node. No browser ran the compiled code.
- The flow field. `flow.js` stores values as 32-bit floats. The F# port uses 64-bit floats.
  The tests accept a relative difference of 1e-5.
- The licence of Fable.Mocha. Its nuspec links a file in its repository. Nobody read that file.
- The Client and the Server. This run ports the shared code and its tests only.
