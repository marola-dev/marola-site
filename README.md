# marola-site

The map at [marola.dev](https://marola.dev): every beach in an area ranked hour by hour for sea,
wind, waves, water quality and tide, with the trails near the coast and a place for studies about the
sea. It is one of the marola repos under the [umbrella](https://github.com/marola-dev/marola). Its
history before the split is marola's, filtered to these files.

The repo holds two builds of the site:

- **The new site** (`front/`, `back/`): the map page in Elm, the static pages and the server in
  Haskell, and the study submission feature. It is built and tested, and it is not what marola.dev
  serves yet.
- **The legacy site** (`site/static/`): plain JavaScript over Mapbox GL JS. `.github/workflows/site.yml`
  still builds and publishes it, every three hours, to the Cloudflare Worker behind marola.dev. The
  switch from the legacy site to the new one is a decision of the owners. It is not made here.

> [!IMPORTANT]
> **Migration notice: marola-dev is moving to pure functional programming.** This repo is the first
> step. The F# rewrite is gone: the map page is now Elm and the server and the static pages are
> Haskell ([ADR 0005](docs/adr/0005-elm-and-haskell.md)).
>
> What changes for you as a contributor:
>
> - New code goes in `front/` (Elm 0.19.1, elm-format) or `back/` (GHC 9.6, ormolu, hspec). Do not
>   add new JavaScript, except a port or a small FFI file in `front/js/` that says why it exists.
> - Data errors are values (`Result`, `Maybe`), not exceptions or partial functions. Every effect
>   leaves Elm as data through a port.
> - Tools come from `nix develop path:.`. CI runs `cabal test all`, `npm test` (elm-test), the
>   built-page check and the server smoke test.
>
> What is still left: the chat widget is not ported yet. `site/static/` stays the live site until the
> owners switch over. Then come the other marola-dev repos, each with its own ADR.

## What the new site is

| Part | What it does | Where |
|---|---|---|
| Map page | The map, the beach list and card, the layer rail and the footer, in Elm, bundled by Vite. Effects go through ports to a small JavaScript shell. MapLibre GL JS 6.17.0, OpenFreeMap `liberty` base map, trails from OpenStreetMap | [`front/`](front) |
| Static pages | About, support, contact, news, members, privacy, takedown and 404, in pt-BR (at the root) and English (under `en/`), rendered at build time from Markdown by a Haskell program | [`back/pages`](back/pages), [`site/content`](site/content) |
| Server | Haskell (warp, SQLite). Serves the files, sends the security headers, takes the contact form, the GitHub login and the study API and pages. Listens on `127.0.0.1` behind nginx | [`back/server`](back/server) |
| Study submission | Anyone with a GitHub account of 7 days or more publishes a study as a PDF with metadata. It shows the notice "not reviewed, not medical advice". The board can hide a study | [ADR 0004](docs/adr/0004-study-submission.md), [board runbook](docs/6-board.md) |
| Visual system | Tokens, type, components and contrast. `just design-check` compares it with the stylesheet | [`DESIGN.md`](DESIGN.md), [`front/public/style.css`](front/public/style.css) |
| Nix package | The server, the pages and the map page as one package that builds with no network | [`nix/package.nix`](nix/package.nix), [`flake.nix`](flake.nix) |

The decisions are in [ADR 0005](docs/adr/0005-elm-and-haskell.md) (Elm and Haskell; it supersedes
the language choices of ADRs 0001 to 0003, whose MapLibre, hosting and page decisions stand) and
[ADR 0004](docs/adr/0004-study-submission.md) (study submission).

### Architecture

[![marola-site and the repos around it: marola-corpus and marola-ml feed marola-app, whose board JSON the map client reads; the Elm client and the Haskell static pages make dist, which the Haskell server serves; nix/package.nix packs them, and piabrota/nix-os runs the package on piabrota2 behind nginx for piabrota.art; OpenFreeMap and GIBS give the tiles, GitHub OAuth the login, marola-dev/.github the members page; marola-devkit and the umbrella build docs.marola.dev](docs/img/architecture.png)](docs/img/architecture.png)

How to read it: each row is a group of repos or services, and an arrow is what one hands to the
next. Orange boxes are outside marola. Not shown: the legacy `site/static` build, which
`site.yml` still deploys to the Cloudflare Worker behind marola.dev, and marola-oods' opt-in
water cache to marola-app. Source: [`docs/archify/architecture.json`](docs/archify/architecture.json),
drawn with the umbrella's Archify pin and `scripts/figure.sh` (in a marola checkout).

### Data flow

- **Boards.** The app image pinned in [`marola-image`](marola-image) writes each area's board (the
  ranked beaches, hour by hour). This repo never builds the app. The legacy build runs the image
  and puts the boards in `site/dist/data/`. The server reads `MAROLA_DATA` (default `data/`), then
  `dist/data/`. `just dist-build --fixtures` writes one board per area from
  [`site/fixtures/board.json`](site/fixtures/board.json) for an offline preview.
- **Trails.** `front/public/data/trails/<area>.json` holds the hiking routes, from OpenStreetMap
  (ODbL). The map page fetches the file of the area on show. See [the reference](docs/4-reference.md#trail-files).
- **Studies.** The server keeps the accounts, the API keys, the study rows and the reports in SQLite
  (`MAROLA_DB`) and the PDFs in a folder (`MAROLA_STUDIES`). The study pages and the Atom feed are
  rendered by the server from those rows.
- **Pages.** `marola-pages` (`back/pages`) renders the static pages into `dist/` at build time.

### Static and dynamic

Static, in `dist/`: the map page and its JavaScript, `style.css`, the vendored libraries and
fonts, the board and trail JSON, and the pages from Markdown. Dynamic, in the server: `POST /contact`,
`/submit`, `/studies`, `/studies/<id>`, `/studies.atom`, `/account`, `/report/<id>`, `/auth/github/*`
and `/api/v1/*`. Every page is served with a Content-Security-Policy that allows scripts and styles
from the site itself only, so a content page has no inline script and no inline style.

## Run it

```bash
nix develop path:.             # the dev shell: node, elm, ghc, cabal, python3 and the lint tools
just dist-build --fixtures     # build the Elm page, render the pages and write fixture boards into dist
just server-run                # http://127.0.0.1:8080, state in .tmp/marola.db
```

`flake.lock` is committed, so `nix develop` and `nix build` use the same nixpkgs as everyone else.

## Test it

```bash
just quality    # every check CI runs that needs no docker: the Elm and Haskell tests, design-check, the legacy checks, docs-lint
```

The parts have their own recipes: `just front-test` (elm-test), `just back-test` (the pages' and the
server's hspec suites), `just front-fmt` and `just back-fmt` (elm-format and ormolu), `just front-check` (the built page in a fake DOM, no browser),
`just server-smoke` (the built server on a free port), `just pages-parity <dir>` (the pages against
another build) and `just design-check`. `just --list` shows all of them.
`scripts/nav_measure.sh` measures the phone nav in a real browser. It needs a Chromium and is not in
`just quality`.

## Build it with Nix

```bash
nix build .#default     # result/bin/marola-server and result/share/marola/dist
just package-smoke      # starts that server and checks four URLs
```

The package has not been built since the move to Elm and Haskell: its npm and Elm hashes are
placeholders until a first build with network ([docs/5-hosting.md](docs/5-hosting.md#build-with-nix)).

## Deploy it

The host runs the published server behind nginx, under systemd. The variables, the nginx and systemd
settings, the GitHub login, the backups and the rollback are in [docs/5-hosting.md](docs/5-hosting.md).
An agent does not deploy.

What the repository checks about its code, its security and its agent tooling, and what it does not: [docs/7-quality.md](docs/7-quality.md). To report a vulnerability: [SECURITY.md](SECURITY.md).

## The legacy site

`site/static/` is the page that marola.dev serves today. It does not use `front/` or `back/`.

```bash
just site-build floripa   # one area's boards from the pinned image, plus the page, into site/dist (docker, network)
just site-serve           # http://localhost:8000
```

Without docker, `node scripts/site_check.js` renders `site/static/app.js` against
`site/fixtures/board.json` in a stub DOM.

`site.yml` runs every three hours, on a push to `main` that touches the page or the pin, and when a
`site-data` writer dispatches `site-data-updated`. It pulls the pinned image, checks the page against
the image's board schema, builds every area's boards (beach lists come from the Actions cache, so
Overpass is asked only for an area without one), adds the page and the `coverage/`, `smoke/` and
`stats/` panels from the `site-data` branch, and deploys to the Cloudflare Worker that serves
`marola.dev` (static assets on the free plan, `wrangler.jsonc`), with the same files on GitHub Pages as
a fallback. `404.html` forwards `marola.dev/docs/*` to [docs.marola.dev](https://docs.marola.dev).

## Repo map

| Piece | Where |
|---|---|
| The new site | [`front/`](front) (Elm), [`back/`](back) (Haskell), [`cabal.project`](cabal.project) |
| The pages' text | [`site/content/`](site/content), the chrome words in [`site/i18n/`](site/i18n) |
| The legacy page | [`site/static/`](site/static) |
| The areas | [`site/areas.json`](site/areas.json) |
| The board contract | the image's `board.schema.json`, vendored as [`site/board.schema.json`](site/board.schema.json) |
| The members list | [`site/members/MEMBERS.md`](site/members/MEMBERS.md), pinned by [`site/members.version`](site/members.version) |
| The deploy workflow (legacy) | [`site.yml`](.github/workflows/site.yml) |
| The self-hosted runner in Brazil (INEA and INEMA) | [`docs/3-development.md`](docs/3-development.md#the-self-hosted-runner-in-brazil) |

## Contracts

| Direction | What |
|---|---|
| Consumes | the app image pinned in [`marola-image`](marola-image), run with `--site --areas site/areas.json`; the `site-data` branch's `coverage/` and `smoke/` (written by the app), `stats/` (written by the umbrella) |
| Publishes | the legacy site at marola.dev; `site/areas.json` and `site/fixtures/board.json`, which the app keeps checked-in copies of; `README.md` and `docs/`, aggregated into [docs.marola.dev](https://docs.marola.dev) |
| Pinned by | nothing: this repo is a leaf |

## Checks of the legacy site

- `node scripts/site_check.js`: `app.js` and `flow.js` in a stub DOM and Mapbox GL against the
  fixture board, which must match the schema.
- `node scripts/redirect_check.js`: the 404 page sends `/docs/*` to `docs.marola.dev`, path kept,
  and leaves every other missing path on the not-found page.
- `scripts/board-schema.sh --check`: the vendored schema is the pinned image's.
- `python3 scripts/site_live_check.py`: what marola.dev serves (the boards and the crawl files), every six hours
  (`site-health.yml`).

More: [docs/1-design.md](docs/1-design.md) (the legacy page: files, the board → markers mapping, CSP),
its sibling [docs/1-design_chat-widget.md](docs/1-design_chat-widget.md) (the chat widget),
[docs/2-libraries.md](docs/2-libraries.md) (vendored libraries and the Elm page's and the Haskell packages),
[docs/3-development.md](docs/3-development.md) (the build and deploy, the Elm and Haskell site, the `site-data`
layout, health checks, i18n, bumping the app image, the `MIP:` trailer),
[docs/4-reference.md](docs/4-reference.md) (`areas.json` fields, the tile policy, the board schema
pin, trail files), [docs/5-hosting.md](docs/5-hosting.md) (hosting), [docs/6-board.md](docs/6-board.md)
(the runbook for hiding a study), [DESIGN.md](DESIGN.md) and [AGENTS.md](AGENTS.md).

## Credits

The emergency button at the top of the map lists Brazil's free emergency numbers (193, 190, 192,
185, 199), each a tap to call. The idea is from Carlos Toledo's
[swell-floripa](https://swell-floripa.vercel.app/) ([@carlostoledo1891](https://github.com/carlostoledo1891)).
The base map is [OpenFreeMap](https://openfreemap.org) with data from OpenStreetMap contributors. The
satellite layers are NASA GIBS.

## Gemini review

Request the reviewer `marola-dev/gemini` on a pull request (sidebar → Reviewers, or
`gh pr edit <N> --add-reviewer marola-dev/gemini`). `marola-gemini-bot` posts one review with at
most 10 inline comments tagged `[high]`/`[medium]`/`[low]`, then pushes one commit with the fixes
it is sure of, after `node scripts/site_check.js` passes. Request it again after new commits for a fresh review. It runs only when
asked, reviews fork pull requests without pushing to them, and never edits `.github/`. `.github/workflows/gemini.yml`
calls the devkit's [`gemini-review`](https://github.com/marola-dev/marola-devkit/blob/main/docs/4-reference_workflows.md#gemini-review)
workflow.
