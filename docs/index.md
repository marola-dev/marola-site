# marola-site

The static map at [marola.dev](https://marola.dev) (MIP-0005, split out by MIP-0070).

## What builds the page

| Piece | Where |
|---|---|
| The page | [`site/static/`](https://github.com/marola-dev/marola-site/tree/main/site/static) |
| The words | [`site/i18n/`](https://github.com/marola-dev/marola-site/tree/main/site/i18n): `pt-BR.json` (the source), `en.json`, and a translator note per key in `context.json`, bundled into `site/static/i18n.js` |
| The areas | [`site/areas.json`](https://github.com/marola-dev/marola-site/blob/main/site/areas.json) |
| The boards | the app image pinned in [`marola-image`](https://github.com/marola-dev/marola-site/blob/main/marola-image), run with `--site --areas site/areas.json` |
| The board contract | the image's `board.schema.json`, vendored as [`site/board.schema.json`](https://github.com/marola-dev/marola-site/blob/main/site/board.schema.json) |
| The panels | the `site-data` branch: `coverage/`, `smoke/` (from the app), `stats/` (from the umbrella) |
| The deploy | [`site.yml`](https://github.com/marola-dev/marola-site/blob/main/.github/workflows/site.yml), GitHub Pages, `CNAME marola.dev` |

## Checks

- `node scripts/site_check.js`: `app.js` in a stub DOM and Leaflet against the fixture board, which
  must match the schema.
- `node scripts/redirect_check.js`: the 404 page sends `/docs/*` to `docs.marola.dev`, path kept,
  and leaves every other missing path on the not-found page.
- `python3 scripts/i18n_bundle.py --check`: both catalogs have the same keys, no empty value, the
  same arguments per message, a context note per key, and `i18n.js` is not stale.
- `scripts/board-schema.sh --check`: the vendored schema is the pinned image's.
- `python3 scripts/site_live_check.py`: what marola.dev serves, every six hours
  (`site-health.yml`).

## Languages

The page is Portuguese first, with English one click away
([MIP-0054](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0054-portuguese-first-experience.md)
§5.5, §5.8). The HTML source text is pt-BR. `ui.js` picks the language from `?lang=`, then the
visitor's stored choice, then the browser's languages, then pt-BR, and rewrites every `data-i18n*`
element from the catalog. The body text of `about.html` and `support.html` is one `article` per
language, and CSS shows the one matching `<html lang>`.

To change or add a string, edit both `site/i18n/pt-BR.json` and `site/i18n/en.json`, give a new key
a note in `context.json`, run `just i18n`, and commit the regenerated `site/static/i18n.js` with
them. `?lang=x-pseudo` renders a generated pseudo-locale that shows any text left outside the
catalog.

## Updating the app image

Edit `marola-image` to the new `jvm-<sha>` tag and its digest, run `just board-schema --update`,
and commit both. A board schema change in the app is two PRs: the app's first, then this bump.
