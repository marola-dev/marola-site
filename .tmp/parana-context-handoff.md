# Handoff — map areas/data outside the Litoral do Paraná

Last updated 2026-11-26. Verify PR/CI state before acting.

## Current state

- **marola-site#278 — merged** as `57c25dc` (squash): Litoral do Paraná, IAT/PR water points, 67 OSM trails, saturated light base map, full-size Spotify player.
  - Source branch `feat/parana-litoral` at `5c6a266` (pre-merge).
  - Screenshots: orphan branch `pr-screenshots`, dir `278/`, embedded in the PR body.
- **piabrota/nix-os#329 — open, mergeable**: pin `6aecd2d` → `57c25dc`.
  - Branch `feat/marola-site-parana` at `e159fb0`; source hash `sha256-lyRBWEPAPw+f1svqVHeHuc2VvH14enpAvh3jeG31DdY=`.
  - Tiles and boards re-cut automatically; docs additive; no deploy run.
- The pin jump also carries marola-site#276 (member websites); `6aecd2d` was #277.

## Area entry — `site/areas.json`

```json
{ "id": "parana", "name": "Litoral do Paraná",
  "lat": -25.5345, "lon": -48.3107, "radius_km": 70, "beach_limit": 80,
  "tz": "America/Sao_Paulo",
  "tiles": "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
  "tiles_attribution": "© OpenStreetMap contributors",
  "zoom": 9, "bounds": [-49.10, -25.95, -48.00, -25.15],
  "layer": "water",
  "pin": { "name": "Ilha do Mel", "lat": -25.5345, "lon": -48.3107 } }
```

- `pin` = named place; `url` makes it a partner link. `bounds` wins over the beaches' refit; camera starts at `lat/lon/zoom`.
- Add the picker code in `front/src/Config.elm` (`areaCode`) and the agency link (`sourceLink`).

## Water quality file — `front/public/data/water/<area>.json`

```json
{ "schema": 1, "area": "parana", "source": "IAT/PR", "sampled_on": "2026-02-09",
  "note": "copy, not live; next bulletin replaces it",
  "points": [ { "point": "IM01", "location": "Farol (Praia do Farol)",
    "lat": -25.54039, "lon": -48.30247, "condition": "proper",
    "sampled_on": "2026-02-09", "enterococci_per_100ml": null, "rain": null } ] }
```

- `condition`: `proper|improper|unknown`. The page fetches it for every area, draws on the water layer, dedupes by place against the board.
- Key uses `flow.key_water_file` with `{source}` — never hardcode IMA/SC.
- PR: IAT/PR *Balneabilidade Atual* (FeatureServer), 59 points, 19 improper, last complete week 9 of 2025/2026 (12 Jan–9 Feb 2026), no enterococci, 10 river-mouth points beyond the printed bulletin; next first bulletin 18 Dec 2026.
- CL: IMA/SC, 31 points, 19 Nov 2026.

### PR state beyond the Litoral

| Region | Water | Trails |
|---|---|---|
| Litoral (current `parana`) | IAT/PR 59 points (19 improper), `data/water/parana.json` | 67 routes in 9 groups, `data/trails/parana.json` |
| Costa Oeste (Itaipu) | IAT/PR 16 freshwater points, no file | no file |
| Norte (Primeiro de Maio) | IAT/PR 1 freshwater point, no file | no file |
| Curitiba / Campos Gerais / interior | no IAT/PR balneability point | OSM per area, no file |

- The IAT service covers 76 features: 59 `Litoral` + 16 `Costa Oeste` + 1 `Norte`. Filter `regiao|municipio|cod_ibge`; latest non-empty `b1..b11`; `Propria→proper`, `Impropria→improper`, empty/`Sem informação→unknown`.
- Interior PR has **no** water file: do not copy `parana.json`; the board may still carry its own points.
- Trails are **per area**, not state-wide. The Litoral queries (Ilha do Mel 55 km, Pico Paraná 20 km) do not cover the interior; run a new Overpass query around the new centre.

## Trails file — `front/public/data/trails/<area>.json`

- Top: `schema, area, ibge_municipality, source, licence, osm_base, note, bairros`.
- `bairros: [{ bairro, trails }]`; trail: `{ name, length_km, difficulty, surface, osm_ways, lines }`; `difficulty` = OSM `sac_scale` (T1/T2 display raw).
- Overpass: named `path|footway|track|steps` + `hiking|foot` relations; group by reverse-geocoded municipality/landscape; drop street-like names; merge duplicates; RDP simplify ~10 m (length from full geometry).
- PR file: 67 routes, 9 groups, ~254 KB.

## Fixtures and tests

- `back/pages/src/Marola/Pages/Fixtures.hs`: add real `fixtureBeaches`; `sampleIat` / `sample`; `boardFor` sets board `sources.water`.
- `front_check.js`: one scenario per area (bounds/pin/trails/water/dedupe/key/footer/picker); playlist checks `#player` is a sibling of `#flow`.
- `front/tests/ConfigTests.elm`: `areaCode` + `sourceLink`.
- Catalog change: `just golden` → `cabal run -v0 exe:marola-tools -- elm-fixtures` → `elm-test`. `front/tests/Fixtures.elm` is generated/git-ignored.

## Palette / player

- Colors only in `scripts/basemap_style.mjs`; run `node scripts/basemap_style.mjs`; check `--check`. Keep `--map-sea` in `front/public/style.css` + `DESIGN.md` in sync.
- Current: sea `#5bb8d8`, earth `#f7efd8`, beach `#f4c65a`, parks/woods `#c7e6a2`–`#84c47a`. Light map.
- `#player` must stay **outside** `.flow` (its `overflow` clipped it). Desktop 420×168 (`right:64; bottom:48`); phone 8 px sides, `bottom:44`.

## Commands

```bash
just front-test; just front-check; just back-test; just design-check; just js-check
node scripts/site_check.js; node scripts/golden.js --check; python3 scripts/i18n_bundle.py --check
MAROLA_SERVER_BIN="$(cabal list-bin exe:marola-server)" MAROLA_PAGES_BIN="$(cabal list-bin exe:marola-pages)" \
  just dist-build --fixtures --no-install
just server-run   # 127.0.0.1:8080
```

macOS: `--no-install` needed (bash 3.2); server link can need `--extra-lib-dirs=/opt/homebrew/opt/sqlite/lib` and `--extra-include-dirs=/opt/homebrew/opt/sqlite/include`.

## Gotchas

- **Fixture tiles** have no z≥4 tile outside Florianópolis; the page then draws overlays only. For screenshots serve a copy with PMTiles header `max_zoom=3` (byte 101) and label it a stand-in; production host covers Brazil z7–9 + area box z10–15.
- **Screenshots**: orphan `pr-screenshots` branch, `<pr>/` dir, raw URLs in the PR body; never on `main`.
- **marola-site commits**: `Tested:` + `Co-Authored-By: Claude <noreply@anthropic.com>`; `site/static/**` also needs `MIP:`.
- **Agent gate**: only `agent-ready` issues; #278 was a direct owner request.
- **nix-os hash**: NAR hash of the GitHub tarball via `nix hash path`; old pin must reproduce. No local Nix; Docker `nixos/nix` + OrbStack. `gh pr edit` may warn on projectCards; use `gh api repos/.../pulls/N -X PATCH -F body=@file`.
- **npmDeps** may fail in sandbox on registry.npmjs.org HTTP/2; source/hash valid, CI/deploy builds.
- Water and trails files are **one-off copies**, no refresh job.

## Next area checklist

1. Choose the area + most touristic point; set `lat/lon`, `radius_km`, `bounds`, optional `pin`.
2. Check the agency: for PR outside Litoral filter IAT/PR by municipality; if no points, skip the water file. Add `sourceLink`; `layer: "water"` if water is the subject.
3. New Overpass query around the area; build trails; group/simplify/note provenance.
4. Add `site/areas.json`, `areaCode`, fixtures/samples.
5. Add `front_check` scenario + `ConfigTests` + docs (`README`, `docs/4-reference.md`, `DESIGN.md` if needed).
6. Gates, `dist-build --fixtures`, before/after screenshots desktop+phone, push to `pr-screenshots`.
7. Open the PR; after merge, update the nix-os pin/docs (tiles/boards follow `site/areas.json`).
