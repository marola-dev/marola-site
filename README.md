# marola-site

The map at [marola.dev](https://marola.dev): every beach in an area ranked hour by hour for sea,
wind, waves, water quality and tide, computed a few times a day and served as a static page. No
server, no tracking, no per-visitor cost.

This repo holds the page, the areas it covers and the workflow that publishes it. The boards
themselves are written by the marola app's image, pinned in [`marola-image`](https://github.com/marola-dev/marola-site/blob/main/marola-image); this
repo never builds the app. It is one of the marola repos under the
[umbrella](https://github.com/marola-dev/marola) (MIP-0070), and its history before the split is
marola's, filtered to these files.

## Run it

```bash
nix develop               # or have node, python3 and docker on PATH
just site-build floripa   # one area's boards from the pinned image, plus the page, into site/dist
just site-serve           # http://localhost:8000
```

Without docker, `node scripts/site_check.js` renders `site/static/app.js` against
`site/fixtures/board.json` in a stub DOM.

## How it is published

`.github/workflows/site.yml` runs every three hours, on a push to `main` that touches the page or the
pin, and when a `site-data` writer dispatches `site-data-updated`. It pulls the pinned image, checks
the page against the image's board schema, builds every area's boards, adds the page and the
`coverage/`, `smoke/` and `stats/` panels from the `site-data` branch, and deploys to GitHub Pages
under `marola.dev`. `404.html` forwards `marola.dev/docs/*` to [docs.marola.dev](https://docs.marola.dev).

More in [docs/](docs/index.md) and [AGENTS.md](https://github.com/marola-dev/marola-site/blob/main/AGENTS.md).
