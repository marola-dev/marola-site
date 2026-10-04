# Development

## Updating the app image

Put the new jvm tag and its digest in [`marola-image`](https://github.com/marola-dev/marola-site/blob/main/marola-image) (the tag is
`jvm-<short sha>` from the app's `docker.yml`; `docker buildx imagetools inspect <ref>` prints the
digest), then run `just board-schema --update` and commit both files together. `board-schema.yml`
fails a PR whose vendored schema differs from the image's, and `site.yml` checks the page against
the image's own schema before every deploy. The jvm image is required: the schema is read out of
`/app/marola.jar`, which the native image does not have. A board schema change in the app is two
PRs: the app's first, then this bump.

## The TypeScript

`site/src/` is strict TypeScript (`tsconfig.json`: `strict`, `noUncheckedIndexedAccess`,
`exactOptionalPropertyTypes`, `erasableSyntaxOnly`). esbuild bundles each entry point (`app.ts`,
`ui.ts`, `chat.ts`) into one minified IIFE in `site/static/`, which keeps the CSP at
`script-src 'self'` with no module loading. `tsc` only typechecks; esbuild only strips types.
The Mapbox types are a minimal ambient file (`site/src/globals.d.ts`), not the 67 MB package.

`npm run check` runs `tsc`, ESLint (typescript-eslint `strictTypeChecked` and
`stylisticTypeChecked`), the build and `node --test`. The tests run the `.ts` files directly with
Node's type stripping (Node 22.18 or newer). The map tests bundle `app.ts` in memory and run it in
a `vm` context against a stub DOM and Mapbox GL, so they never test a stale bundle. The page tests
loop over every `site/static/*.html`, so a new page gets the CSP, nav, i18n and publish checks
without new test code.

## The build and deploy (`site.yml`)

Runs on a schedule (every three hours), on a push to `main` touching `site/**`, `marola-image` or
the workflow itself, on `repository_dispatch: site-data-updated` (sent by every `site-data`
writer), and on `workflow_dispatch` (optionally one area). `concurrency: site` queues a run rather
than cancelling one that already paid for its Overpass query.

The job: build the page's scripts (`npm ci`, `npm run build`) → pull the pinned image (two
tries) → check the tests and the page against the image's
own board schema → build every area's boards (or one, with an area input) → copy the static page
into `site/dist` → write the Mapbox token and style into `mapbox-config.js` → cache-bust
`index.html`'s script/style tags with `?v=<sha>` (Pages caches each file independently) → add the
`site-data` branch's panels → a required-files check (a half-built site must never reach Pages) →
the publish allowlist (only the page, its assets and `data/`, `smoke/`, `coverage/`, `stats/` go
out) → a `CNAME` file → deploy to GitHub Pages.

## The `site-data` branch layout

An orphan branch, never deployed by the workflows that write it: `coverage/` and `smoke/` (the
app's CI and `docker-smoke.yml`), `stats/` (the umbrella). Each writer pushes with
`scripts/site-data-push.sh` (retries on a rejected push, replaying its one commit onto the new
tip) and then sends `repository_dispatch: site-data-updated` so `site.yml` refreshes the panels
without waiting for its schedule. A directory missing from the branch just means no panel for it;
a missing branch means none of the three.

## Health checks

`site-health.yml` runs `python3 scripts/site_live_check.py` against the live site every six hours,
separate from `site.yml` on purpose: a red run here means upstream data is missing (a bulletin
gone stale, a provider down), not that the build is broken, so it must never block a deploy.

## i18n bundling

`site/i18n/*.json` (`pt-BR` is the source locale, `en` is translated, `x-pseudo` is generated,
never translated) are checked and bundled into `site/src/catalog.ts` by `scripts/i18n_bundle.py`
(MIP-0054 §5.8): every locale has exactly `pt-BR`'s keys with no empty value, every message parses
in the ICU subset `site/src/i18n.ts` implements and names the same arguments as `pt-BR`'s, and every key has a
note in `context.json`. Edit the catalogs, never `catalog.ts`; `--check` fails a stale committed
bundle.

## The `MIP:` trailer

A commit touching `site/static/**` or `site/src/**` carries `MIP: MIP-NNNN` or `MIP: none — <reason>`.
`scripts/mip-trailer-check.sh` enforces it; `just prepush` runs it over the commits about to be
pushed.
