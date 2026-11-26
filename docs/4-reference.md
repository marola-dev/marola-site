# Reference

## Area fields

Each entry in `site/areas.json` is one area `just site-build` can build boards for.
`scripts/site_check.js` validates every entry against the same shape the app's `Areas.parse`
([`cli/src/main/scala/marola/site/SiteBuilder.scala`](https://github.com/marola-dev/marola-app/blob/main/cli/src/main/scala/marola/site/SiteBuilder.scala))
requires; a malformed entry is silently dropped there rather than failing.

| Field | Type | Notes |
|---|---|---|
| `id` | string, `^[a-z0-9-]+$` | The area's slug (`floripa`, `rio`, `salvador`, `complexo-lagunar`, `parana`); used in `data/<id>/…` paths and the `?area=` param |
| `name` | string | The full display name (`Florianópolis`, `Rio de Janeiro`, `Salvador, BA`, `Complexo Lagunar Sul Catarinense`, `Litoral do Paraná`) |
| `lat`, `lon` | number | The area's centre point, for the Overpass query the app runs to find beaches |
| `radius_km` | number | How far out from `lat`/`lon` the app looks for beaches |
| `beach_limit` | number | The most beaches the app keeps for this area |
| `tz` | string, a valid IANA zone | The area's local timezone (`America/Sao_Paulo`, `America/Bahia`), for "today"/"tomorrow" labelling |
| `tiles` | string | A tile-server URL template. Read by the app side, not by this repo's own map any more: since the Mapbox GL switch ([libraries](2-libraries.md#what-mapbox-replaced)), `app.js` builds its base map from `mapbox-config.js` instead |
| `tiles_attribution` | string | Pairs with `tiles`, same app-side status |
| `zoom` | number, optional | Where the map enters when the area is picked and has no `bounds`; without it, `Config.areaZoom` (10) |
| `layer` | string, optional | The map layer the area opens on, when the link names none (`water` for the Complexo Lagunar, whose subject is the lagoon's water quality, and for the Litoral do Paraná, whose points are IAT/PR's). A `?layer=` in the link wins |
| `bounds` | `[west, south, east, north]`, optional | The box the camera frames when the area is picked, instead of a point zoom, and the beaches' bounds no longer refit it. The Complexo Lagunar frames its lagoons (`-48.95, -28.63, -48.61, -28.07`): Imaruí, Mirim, Santo Antônio, Cabeçuda, Camacho, Arroio Corrente. The Litoral do Paraná frames the coast and the Serra do Mar (`-49.10, -25.95, -48.00, -25.15`), from Guaratuba to Superagui and inland to the Pico Paraná |
| `pin` | object, optional | `{name, lat, lon, url}`: the area's named place, drawn as a pin inside the camera's frame; `url` makes it a link, opened in a new tab. The Complexo Lagunar is pinned to Canto das Águas in Taquaraçatuba, Imaruí, linking to `https://cantodasaguas.org/`; it is the institute's published location, not a surveyed gate. The Litoral do Paraná is pinned to the Ilha do Mel, the state's most visited point, with no link: marola has no partner there yet |

## Tile policy

The page's base map and its CSP are [design.md](1-design.md#csp-and-the-no-third-party-rule)'s;
this is the cost and provenance side:

- **Mapbox** (the base map): billed per map load once `MAPBOX_PUBLIC_TOKEN` is set, free up to
  Mapbox's monthly tier. The token is a public `pk.` token restricted to marola.dev's URLs, kept in
  a repo variable/secret and written into `mapbox-config.js` only at deploy time
  (`scripts/mapbox_config.sh`); the account, the token and any billing setting are a human's
  ([`AGENTS.md`](../AGENTS.md)'s Cost & deployment safety section). Without a token the page shows
  no base map rather than failing silently; the deploy on piabrota2 sets `MAPBOX_REQUIRE_TOKEN=1` so a
  missing token fails the build instead of shipping a map-less live site.
- **The new site's base map**: no provider and no bill. The tiles are one PMTiles file on the site's own
  host, cut by `scripts/basemap_extract.sh` from a Protomaps daily build of OpenStreetMap data (ODbL: the
  page credits "© OpenStreetMap"); the style and the glyphs ship with the page
  ([Base map pin](#base-map-pin), [5-hosting](5-hosting.md#the-base-map)).
- **NASA GIBS** (the four satellite raster layers): free, keyless, public tiles, fetched only when
  a visitor turns one of those layers on. No account and no cost.
- **Spotify** (the new site's playlist player): the embed of GREAT RESET, the playlist
  room.piabrota.art plays (`Config.playlistEmbed`), loaded in an iframe only when a visitor presses
  the Spotify button. No account and no cost for marola; playing in full needs the visitor's own login.

## Base map pin

`site/basemap.version` pins the Protomaps build the tiles file is cut from. Line 1 is the build's key
(`<yyyymmdd>.pmtiles`, a file of about 139 GB at `https://build.protomaps.com/`), line 2 `b3sum` and the
checksum [builds.json](https://build-metadata.protomaps.dev/builds.json) lists for it.
`scripts/basemap_extract.sh` refuses to run when the key is no longer listed or its checksum differs. It
does not hash the build itself, which it never downloads whole.

| File | What | Written by |
|---|---|---|
| `site/basemap.version` | the pinned build | by hand, when the tiles are cut again |
| `marola.pmtiles` on the host (`MAROLA_TILES`) | world to zoom 6, Brazil (`-74.5,-34.5,-28,6`) zoom 7 to 9, each area's box zoom 10 to 15; 216 MB | `scripts/basemap_extract.sh <out>`; never in git |
| `site/fixtures/basemap.pmtiles` | world to zoom 1 and 3 km around the first area to zoom 11; 684 kB. `site_build.sh --fixtures` copies it to `dist/tiles/marola.pmtiles` for tests and an offline preview | `scripts/basemap_extract.sh --fixture site/fixtures/basemap.pmtiles` |
| `front/public/map/style.json`, `front/public/map/fonts/` | the style and its glyphs | `node scripts/basemap_style.mjs` (`--check` compares) |

An area's box is its centre plus and minus `radius_km + 50` km. A new area in `site/areas.json` needs the
file cut again: the `complexo-lagunar` area (the Southern Santa Catarina Lagoon Complex) and the
`parana` area (the Litoral do Paraná) are in the list, so the host's `MAROLA_TILES` file needs a new
`scripts/basemap_extract.sh` run before the live map shows streets there. The fixture preview still
cuts only the first area to zoom 11 (`--fixture`), so it shows the CL and PR areas on the world and
country tiles; that is a stand-in, not a missing build step.

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

`board-schema.yml` runs `--check` in CI, and `ci.yml`'s `static` job checks the page against the
vendored copy. A board schema change in the app is two PRs: the app's first,
then this repo's `marola-image`/`board-schema.sh --update` pair — see
[development.md](3-development.md#updating-the-app-image).

The schema (`$schema`: `https://json-schema.org/draft/2020-12/schema`) requires `schema`, `area`,
`day`, `today`, `generated_at`, `sources`, `lore` and `beaches`; `trails` is optional.

## Water quality in the Complexo Lagunar and the Litoral do Paraná

The `complexo-lagunar` boards use the usual pipeline: OpenStreetMap beaches and IMA/SC's
bathing-water points. IMA publishes points in the lagoons (Lagoa de Ibiraquera, Lagoa da Ferrugem,
Canal do Camacho, Lagoa de Cabeçuda, Lagoa do Arroio Corrente) and at the lagoon mouths. The app
matches a provider point to a beach by name; for an inland name (`lagoa …`, `canal …`) it does not
fall back to distance, so a lagoon point only reaches a beach whose name matches it. The fixture
board carries the points for the offline preview (the `fixtures boards` command); a production
board shows the points the app matches. An unmatched lagoon point needs an app-side change (an
inland-water beach, or a name alias), not an edit here.

### The area's own water file

`front/public/data/water/<area>.json` is the page's fallback for exactly that case: the official
points the board cannot draw because the app matches a provider point to a beach by name. The map
page fetches `data/water/<area>.json` for the area on show and draws its points on the water layer,
next to the board's, once per place (a point within about a metre of one the board already carries
is the same sample). The Complexo Lagunar has one; the Litoral do Paraná has another:

| Field | Notes |
|---|---|
| `schema` | The number 1 |
| `area` | The area id |
| `source` | The agency: `IMA/SC` or `IAT/PR` |
| `sampled_on` | The bulletin's day. The key's line under the rail prints it, so a dot never reads as today's |
| `note` | Text for whoever refreshes it |
| `points` | `{point, location, lat, lon, condition, sampled_on, enterococci_per_100ml, rain}`, the board's own point shape (`proper`, `improper`, `unknown`) |

The Complexo Lagunar file is a copy of IMA/SC's bulletin of 19 November 2026: 31 points, the beaches
and the lagoons of Garopaba, Imbituba, Laguna, Jaguaruna, Paulo Lopes and Palhoça, two of them
`improper`. The IMA publishes no enterococci count in that bulletin. **The next bulletin replaces the
file**; it is a copy, not live data, and no job refreshes it. The agency's site is
<https://balneabilidade.ima.sc.gov.br/> (`/municipio/getMunicipios` and the two POSTs its page
makes).

The Litoral do Paraná file is a copy of IAT/PR's *Balneabilidade Atual* service
(<https://geopr.iat.pr.gov.br/server/rest/services/Geoprocessamento/balneabilidade/FeatureServer/0>,
the layer the agency's own map reads), taken on 26 November 2026: 59 points from the Ilha do Mel to
Guaratuba and the rivers of Morretes and Antonina, 19 of them `improper`. The service's last complete
week is the 9th bulletin of the 2025/2026 season (samples from 12 January to 9 February 2026,
published for the week of 13–19 February); the 2026/2027 season's first bulletin is due on 18 December
2026, and it replaces the file. The service lists 10 river-mouth points that the printed bulletin
does not; they are in the file too, because the agency samples them. The IAT uses *E. coli* and
publishes no count in the bulletin, so `enterococci_per_100ml` is null for every point. The `source` is
`IAT/PR`; the key under the layer prints that name and the sampling day, not "today". The file is the
page's fallback: it draws these points whether or not the board's provider matches any of them, and
the map draws each place once.

## Embedding the map

`/embed` serves the map page with the chrome off (ADR 0008): no navigation, no tool row, no footer;
the map, the layer rail, the panels and the card, the trails panel, the emergency button and the
notice stay, and so do the attribution and a slim strip with the language switch. It is the same Elm
bundle, not a second build; only `/embed` is served frameable, and by the origins
`MAROLA_EMBED_FROM` lists ([hosting](5-hosting.md#variables)). With the list empty, or for any other
page, the server sends `frame-ancestors 'none'`.

The embed sets what the URL carries: `area`, `layer`, `lang`, `day`, `beaches=0` and `trails=0`
(the page's other parameters). With no `day`, it is today's board. The Complexo Lagunar frames its
lagoons from the first frame — its `bounds` — with Canto das Águas pinned inside, because an area
with `bounds` or a `pin` skips the fit to the beaches' bounds:

```html
<iframe src="https://marola.dev/embed?area=complexo-lagunar&lang=pt-BR"
        title="marola: as condições da lagoa hoje"
        width="100%" height="600" loading="lazy"></iframe>
```

The page reads its size from the iframe and sends nothing back: no cookies, no account, no message
to the embedding page (ADR 0008). Each embed is one visitor's map load.

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
| `bairros` | A list of `{bairro, trails}`, with an optional `osm_relation`. Each trail has `name`, `length_km`, `difficulty` (the OSM `sac_scale`, or null), `surface`, `osm_ways` (way ids) and `lines` (lists of `[lat, lon]`) |

The id of a route is its position in the bairros, in order. The map and the panel use that id.

Rio de Janeiro has 113 routes in 17 bairros. Florianópolis has 44 routes. The Complexo Lagunar Sul
Catarinense has 31 routes in seven groups (Imbituba, Garopaba, Paulo Lopes, Palhoça e Guarda do
Embaú, Florianópolis, Laguna and Serra do Tabuleiro), from the same query over the lagoons and the
Serra do Tabuleiro. The Litoral do Paraná has 67 routes in nine groups (Ilha do Mel, Guaraqueçaba,
Antonina, Morretes, Serra do Mar, Pontal do Paraná, Matinhos, Guaratuba and the Grandes travessias).
Salvador has an empty list and a note: the panel shows the note, never an empty
panel. When an area has no file, the board's own optional `trails` array stands in.

**Why no route lies on the lagoon shore.** The 31 routes are the coastal ones (Rosa, Ferrugem,
Ouvidor, Itapirubá) and the Serra do Tabuleiro. A query over the lagoon margins themselves — the
Imaruí, Mirim and Santo Antônio shores, inside the area's 55 km circle — finds no named route there:
OpenStreetMap has a single named highway way in Imaruí (a `highway=steps` street), and the filter
keeps named `path`/`track` ways only. A lagoon route appears when the map has one; the file does not
invent it.

**Provenance.** One query on the Overpass API made the files, except the Litoral do Paraná's: its
file combines two queries, one 55 km around the Ilha do Mel and one 20 km around the Pico Paraná,
because the area is two landscapes (the coast and the Serra do Mar). The files are a one-off copy: no
job refreshes them. The query takes every `way` with `highway` in `path|footway|track|steps` and a
`name`, and every `relation` with `route` in `hiking|foot`. Both use
`around:<radius_m>,<lat>,<lon>`, and the radius and the centre come from `site/areas.json`. The
bairro of a route comes from the OSM relations with `boundary=administrative` and `admin_level` 9 or
10 (or `place=suburb`, `neighbourhood` or `quarter`) inside the municipality that has the OSM tag
`IBGE:GEOCODIGO`; the Litoral do Paraná's file groups by municipality or landscape instead, from a
reverse lookup of each route's midpoint, because its routes cross several municipalities. Its lines
are simplified to about 10 m for the map (the length stays the full OSM geometry).

**Filter.** A way stays when `sac_scale` is set, or when it is a `highway=path` whose name does not
start with a street word. The Litoral do Paraná's file also keeps named `footway`, `track` and
`steps` ways: its coastal routes are mapped that way, and keeping only `path` ways would leave the
island and the bay nearly empty.

**Licence.** The data is OpenStreetMap data under the ODbL 1.0. The page shows the credit in the
map's attribution control and in the panel footer. Do not edit the files by hand: make them again
with the query above.
