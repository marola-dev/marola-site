# AGENTS.md

Instructions for any AI coding agent working in **marola-site**. This is the repo layer
(MIP-0070 §5.1): the workspace rules live in the umbrella's
[AGENTS.md](https://github.com/marola-dev/marola/blob/main/AGENTS.md); this file says what this
repo is and where it differs.

<!-- invariants:start -->
## Org invariants

Non-negotiable in every marola repo; a repo may make these stricter, never looser (MIP-0070 §5.1).

- **Cost and deployment safety**: never provision or deploy a paid cloud resource without explicit human confirmation first ([AGENTS.md](AGENTS.md#cost--deployment-safety-hard-rule)).
- **No secrets in code**: never hardcode a key/connection string/secret; `.env.example` holds placeholders only ([AGENTS.md](AGENTS.md#cost--deployment-safety-hard-rule)).
- **The agent-ready gate**: an agent may only begin implementation on an issue carrying `agent-ready` ([AGENTS.md](AGENTS.md#issue-tracking-hard-rule)).
- **The three commit trailers**: commits carry three trailers and nothing else — `Tested:`, `Cost:`, and `Co-Authored-By: Claude <noreply@anthropic.com>` ([AGENTS.md](AGENTS.md#attribution-and-cost-accounting-hard-rule)).
- **Phase discipline**: work one phase at a time; never start a later phase before the current one is done ([AGENTS.md](AGENTS.md#phase-discipline-hard-rule)).
<!-- invariants:end -->

## What this repo is

The map at [marola.dev](https://marola.dev): a static page that shows every area's precomputed
boards (MIP-0005), with no server, no LLM and no per-visitor cost.

- `site/static/`: the page (`index.html`, `about.html`, `support.html` behind Donate, `app.js`,
  `ui.js`, `style.css`, the chat widget, vendored Leaflet) and `404.html`, which forwards the old
  `marola.dev/docs/*` links to `docs.marola.dev`.
- `site/i18n/`: the pt-BR and English catalogs (MIP-0054). `scripts/i18n_bundle.py` checks them
  and writes `site/static/i18n.js`; edit the catalogs, never `i18n.js`.
- `site/areas.json`: the areas the boards are built for. `site/fixtures/board.json`: the board the
  harness renders. `site/board.schema.json`: the board contract, vendored from the pinned image.
- `scripts/`: `site_check.js` (app.js in a stub DOM and Leaflet), `redirect_check.js` (the 404
  forwarder), `board-schema.sh` (the image pin and its schema), `stamp_site_version.sh`,
  `site_live_check.py` (what marola.dev actually serves), `site-data-push.sh` (the retrying push
  every `site-data` writer uses), `mip-trailer-check.sh`.
- `DESIGN.md`: the visual style reference (the Co2 editorial style); its fonts' substitutes,
  Cormorant Garamond and Inter, are self-hosted in `site/static/vendor/fonts/`.
- `.claude/skills/site-frontend/`: this repo's own skill for anything a visitor sees;
  `design-system/` applies `DESIGN.md` to it, `ptbr-humanizer/` keeps the Portuguese natural, and
  `citizen-science-site/` keeps sources, freshness, limits and the way to contribute on the page.

## What it consumes and produces

| Direction | Contract |
|---|---|
| app → site | The image in `marola-image` (`ghcr.io/marola-dev/marola-app:jvm-<sha>@sha256:<digest>`, both parts required). `site.yml` runs it with `--site --areas site/areas.json --site-out site/dist`; it writes board data only. The image's `board.schema.json` is the contract |
| app, umbrella → site | The `site-data` branch: `coverage/` and `smoke/` (the app's CI and `docker-smoke.yml`), `stats/` (the umbrella). Writers push with the cross-repo token, then send `repository_dispatch` `site-data-updated` |
| site → app | `site/areas.json` and `site/fixtures/board.json`; the app's tests keep checked-in copies |
| site → umbrella | `README.md` and `docs/`, aggregated into docs.marola.dev (`notify-umbrella.yml`) |

No workflow here builds the app or reads its tree (MIP-0070 §5.4).

**Bumping the image.** Put the new jvm tag and its digest in `marola-image` (the tag is
`jvm-<short sha>` from the app's `docker.yml`; `docker buildx imagetools inspect <ref>` prints the
digest), then run `just board-schema --update` and commit both files together. `board-schema.yml`
fails a PR whose vendored schema differs from the image's, and `site.yml` checks the page against
the image's own schema before every deploy. The jvm image is required: the schema is read out of
`/app/marola.jar`, which the native image does not have.

## Commands

```bash
nix develop               # node, python, the lint tools and the devkit's tools; links .devkit
just quality              # every gate CI runs that needs no docker or network
just site-build floripa   # boards from the pinned image + the page into site/dist (docker, network)
just site-serve           # http://localhost:8000
just site-live-check      # what marola.dev serves now
just board-schema --check # the vendored schema against the pinned image's (docker)
```

The devkit's git hooks (`core.hooksPath .devkit/.githooks`, set by the dev shell) run
`just precommit` and `just prepush`.

## Cost & deployment safety (hard rule)

As in the umbrella. `site.yml` deploys to GitHub Pages (free) on a schedule and on `main`; an agent
does not trigger a deploy by hand (`just site-deploy` is denied in `.claude/settings.json`).

## Issue tracking (hard rule)

An agent starts work only on an issue carrying `agent-ready`, in this repo (MIP-0070 §5.7).

## Attribution and cost accounting (hard rule)

Commits carry `Tested:`, `Cost:` and `Co-Authored-By: Claude <noreply@anthropic.com>`.
**Stricter here:** a commit touching `site/static/**` also carries `MIP: MIP-NNNN` or
`MIP: none — <reason>`; `just prepush` runs `scripts/mip-trailer-check.sh` over the pushed
commits (`origin/main..HEAD` when the hook does not pass the pushed refs on).

## Phase discipline (hard rule)

The phase list is the umbrella's `docs/PHASES.md`. Site work serves the current phase.

## Code style

Plain JavaScript, no framework and no build step; the page makes no third-party requests and keeps
`script-src 'self'`. A visible change goes through the `site-frontend`, `design-system`, `ptbr-humanizer` and `citizen-science-site` skills, `node scripts/site_check.js`
and before/after screenshots. Shell: `set -euo pipefail`, shellcheck-clean. Python: ruff. Comments
only for why, a trap, or a pointer, as the umbrella's AGENTS.md spells out.
