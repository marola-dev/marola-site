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
boards (MIP-0005), with no server and no LLM, over a Mapbox base map (free up to Mapbox's monthly
map-load tier, billed above it).

- `site/static/`: the page (`index.html`, `about.html`, `support.html` behind Donate, `app.js`,
  `ui.js`, `style.css`, `flow.js` (the WebGL wind and wave layer), `mapbox-config.js`, the chat
  widget, vendored Mapbox GL JS (its CSP build), Inter and the wave loop under `vendor/`, the
  about page's repo diagram under `img/`) and `404.html`, which forwards the old
  `marola.dev/docs/*` links to `docs.marola.dev`.
- `site/i18n/`: the pt-BR and English catalogs (MIP-0054). `scripts/i18n_bundle.py` checks them
  and writes `site/static/i18n.js`; edit the catalogs, never `i18n.js`.
- `site/areas.json`: the areas the boards are built for. `site/fixtures/board.json`: the board the
  harness renders. `site/board.schema.json`: the board contract, vendored from the pinned image.
- `scripts/`: `site_check.js` (app.js and flow.js in a stub DOM and Mapbox GL), `mapbox_config.sh`
  (the public Mapbox token into `mapbox-config.js` at deploy), `redirect_check.js` (the 404
  forwarder), `board-schema.sh` (the image pin and its schema), `stamp_site_version.sh`,
  `site_live_check.py` (what marola.dev actually serves), `site-data-push.sh` (the retrying push
  every `site-data` writer uses), `mip-trailer-check.sh`, and the Brazilian proxy's
  `br-proxy.sh` (the runner's router), `br-proxy-preflight.sh` (the flight check) and
  `br-proxy-node.sh` (`just br-proxy-node`).
- `ops/br-proxy/`: the Brazilian proxy pool that INEA and INEMA, which answer only Brazilian
  addresses, are reached through (#4): a volunteer node's compose file and allowlist, and
  [`JOIN.md`](ops/br-proxy/JOIN.md). `site.yml`'s flight check fails closed without a healthy
  node (secrets `TAILSCALE_OAUTH_CLIENT_ID`/`TAILSCALE_OAUTH_SECRET`, or the `MAROLA_BR_PROXY`
  override); the repo variable `BR_PROXY_REQUIRED=false` is a break glass, never a default. An
  agent never sets it.
- `DESIGN.md`: the visual system (tokens, type, components); Inter is self-hosted in
  `site/static/vendor/fonts/`.
- `.claude/skills/site-frontend/`: the entry point for anything a visitor sees; it orders the
  other frontend skills and settles their conflicts. `ptbr-humanizer/` keeps the Portuguese
  natural, `citizen-science-site/` keeps sources, freshness, limits and the way to contribute on
  the page; `frontend-design/`, `webapp-testing/` (anthropics/skills), `design-taste-frontend/`
  (Leonxlnx/taste-skill), `emil-design-eng/`, `review-animations/` and `break-ui/`
  (emilkowalski/skill), `karpathy-guidelines/` (forrestchang/andrej-karpathy-skills) and the eight
  `mapbox-*/` skills (mapbox/mapbox-agent-skills) are vendored unchanged with their licences.
- `.mcp.json`: the Playwright and Figma MCP servers (no keys; Figma signs in with OAuth).

## What it consumes and produces

See [README's Contracts](README.md#contracts). No workflow here builds the app or reads its tree
(MIP-0070 §5.4). Bumping the image: steps and gates in
[`docs/3-development.md`](docs/3-development.md#updating-the-app-image).

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

## Docs

`README.md` is the landing: what the repo is, how to run it, the repo map, its contracts, and
links. There is no `docs/index.md`. `docs/` holds numbered pages, not directories (MIP-0074 §5.2):
`1-design` (files, the board → markers mapping, CSP), `1-design_chat-widget`, `2-libraries`
(vendored Mapbox GL JS and the rest of `vendor/`, no build step), `3-development` (the build and
deploy, image bumps), `4-reference` (`areas.json`, the board schema pin). The H1 is the nav label.
A decision that starts and ends here is an ADR at `docs/adr/NNNN-<slug>.md`; anything crossing a
repo boundary is an umbrella MIP.

- **Links**: relative inside the repo, written to work on GitHub (`../AGENTS.md`, `../DESIGN.md`
  from `docs/`); the docs build turns a link outside `docs/` into its GitHub blob URL at the built
  commit (Appendix A). Another repo or the umbrella is linked by `https://docs.marola.dev/…`.
- **Recipes**: a doc names only this repo's and the devkit's recipes. Any other (the app's `just
  run -- --serve-chat`) carries the checkout marker: "in a marola-app checkout" in the same
  sentence, or `# in a marola-app checkout` as a fence's first line.
- `just quality` runs `docs-lint` (MIP-0074 §7): it fails on a foreign recipe without the marker,
  a relative link that leaves the repo, `docs/index.md`, and stale split-era wording.

## Cost & deployment safety (hard rule)

As in the umbrella. `site.yml` deploys to GitHub Pages (free) on a schedule and on `main`, and the
same files to the Cloudflare Worker `marola` (free static assets), which serves marola.dev
(MIP-0078); an agent does not
trigger a deploy by hand (`just site-deploy` is denied in `.claude/settings.json`).

The base map is Mapbox's, billed per map load above its free tier: the account, the token and
any billing setting are a human's. So are the Tailscale tailnet, its OAuth client and every pool
node's auth key (`ops/br-proxy/JOIN.md`). The token is a public `pk.` token restricted to marola.dev's
URLs, kept in the repo variable (or secret) `MAPBOX_PUBLIC_TOKEN` and written into
`mapbox-config.js` only at deploy; never commit one, and never an `sk.` token anywhere in the page.

## Issue tracking (hard rule)

An agent starts work only on an issue carrying `agent-ready`, in this repo (MIP-0070 §5.7).

## Attribution and cost accounting (hard rule)

Commits carry `Tested:`, `Cost:` and `Co-Authored-By: Claude <noreply@anthropic.com>`.
**Stricter here:** a commit touching `site/static/**` also carries `MIP: MIP-NNNN` or
`MIP: none — <reason>`; `just prepush` runs `scripts/mip-trailer-check.sh` over the pushed
commits (`origin/main..HEAD` when the hook does not pass the pushed refs on).

## Screenshots in the PR (hard rule)

A PR that changes anything a visitor sees shows it in its own body, not only in a chat thread:
before and after, desktop (1280 × 800) and phone (390 × 844), of every page the change touches.
Push the PNGs to the orphan `pr-screenshots` branch under `<pr-number>/` and embed them by their
`https://raw.githubusercontent.com/marola-dev/marola-site/pr-screenshots/<pr-number>/<file>.png`
URL, in a Before | After table. Images never go on `main`. A screenshot taken on a stand-in map
style (the sandbox can't reach Mapbox) says so under the table. No screenshots in the body, the
PR is not ready for review.

## Phase discipline (hard rule)

The phase list is the umbrella's `docs/PHASES.md`. Site work serves the current phase.

## Code style

Plain JavaScript, no framework and no build step; the page keeps `script-src 'self'`, and its one
third-party origins are Mapbox for the base map (style, tiles, fonts, the map-load count) and NASA
GIBS for the satellite layers (public, keyless tiles, fetched only when a visitor picks one). A visible
change goes through the `site-frontend` skill (which names the others), `node scripts/site_check.js`
and before/after screenshots. Shell: `set -euo pipefail`, shellcheck-clean. Python: ruff. Comments
only for why, a trap, or a pointer, as the umbrella's AGENTS.md spells out.
