# marola-site

The map at [marola.dev](https://marola.dev): every beach in an area ranked hour by hour for sea,
wind, waves, water quality and tide, with the trails near the coast and a place for studies about the
sea. It is one of the marola repos under the [umbrella](https://github.com/marola-dev/marola). Its
history before the split is marola's, filtered to these files.

The repo holds two builds of the site:

- **The new site** (`front/`, `back/`): the map page in Elm, the static pages and the server in
  Haskell, and the study submission feature. It is what marola.dev and marola.piabrota.art serve:
  piabrota2, a VPS in Brazil, runs it as NixOS units in
  [piabrota/nix-os](https://github.com/piabrota/nix-os) (`marola-site.nix`) behind nginx, with the
  boards it builds four times a day. No Cloudflare.
- **The legacy site** (`site/static/`): plain JavaScript over Mapbox GL JS. Nothing deploys it any
  more; its files stay until the cutover pull request removes them.

> [!IMPORTANT]
> **Migration notice: marola-dev is moving to pure functional programming.** This repo is the first
> step. The F# rewrite is gone: the map page is now Elm and the server and the static pages are
> Haskell ([ADR 0005](docs/adr/0005-elm-and-haskell.md)).
>
> What changes for you as a contributor:
>
> - New code is Elm or Haskell. The page goes in `front/` (Elm 0.19.1, elm-format); the server, the
>   pages and every script, check and harness go in `back/` (GHC 9.6, ormolu, hspec). Do not add
>   new JavaScript: [ADR 0007](docs/adr/0007-elm-or-haskell-hard-rule.md) allows it only where
>   nothing else can run, and every JavaScript file git tracks is on
>   [`scripts/js-allowlist.tsv`](scripts/js-allowlist.tsv) with the reason it cannot be Elm or
>   Haskell (`just js-check` fails on a file that is not listed).
> - Data errors are values (`Result`, `Maybe`), not exceptions or partial functions. Every effect
>   leaves Elm as data: elm/http and `Browser.Dom` for requests and focus, a port for what
>   JavaScript must do.
> - Tools come from `nix develop path:.`. CI runs the devkit's static, python and agents jobs plus
>   the Haskell and Elm jobs (ormolu, `cabal test all`, elm-format, elm-test, the built-page check,
>   the design check and the JS check); `just quality` runs the same checks locally.
>
> What is still left: the chat widget is not ported yet. `site/static/` stays the live site until the
> owners switch over. Then come the other marola-dev repos, each with its own ADR.

## What the new site is

| Part | What it does | Where |
|---|---|---|
| Map page | The map, the beach list and card, the layer rail and the footer, in Elm, bundled by Vite. Effects go through ports to a small JavaScript shell. MapLibre GL JS 6.17.0 over the site's own base map (a style, glyphs and one PMTiles file cut from a Protomaps build of OpenStreetMap; [ADR 0006](docs/adr/0006-self-hosted-basemap.md)), trails from OpenStreetMap | [`front/`](front) |
| Static pages | About, support, contact, contact-sent, news, members, privacy, takedown, partners and 404, in pt-BR (at the root), English, Japanese and Traditional Chinese (under `en/`, `ja/` and `zh-Hant/`), rendered at build time from Markdown by a Haskell program | [`back/pages`](back/pages), [`site/content`](site/content) |
| Server | Haskell (warp, SQLite). Serves the files, sends the security headers, takes the contact form, the GitHub login and the study API and pages. Listens on `127.0.0.1` behind nginx | [`back/server`](back/server) |
| Study submission | Anyone with a GitHub account of 7 days or more publishes a study as a PDF with metadata: the GitHub repository of the code and the archive of the study (Zenodo, arXiv or aiXiv) are required. It shows the notice "not reviewed, not medical advice". The board can hide a study | [ADR 0004](docs/adr/0004-study-submission.md), [board runbook](docs/6-board.md) |
| Tools | The checks and harnesses in Haskell (`marola-tools`): the design check, the JS allowlist check, the offline board fixtures, the Elm test fixture generator, the fake GitHub and the smoke suites (server, package, studies, submit, board) | [`back/tools`](back/tools) |
| Visual system | Tokens, type, components and contrast. `just design-check` compares it with the stylesheet | [`DESIGN.md`](DESIGN.md), [`front/public/style.css`](front/public/style.css) |
| Nix package | The server, the pages and the map page as one package that builds with no network | [`nix/package.nix`](nix/package.nix), [`flake.nix`](flake.nix) |

The decisions are in [ADR 0005](docs/adr/0005-elm-and-haskell.md) (Elm and Haskell; it supersedes
the language choices of ADRs 0001 to 0003, whose MapLibre, hosting and page decisions stand),
[ADR 0004](docs/adr/0004-study-submission.md) (study submission),
[ADR 0006](docs/adr/0006-self-hosted-basemap.md) (the base map is the site's own: Protomaps tiles in one
PMTiles file on the host),
[ADR 0007](docs/adr/0007-elm-or-haskell-hard-rule.md) (Elm or Haskell;
JavaScript only when it is 100 % necessary, held by the allowlist check) and
[ADR 0008](docs/adr/0008-embeddable-map.md) (the embeddable map: an iframe of a chrome-less page,
behind an allowlist the server owns; the plan of eight tasks is in the ADR).

### Architecture

[![marola-site and the repos around it: marola-corpus and marola-ml feed marola-app, whose board JSON the map client reads; the Elm client and the Haskell static pages make dist, which the Haskell server serves; nix/package.nix packs them, and piabrota/nix-os runs the package on piabrota2 behind nginx for piabrota.art; the host holds the base map's tiles and GIBS gives the satellite layers, GitHub OAuth the login, marola-dev/.github the members page; marola-devkit and the umbrella build docs.marola.dev](docs/img/architecture.png)](docs/img/architecture.png)

How to read it: each row is a group of repos or services, and an arrow is what one hands to the
next. Orange boxes are outside marola. Not shown: marola-oods' opt-in
water cache to marola-app. Source: [`docs/archify/architecture.json`](docs/archify/architecture.json),
drawn with the umbrella's Archify pin and `scripts/figure.sh` (in a marola checkout).

### Data flow

- **Boards.** The app image pinned in [`marola-image`](marola-image) writes each area's board (the
  ranked beaches, hour by hour). This repo never builds the app. The legacy build runs the image
  and puts the boards in `site/dist/data/`. The server reads `MAROLA_DATA` (default `data/`), then
  `dist/data/`; `/data/areas.json`, the picker's list, is always the build's. `just dist-build --fixtures` writes one board per area from
  [`site/fixtures/board.json`](site/fixtures/board.json) for an offline preview.
- **Trails.** `front/public/data/trails/<area>.json` holds the hiking routes, from OpenStreetMap
  (ODbL). The map page fetches the file of the area on show. See [the reference](docs/4-reference.md#trail-files).
- **Water points.** `front/public/data/water/<area>.json` holds an area's official sampling points
  when the board cannot draw them: the app matches a point to a beach by name and never falls back
  to distance for an inland name, so a lagoon point reaches no beach. The page draws the file's
  points on the water layer, once per place. Only the Complexo Lagunar has one (IMA/SC, beaches and
  lagoons). See [the reference](docs/4-reference.md#the-areas-own-water-file).
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

## Embed the map

Any site can frame marola's map with one `<iframe>`, no script of ours and no key: `/embed` is the
same page with the navigation, the tool row and the footer off (ADR 0008). The map, the layers, the
trails, the beach card, the emergency button and the "not a lifeguard" notice stay, with marola's
attribution and a slim strip for the language.

```html
<iframe src="https://marola.dev/embed?area=complexo-lagunar&lang=pt-BR"
        title="marola: as condições da lagoa hoje"
        width="100%" height="600" loading="lazy"></iframe>
```

- `area` is an id from [`site/areas.json`](site/areas.json) (`floripa`, `rio`, `salvador`,
  `complexo-lagunar`). With no `day`, the embed shows today's board; `day=YYYY-MM-DD` pins a past one.
- `layer` picks the layer on show (`water`, `wind`, `waves`, …), `lang` the language (`pt-BR`, `en`,
  `ja`, `zh-Hant`), and `beaches=0` / `trails=0` start with those hidden.
- A bounded area frames its own waters: the Complexo Lagunar opens on the lagoons (Imaruí, Mirim,
  Santo Antônio, Cabeçuda, Camacho, Arroio Corrente) with **Canto das Águas**, in Taquaraçatuba,
  Imaruí, pinned inside and linked to the institute's site, opens on the bathing-water layer, and
  stays there instead of fitting all the beaches. That is the first
  embed: the institute's [ecomonitoring platform](https://cantodasaguas.org/) shows the lagoon on
  today's date, in Portuguese.
- The server frames `/embed` only for the origins in `MAROLA_EMBED_FROM`, one per line, a file on the
  host ([hosting](docs/5-hosting.md#variables)). Every other page, and an empty list, keeps
  `frame-ancestors 'none'`: a partner asks to be added, and nobody else can frame marola. No origin
  is added by an agent.

The embed needs no JavaScript on the partner's page and sends nothing back: the iframe reads its
size from its own CSS, and what it shows is public on marola.dev too.

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
another build), `just design-check` and `just js-check` (both `marola-tools`, in Haskell). `just --list` shows all of them.
`scripts/nav_measure.sh` measures the phone nav in a real browser. It needs a Chromium and is not in
`just quality`.

## Build it with Nix

```bash
nix build .#default     # result/bin/marola-server and result/share/marola/dist
just package-smoke      # starts that server and checks four URLs
```

The build has no network: the Haskell packages come from nixpkgs' Hackage set, the npm packages from
`front/package-lock.json` and the Elm packages from [`nix/elm-srcs.nix`](nix/elm-srcs.nix) and
[`nix/registry.dat`](nix/registry.dat), all with real hashes confirmed by `nix build` on 2026-11-12
([docs/5-hosting.md](docs/5-hosting.md#build-with-nix)). After a change to `front/package-lock.json`
the npm hash is stale: the next `nix build` fails and prints the right one.

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

Nothing here deploys. piabrota2, in Brazil, serves the new site at the commit piabrota/nix-os pins
(`marola-site.nix`), and four times a day runs the pinned image's `--site` over every area into the
server's board folder (the beach lists stay on the box, so Overpass is asked only for an area without
one). `404.html` forwards `marola.dev/docs/*` to [docs.marola.dev](https://docs.marola.dev).

## Repo map

| Piece | Where |
|---|---|
| The new site | [`front/`](front) (Elm), [`back/`](back) (Haskell), [`cabal.project`](cabal.project) |
| The tools | [`back/tools/`](back/tools) (`marola-tools`), and the allowlist it checks: [`scripts/js-allowlist.tsv`](scripts/js-allowlist.tsv) |
| The pages' text | [`site/content/`](site/content), the chrome words in [`site/i18n/`](site/i18n) |
| The legacy page | [`site/static/`](site/static) |
| The areas | [`site/areas.json`](site/areas.json) |
| The board contract | the image's `board.schema.json`, vendored as [`site/board.schema.json`](site/board.schema.json) |
| The members list | [`site/members/MEMBERS.md`](site/members/MEMBERS.md), pinned by [`site/members.version`](site/members.version) |
| The legacy build and deploy (on piabrota2, INEA and INEMA) | [`docs/3-development.md`](docs/3-development.md#the-build-and-deploy-on-piabrota2-not-github-actions) |

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
The base map is the site's own: tiles cut with [Protomaps](https://protomaps.com) from the data of OpenStreetMap
contributors, served by the site's server. The satellite layers are NASA GIBS.

## Gemini review

Request the reviewer `marola-dev/gemini` on a pull request (sidebar → Reviewers, or
`gh pr edit <N> --add-reviewer marola-dev/gemini`). `marola-gemini-bot` posts one review with at
most 10 inline comments tagged `[high]`/`[medium]`/`[low]`, then pushes one commit with the fixes
it is sure of, after `node scripts/site_check.js` passes. Request it again after new commits for a fresh review. It runs only when
asked, reviews fork pull requests without pushing to them, and never edits `.github/`. `.github/workflows/gemini.yml`
calls the devkit's [`gemini-review`](https://github.com/marola-dev/marola-devkit/blob/main/docs/4-reference_workflows.md#gemini-review)
workflow.
