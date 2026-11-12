# ADR-0006: The base map is the site's own (Protomaps, one PMTiles file)

| | |
|---|---|
| **Status** | Proposed (the owner chose the direction in marola-dev/marola-site#194, 2026-11-12; accepted when he merges it) |
| **Date** | 2026-11-12 |
| **Supersedes** | the base map of [ADR-0001](0001-fsharp-fable-maplibre-dynamic-hosting.md) (OpenFreeMap's `liberty` style and tiles), which [ADR-0005](0005-elm-and-haskell.md) had kept |

## Context

ADR-0001 moved the new page from Mapbox to MapLibre GL JS, with OpenFreeMap as the host of the
style, the sprite, the glyphs and the tiles. That removed the token and the bill, and left one
third party in the page's path: every map view sent the visitor's address to
`tiles.openfreemap.org`, and the map's look and its uptime were somebody else's. The privacy text
had to call the base map "the exception".

The owner asked for the map to stay on MapLibre and to stop depending on OpenFreeMap, and chose
self-hosted Protomaps: one PMTiles file on his own host (piabrota2, nginx in front of
`marola-server`). The site already has a server (ADR-0001, ADR-0002), so a file it sends is not a
new moving part. This starts and ends in this repo, so it is an ADR, not a MIP.

## Decision

1. **One PMTiles file, `marola.pmtiles`, is the base map's tiles.** It is host data, like the
   boards: never in git, never in the Nix package. `scripts/basemap_extract.sh` cuts it from the
   Protomaps daily build pinned in `site/basemap.version`.
2. **The file is a sparse pyramid**: the whole world to zoom 6, Brazil to zoom 9, and zoom 10 to 15
   in a box around each area of `site/areas.json` (its `radius_km` plus 50 km). The pieces are cut
   with `pmtiles extract` and joined with tippecanoe's `tile-join`; their zoom ranges do not
   overlap, so no tile is merged.
3. **A missing tile draws its ancestor.** The page registers the `pmtiles` protocol with
   `errorOnMissingTile`, so MapLibre treats a tile the file does not hold as failed and keeps the
   nearest loaded ancestor on screen. Outside a box the map gets coarse; it has no hole and no edge.
4. **The server sends the file by byte range** at `/tiles/<name>.pmtiles`, from `MAROLA_TILES`
   (then from `MAROLA_STATIC/tiles`, where an offline build puts the fixture). It is the only route
   that answers `Range`; it has its own rate limit. nginx may serve the file directly instead
   ([5-hosting](../5-hosting.md#the-base-map)).
5. **The style is generated and committed**: `scripts/basemap_style.mjs` builds
   `front/public/map/style.json` from `@protomaps/basemaps`' light flavor, recoloured
   ([DESIGN.md](../../DESIGN.md), "The base map"), with labels in Portuguese, a layer of beach
   names, and no sprite. Its glyphs (Noto Sans, Latin ranges) are committed under
   `front/public/map/fonts/`.
6. **The `pmtiles` library is vendored** under `front/public/vendor/pmtiles/`, as MapLibre is.
   `front/package-lock.json` does not change.
7. **The CSP loses `tiles.openfreemap.org`.** Its only third-party host is NASA GIBS, and its only
   frame Spotify's player, each loaded when the visitor asks for it.
8. **The credit** on the map is "© OpenStreetMap" (the ODbL asks for it) and "Protomaps", with links.

## What was measured

All sizes are of the Protomaps build `20261112.pmtiles` (basemap 4.15.2, 139 GB), with pmtiles
1.22.1 (`pmtiles extract --dry-run` for the options, the files themselves for the choice).

| Option | Size |
|---|---|
| world, zoom 0 to 5 / 0 to 6 / 0 to 7 | 15 MB / 45 MB / 190 MB |
| Brazil (`-74.5,-34.5,-28,6`), zoom 0 to 8 / 0 to 9 | 22 MB / 65 MB |
| the coast alone (`-52,-30,-34,-4`), zoom 0 to 10 | 64 MB |
| Florianópolis, radius plus 40 km, zoom 0 to 14 / 0 to 15 | 15 MB / 29 MB |
| Rio de Janeiro, radius plus 40 km, zoom 0 to 15 | 46 MB |
| Salvador, radius plus 40 km, zoom 0 to 15 | 20 MB |
| **chosen**: world 0 to 6 (45.1 MB), Brazil 7 to 9 (61.7 MB), Florianópolis, Rio and Salvador at radius plus 50 km, 10 to 15 (37.2, 49.2 and 22.5 MB) | **216 MB** (215,993,204 bytes) |

- The style is 22 kB (68 layers). The glyphs are 1.7 MB in 18 files; a view of a Brazilian city
  fetches two or three ranges of 76 to 135 kB each, and the server compresses them (a third less).
- The vendored `pmtiles.mjs` is 19 kB. The page's own bundle grew by 238 bytes.
- The fixture, `site/fixtures/basemap.pmtiles` (world to zoom 1, 3 km around Florianópolis to
  zoom 11), is 684 kB.
- In a headless Chromium, the three areas at their opening view, at zoom 14.5, at state scale and
  at zoom 3 made requests to the page's own origin only, none failed, and no label was missing a
  glyph. The same run found the ancestor tile drawn past the edge of a box.

Zoom 15 is the build's deepest level; MapLibre draws zoom 16 and 17 (the page's limit) from it.

## Consequences

- No third party sees a visitor's address when the map is drawn. The privacy and about pages say so.
- The host holds 216 MB more, and sends the tiles: some hundreds of range requests of a few
  kilobytes for a visit, each a line in the server's log until nginx serves the file.
- **The file must be on the host before this version is deployed.** Without it the page shows the
  beach list and the note that the map did not load. A deploy is now two steps in a fixed order.
- A new area needs the file cut again, or its streets stop at zoom 9.
- The map is as fresh as the pinned build. Protomaps keeps a daily build for about a week, so the
  pin names a build that later disappears; cutting again means moving the pin first. The script
  checks the pin against Protomaps' list, not the 139 GB build's bytes.
- The look is ours to keep: the colours live in `scripts/basemap_style.mjs`, and a new version of
  `@protomaps/basemaps` or of the tiles' schema reaches the page only when someone runs it.
- No icon on the map: no POI, no road shield, no one-way arrow, no dot beside a town's name. The
  sprite would be one more asset to host and the page marks its own beaches.
- A name with no Portuguese or English form in a script other than Latin is not drawn, because the
  page ships Latin glyphs only.
- The cutting needs two tools the dev shell does not have (`pmtiles`, `tile-join`); the doc names
  the `nix shell` that brings them. The style generator fetches an npm package and a git
  repository into `.tmp/` on its first run.
- MapLibre reports each missing tile as an error. The page ignores exactly that message before
  the map has loaded, and every other error still fails the map.

## Alternatives

- **Stay on OpenFreeMap.** Free and already working, and it is what the owner asked to leave: a
  third party in every map view, and a style we do not control.
- **MapTiler or Stadia Maps.** Hosted vector tiles with good styles. Both need an account and a
  key in the page, have a free tier with a bill past it, and see every visitor: Mapbox's terms
  again, which ADR-0001 left.
- **MapLibre's demo tiles** (`demotiles.maplibre.org`). No account, but they stop at country
  outlines: no streets, no beaches. A demo, and still a third party.
- **Protomaps' hosted API.** The same tiles with a key and a quota, and a third party.
- **The whole planet, or all of Brazil at zoom 15.** 139 GB, or several GB: more than the host
  should hold for three cities.
- **Two files and two sources** (a world file and a detail file). Needs no `tile-join`, but every
  layer of the style would exist twice and labels would repeat where the two meet.
- **Raster tiles from tile.openstreetmap.org.** Against that server's usage policy for a site's
  base map, a third party, and blurry on a phone.
- **Bundling `pmtiles` with Vite.** It would change `front/package-lock.json` and the `npmDeps`
  hash of `nix/package.nix`. The page already loads MapLibre as a vendored module, so this one
  joins it.
