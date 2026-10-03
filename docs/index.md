# marola-site

The static map at [marola.dev](https://marola.dev) (MIP-0005, split out by MIP-0070).

## What builds the page

| Piece | Where |
|---|---|
| The page | [`site/static/`](https://github.com/marola-dev/marola-site/tree/main/site/static) |
| The areas | [`site/areas.json`](https://github.com/marola-dev/marola-site/blob/main/site/areas.json) |
| The boards | the app image pinned in [`marola-image`](https://github.com/marola-dev/marola-site/blob/main/marola-image), run with `--site --areas site/areas.json` |
| The board contract | the image's `board.schema.json`, vendored as [`site/board.schema.json`](https://github.com/marola-dev/marola-site/blob/main/site/board.schema.json) |
| The panels | the `site-data` branch: `coverage/`, `smoke/` (from the app), `stats/` (from the umbrella) |
| The deploy | [`site.yml`](https://github.com/marola-dev/marola-site/blob/main/.github/workflows/site.yml), GitHub Pages, `CNAME marola.dev` |

## Checks

- `node scripts/site_check.js`: `app.js` and `flow.js` in a stub DOM and Mapbox GL against the
  fixture board, which must match the schema.
- `node scripts/redirect_check.js`: the 404 page sends `/docs/*` to `docs.marola.dev`, path kept,
  and leaves every other missing path on the not-found page.
- `scripts/board-schema.sh --check`: the vendored schema is the pinned image's.
- `python3 scripts/site_live_check.py`: what marola.dev serves, every six hours
  (`site-health.yml`).

## Updating the app image

Edit `marola-image` to the new `jvm-<sha>` tag and its digest, run `just board-schema --update`,
and commit both. A board schema change in the app is two PRs: the app's first, then this bump.
