# Reference

## Area fields

Each entry in `site/areas.json` is one area `just site-build` can build boards for.
`scripts/site_check.js` validates every entry against the same shape the app's `Areas.parse`
([`cli/src/main/scala/marola/site/SiteBuilder.scala`](https://github.com/marola-dev/marola-app/blob/main/cli/src/main/scala/marola/site/SiteBuilder.scala))
requires; a malformed entry is silently dropped there rather than failing.

| Field | Type | Notes |
|---|---|---|
| `id` | string, `^[a-z0-9-]+$` | The area's slug (`floripa`, `rio`, `salvador`); used in `data/<id>/…` paths and the `?area=` param |
| `name` | string | The full display name (`Florianópolis`, `Rio de Janeiro`, `Salvador, BA`) |
| `lat`, `lon` | number | The area's centre point, for the Overpass query the app runs to find beaches |
| `radius_km` | number | How far out from `lat`/`lon` the app looks for beaches |
| `beach_limit` | number | The most beaches the app keeps for this area |
| `tz` | string, a valid IANA zone | The area's local timezone (`America/Sao_Paulo`, `America/Bahia`), for "today"/"tomorrow" labelling |
| `tiles` | string | A tile-server URL template. Read by the app side, not by this repo's own map any more: since the Mapbox GL switch ([libraries](2-libraries.md#what-mapbox-replaced)), `app.js` builds its base map from `mapbox-config.js` instead |
| `tiles_attribution` | string | Pairs with `tiles`, same app-side status |

## Tile policy

The page's base map and its CSP are [design.md](1-design.md#csp-and-the-no-third-party-rule)'s;
this is the cost and provenance side:

- **Mapbox** (the base map): billed per map load once `MAPBOX_PUBLIC_TOKEN` is set, free up to
  Mapbox's monthly tier. The token is a public `pk.` token restricted to marola.dev's URLs, kept in
  a repo variable/secret and written into `mapbox-config.js` only at deploy time
  (`scripts/mapbox_config.sh`); the account, the token and any billing setting are a human's
  ([`AGENTS.md`](../AGENTS.md)'s Cost & deployment safety section). Without a token the page shows
  no base map rather than failing silently; `site.yml`'s deploy sets `MAPBOX_REQUIRE_TOKEN=1` so a
  missing token fails the build instead of shipping a map-less live site.
- **NASA GIBS** (the four satellite raster layers): free, keyless, public tiles, fetched only when
  a visitor turns one of those layers on. No account and no cost.

## Board schema pin

`marola-image` (repo root) pins the one `ghcr.io/marola-dev/marola-app:jvm-<sha>@sha256:<digest>`
image this repo builds boards from — the jvm tag specifically, because the schema is read out of
`/app/marola.jar`, which the native image does not have. `site/board.schema.json` is that image's
`board.schema.json`, vendored by `scripts/board-schema.sh`:

```bash
scripts/board-schema.sh --image            # print the pinned image reference
scripts/board-schema.sh --check            # fail when the vendored schema differs from the pin's
scripts/board-schema.sh --update           # rewrite the vendored schema after bumping the pin
```

`board-schema.yml` runs `--check` in CI, and `site.yml` checks the page against the image's own
schema again before every deploy. A board schema change in the app is two PRs: the app's first,
then this repo's `marola-image`/`board-schema.sh --update` pair — see
[development.md](3-development.md#updating-the-app-image).

The schema (`$schema`: `https://json-schema.org/draft/2020-12/schema`) requires `schema`, `area`,
`day`, `today`, `generated_at`, `sources`, `lore` and `beaches`; `trails` is optional.

## Trail files

`front/public/data/trails/<area>.json` holds the hiking routes of an area. The map page fetches
`data/trails/<id>.json` for the area on show. `Trail.decoder` in `front/src/Trail.elm` decodes one route.

| Field | Notes |
|---|---|
| `schema` | The number 1 |
| `area` | The area id |
| `ibge_municipality` | The IBGE code of the municipality (the OSM tag `IBGE:GEOCODIGO`). The panel shows it in its footer |
| `source`, `licence`, `osm_base` | Where the lines come from: OpenStreetMap contributors, ODbL-1.0 |
| `note` | Text for the panel. Salvador has no routes, and its note says why |
| `bairros` | A list of `{bairro, osm_relation, trails}`. Each trail has `name`, `length_km`, `difficulty` (the OSM `sac_scale`, or null), `surface`, `osm_ways` (way ids) and `lines` (lists of `[lat, lon]`) |

The id of a route is its position in the bairros, in order. The map and the panel use that id.

Rio de Janeiro has 113 routes in 17 bairros. Florianópolis has 44 routes. Salvador has an empty
list and a note: the panel shows the note, never an empty panel. When an area has no file, the
board's own optional `trails` array stands in.

**Provenance.** One query on the Overpass API made the files. The files are a one-off copy: no job
refreshes them. The query takes every `way` with `highway` in `path|footway|track|steps` and a
`name`, and every `relation` with `route` in `hiking|foot`. Both use `around:<radius_m>,<lat>,<lon>`,
and the radius and the centre come from `site/areas.json`. The bairro of a route comes from the OSM
relations with `boundary=administrative` and `admin_level` 9 or 10 (or `place=suburb`,
`neighbourhood` or `quarter`) inside the municipality that has the OSM tag `IBGE:GEOCODIGO`.

**Filter.** A way stays when `sac_scale` is set, or when it is a `highway=path` whose name does not
start with a street word.

**Licence.** The data is OpenStreetMap data under the ODbL 1.0. The page shows the credit in the
map's attribution control and in the panel footer. Do not edit the files by hand: make them again
with the query above.
