# marola-site

The map at [marola.dev](https://marola.dev): every beach in an area ranked hour by hour for sea,
wind, waves, water quality and tide, computed a few times a day and served as a static page, over
a Mapbox base map with animated wind and wave layers drawn from the same boards. No server, no
tracking of its own, and no per-visitor cost while Mapbox's map loads stay in its free tier.

**Live, rebuilt every three hours** (MIP-0005, split out by MIP-0070). This repo holds the page,
the areas it covers and the workflow that publishes it. The boards themselves are written by the
marola app's image, pinned in [`marola-image`](https://github.com/marola-dev/marola-site/blob/main/marola-image); this repo never builds the app. It is
one of the marola repos under the [umbrella](https://github.com/marola-dev/marola), and its history
before the split is marola's, filtered to these files.

## Run it

```bash
nix develop               # or have node, python3 and docker on PATH
just site-build floripa   # one area's boards from the pinned image, plus the page, into site/dist
just site-serve           # http://localhost:8000
```

Without docker, `node scripts/site_check.js` renders `site/static/app.js` against
`site/fixtures/board.json` in a stub DOM.

## How it is published

`site.yml` runs every three hours, on a push to `main` that touches the page or the pin, and when
a `site-data` writer dispatches `site-data-updated`. It pulls the pinned image, checks the page
against the image's board schema, builds every area's boards, adds the page and the `coverage/`,
`smoke/` and `stats/` panels from the `site-data` branch, and deploys to GitHub Pages under
`marola.dev`. `404.html` forwards `marola.dev/docs/*` to [docs.marola.dev](https://docs.marola.dev).

## Repo map

| Piece | Where |
|---|---|
| The page | [`site/static/`](https://github.com/marola-dev/marola-site/tree/main/site/static) |
| The areas | [`site/areas.json`](https://github.com/marola-dev/marola-site/blob/main/site/areas.json) |
| The board contract | the image's `board.schema.json`, vendored as [`site/board.schema.json`](https://github.com/marola-dev/marola-site/blob/main/site/board.schema.json) |
| The deploy workflow | [`site.yml`](https://github.com/marola-dev/marola-site/blob/main/.github/workflows/site.yml) |

## Contracts

| Direction | What |
|---|---|
| Consumes | the app image pinned in [`marola-image`](https://github.com/marola-dev/marola-site/blob/main/marola-image), run with `--site --areas site/areas.json`; the `site-data` branch's `coverage/` and `smoke/` (written by the app), `stats/` (written by the umbrella) |
| Publishes | the static site at marola.dev; `site/areas.json` and `site/fixtures/board.json`, which the app keeps checked-in copies of; `README.md` and `docs/`, aggregated into [docs.marola.dev](https://docs.marola.dev) |
| Pinned by | nothing — this repo is a leaf |

## Checks

- `node scripts/site_check.js`: `app.js` and `flow.js` in a stub DOM and Mapbox GL against the
  fixture board, which must match the schema.
- `node scripts/redirect_check.js`: the 404 page sends `/docs/*` to `docs.marola.dev`, path kept,
  and leaves every other missing path on the not-found page.
- `scripts/board-schema.sh --check`: the vendored schema is the pinned image's.
- `python3 scripts/site_live_check.py`: what marola.dev serves, every six hours
  (`site-health.yml`).

More: [docs/3-development.md](docs/3-development.md) (the build and deploy, the `site-data`
layout, health checks, i18n, bumping the app image, the `MIP:` trailer) and
[AGENTS.md](https://github.com/marola-dev/marola-site/blob/main/AGENTS.md).
