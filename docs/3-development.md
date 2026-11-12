# Development

## Updating the app image

Put the new jvm tag and its digest in [`marola-image`](https://github.com/marola-dev/marola-site/blob/main/marola-image) (the tag is
`jvm-<short sha>` from the app's `docker.yml`; `docker buildx imagetools inspect <ref>` prints the
digest), then run `just board-schema --update` and commit both files together. `board-schema.yml`
fails a PR whose vendored schema differs from the image's, and `site.yml` checks the page against
the image's own schema before every deploy. The jvm image is required: the schema is read out of
`/app/marola.jar`, which the native image does not have. A board schema change in the app is two
PRs: the app's first, then this bump.

## The build and deploy (`site.yml`)

Runs only on `workflow_dispatch` for now (one area, or `all`, the default), on the self-hosted
runner [below](#the-self-hosted-runner-in-brazil); no schedule, push or `repository_dispatch`. `concurrency: site` queues a run rather
than cancelling one that is already building.

The job: pull the pinned image (two tries) → check the harness and the page against the image's
own board schema → restore the beach lists → build every area's boards (or one, with an area input) → copy the static page
into `site/dist` → write the [crawl files](#crawl-files-and-metadata) → write the Mapbox token and style into `mapbox-config.js` → cache-bust
`index.html`'s script/style tags with `?v=<sha>` (Pages caches each file independently) → add the
`site-data` branch's panels → a required-files check (a half-built site must never reach Pages) →
the publish allowlist (only the page, its assets and `data/`, `smoke/`, `coverage/`, `stats/` go
out) → a `CNAME` file → deploy to GitHub Pages, and the same `site/dist` to the Cloudflare Worker
`marola` (static assets only, `wrangler.jsonc`), which serves marola.dev since 2026-10-07. GitHub
Pages keeps the same deploy as a fallback, and a Cloudflare failure does not fail the run
(MIP-0078). Its secrets are `CLOUDFLARE_API_TOKEN` (Edit Cloudflare Workers) and
`CLOUDFLARE_ACCOUNT_ID`.

### Beach lists and Overpass

The app keeps each area's beach list in `site/beaches/<lat>_<lon>_r<radius>_n<limit>.json` and asks
Overpass only for an area without one, writing the file when the query succeeds. `site.yml` keeps
that directory in the Actions cache (`beaches-<hash>`, restored newest first, saved after every
run, a failed one included), so once every area has a list the build no longer depends on the
public Overpass mirrors, whose timeouts used to fail whole builds (#63). Trails still come from
Overpass, but a failure there only leaves them off the board. A list refreshes when its area's
`lat`, `lon`, `radius_km` or `beach_limit` changes (that is the file name); to refetch otherwise,
delete the `beaches-` entries under Actions → Caches. OSM beaches change over years, not hours.

### The self-hosted runner in Brazil

INEA (Rio) and INEMA (Bahia) answer only Brazilian addresses, and GitHub's runners are not in
Brazil. So `site.yml`'s build job runs on a self-hosted runner labelled `marola-br`, on a machine in
Brazil, and reaches both directly: no proxy and no open port, since the runner only connects out to
GitHub. The deploy job stays on GitHub's runners.

`site.yml` runs only by hand for now, from the Actions tab or `gh workflow run site.yml` (pick an
area, or `all`, the default). With the runner off, a run waits in the queue and marola.dev keeps
the last deployed site. Only an owner (a repo admin) can run it: the `owner` job, on GitHub's
runner, fails the run before the build job reaches the self-hosted one. Registering the runner,
from the devkit:

```bash
MAROLA_RUNNER_REPO=marola-dev/marola-site MAROLA_RUNNER_PREFIX=marola-site \
  MAROLA_RUNNER_LABELS=marola-br just runners 1
```

A public repo's self-hosted runner runs whatever a workflow in a pull request asks it to, so keep
Settings → Actions → "Approval for running fork pull request workflows" on *all external
contributors*. `just site-build` works the same from any machine in Brazil.

### Crawl files and metadata

`site/static/robots.txt` (everyone allowed, names the sitemap) and `humans.txt` (written by
`scripts/members_build.py` from the same pinned `MEMBERS.md` as `members.html`) are committed.
`scripts/site_meta.py site/dist` writes the rest at build time: `llms.txt` (the site, every page,
one data link per area in `site/areas.json`, and the docs' own
[llms.txt](https://docs.marola.dev/llms.txt)), `sitemap.xml` (the five indexable pages with their
`hreflang` alternates; `contact.html` carries `noindex`), `.well-known/security.txt` (RFC 9116,
`Expires` 364 days after the build) and `board.schema.json`. A site not rebuilt for a year serves
an expired `security.txt`, and the health check says so. Pages' artifact drops dot-directories
unless `include-hidden-files` is set, which `site.yml` does for `.well-known/`.

### Crawlers, AI and visitor counts (Cloudflare)

Two things about crawlers are zone settings in Cloudflare's dashboard, not files here, and both
are a person's call:

- **The managed robots.txt.** Cloudflare prepends its content-signals block (`search`,
  `ai-input`, `ai-train`) to our `robots.txt`. On 2026-11-10 it carried no `Content-Signal` line,
  so it neither granted nor refused anything. Whatever it is set to has to agree with `llms.txt`,
  which invites a model to read the site: `search=yes, ai-input=yes` at least.
- **AI crawler blocking** ("Block AI bots", AI Crawl Control) answers some crawlers with 403
  before they reach `robots.txt` or `llms.txt`.

Visitor counts come from Cloudflare's zone analytics (#128): requests seen at the edge, no script
in the page, no cookie. The page adds no analytics of its own (#176 holds that decision).

## The `site-data` branch layout

An orphan branch, never deployed by the workflows that write it: `coverage/` and `smoke/` (the
app's CI and `docker-smoke.yml`), `stats/` (the umbrella). Each writer pushes with
`scripts/site-data-push.sh` (retries on a rejected push, replaying its one commit onto the new
tip) and then sends `repository_dispatch: site-data-updated`, which `site.yml` ignores while it runs
only by hand: the panels refresh on the next manual run. A directory missing from the branch just means no panel for it;
a missing branch means none of the three.

## Health checks

`site-health.yml` runs `python3 scripts/site_live_check.py` against the live site every six hours
(the boards, and the crawl files: `robots.txt` names a sitemap, every sitemap `<loc>` and `llms.txt`
link answers 200, `security.txt` has not expired),
separate from `site.yml` on purpose: a red run here means upstream data is missing (a bulletin
gone stale, a provider down), not that the build is broken, so it must never block a deploy.

## i18n bundling

`site/i18n/*.json` (`pt-BR` is the source locale, `en` is translated, `x-pseudo` is generated,
never translated) are checked and bundled into `site/static/i18n.js` by `scripts/i18n_bundle.py`
(MIP-0054 §5.8): every locale has exactly `pt-BR`'s keys with no empty value, every message parses
in the ICU subset `ui.js` implements and names the same arguments as `pt-BR`'s, and every key has a
note in `context.json`. Edit the catalogs, never `i18n.js`; `--check` fails a stale committed
bundle.

## The new site: Elm and Haskell

The map page is Elm in `front/`, bundled by Vite; the static pages and the server are Haskell in
`back/pages` and `back/server`, one cabal project at the root ([ADR 0005](adr/0005-elm-and-haskell.md)).

| Recipe | What it does |
|---|---|
| `just front-test` | elm-test over `front/tests` (`npm ci` first when `front/node_modules` is missing) |
| `just back-test` | `cabal test all`: the pages' and the server's hspec suites |
| `just front-fmt`, `just back-fmt` | elm-format 0.8.8 and ormolu 0.7.7.0 in check mode; `write` as the argument formats |
| `just golden` | Writes `front/tests/golden.json` |
| `just quality` | Runs all three, with the legacy checks |

The golden file is the parity contract with the old page. `scripts/golden.js` runs the pure functions of
`ui.js`, `app.js` and `flow.js` over a table of inputs and writes what they return. The Elm tests
(`GoldenTests.elm`) read the file and must give the same answers. Change the old code or the table,
run `just golden`, commit the new file; `just golden --check` fails a stale one.

Versions are pinned three ways: `front/package-lock.json` (npm: Vite, vite-plugin-elm, elm-test),
`front/elm.json` (the Elm packages) and `cabal.project.freeze` (every Haskell package, with
`index-state`). To change a Haskell bound, edit the `.cabal` file, run `cabal freeze` at the root and
commit the new freeze file. The first build downloads from npm, package.elm-lang.org and Hackage.

`flake.nix` gives the dev shell node, elm, GHC 9.6, cabal-install and SQLite from the flake's
own `nixpkgs`, pinned by the committed `flake.lock`. That elm is 0.19.2 and refuses `front/elm.json`
(0.19.1, the official release CI uses); `just front-test` needs the official 0.19.1 binary on `PATH`. The freeze file names GHC 9.6.6's `base`;
with another GHC 9.6 minor, run `cabal freeze` again.

## News posts

A post is `site/content/news/YYYY-MM-DD-<slug>.pt-BR.md` plus its `.en.md`, in the format
[`site/content/news/README.md`](../site/content/news/README.md) gives, listed in that file's index.
`python3 scripts/news_build.py` writes every post into the marked block of
`site/static/news.html`, newest first; `--check` fails a stale page, a post missing a language and
any Markdown outside the format. Edit the posts, never the block. Each post shows its reading time,
its words over 200 a minute, rounded up; the `news-post` skill has the rule.

## The `MIP:` trailer

A commit touching `site/static/**` carries `MIP: MIP-NNNN` or `MIP: none — <reason>`.
`scripts/mip-trailer-check.sh` enforces it; `just prepush` runs it over the commits about to be
pushed.

### Build and serve the client

```bash
just dist-build             # front_build.sh (Vite) and marola-pages into dist/, with the assets and csp.txt
just dist-build --fixtures  # also writes data/<area>/ boards from site/fixtures/board.json
just server-run             # http://127.0.0.1:8080, with the security headers (see below)
just front-check            # a Node smoke test of the built page in dist
just pages-parity <dir>     # the pages, byte for byte, against another build's dist
```

`scripts/site_build.sh` runs `scripts/front_build.sh` (`npm ci`, then `vite build` into `front/dist`:
the Elm bundle under `assets/` and `front/public/` copied as it is), copies it to `dist/`, runs
`marola-pages site dist`, and adds the catalogs of `site/i18n/`, the images and the board schema. It
writes `csp.txt` with `marola-server csp`. The pages are every static page (about, support, contact,
contact-sent, 404, news, members) and the metadata files (`robots.txt`, `sitemap.xml`, `llms.txt`,
`humans.txt`, `.well-known/security.txt`), in `dist/` and `dist/en/`. Edit the Markdown in
`site/content/pages/` and the posts in `site/content/news/`, and the chrome words in `site/i18n/`,
never the HTML. The members page reads `site/members/MEMBERS.md`, a copy of marola-dev/.github's file.
`site/members.version` has two lines: the commit the copy came from, and `blob <sha>`, the git blob id
of the copy. The build refuses a copy that does not hash to that id, so a build needs no network.
`just members-check` (in `just quality`) and a test in `back/pages` check the same. To move the
pin, copy MEMBERS.md at the new commit over the file and write both lines of `site/members.version`
(`git hash-object site/members/MEMBERS.md` prints the blob id). `MEMBERS_SOURCE=<file>` reads another
file instead. With no `site/members/MEMBERS.md`, the build fetches the commit. `--no-install` reuses
`front/node_modules`. `dist/`, `front/dist/` and `dist-newstyle/` are not in git.

`just front-check` runs the built page in Node with a small DOM and a MapLibre stub. It does not start
a browser, so it does not prove that the real MapLibre draws the map.

### Run and test the server

```bash
just server-run           # http://127.0.0.1:8080 over dist and data/, with every security header
just back-test            # the pages' and the server's tests (the server's pipeline in memory)
just back-build           # build both Haskell packages; `cabal list-bin marola-server` prints the binary
scripts/server_smoke.sh   # start the built server on a free port, check it, stop it
```

The server builds its CSP header from `Marola.Csp`, which also writes `dist/csp.txt`, so the page and
the server cannot drift. `just server-run` keeps the contact database in `.tmp/marola.db`, which git
ignores. The smoke script needs `just dist-build --fixtures` first. How it runs on a host, with the
variables and the nginx and systemd settings, is in [the hosting page](5-hosting.md).

To try the login by hand, start the fake GitHub and the server in dev mode. The fake GitHub signs in a made-up
user (`smoke-sci`); `MAROLA_DEV=1` lets the server take its URL from the environment and drop `Secure` and the
`__Host-` prefix, which plain HTTP cannot carry. Never set `MAROLA_DEV` on a host.

```bash
node scripts/fake_github.mjs fake-secret 9100 &       # prints the port
printf 'fake-secret\n' > .tmp/github-secret
MAROLA_DEV=1 MAROLA_GITHUB_CLIENT_ID=dev MAROLA_GITHUB_CLIENT_SECRET_FILE=.tmp/github-secret \
  MAROLA_GITHUB_BASE=http://127.0.0.1:9100 MAROLA_GITHUB_API_BASE=http://127.0.0.1:9100 just server-run
```

Then open `http://127.0.0.1:8080/submit` and press the login button. `scripts/server_smoke.sh` does the same
flow with `scripts/server_smoke_submit.mjs`: login through the redirects, a key, the form with its CSRF token,
the study page and its hash, a report, a withdrawal.

