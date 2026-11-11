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

## The F# app (`app/`)

The rewrite of the page is in F#, compiled to JavaScript by Fable ([ADR 0001](adr/0001-fsharp-fable-maplibre-dynamic-hosting.md)).
`app/Shared` holds the domain types, the board decoder and the pure functions. It uses no .NET-only
API, so .NET and Fable both compile it. `app/Client` is the map page (not written yet; its static
files and its two JavaScript files are there). `app/Server` (.NET) comes later.

`app/Tests` holds the tests with Expecto. `app/Tests.Fable` compiles the same test files with Fable and
runs them on Node, so a function has to give the same answer on both runtimes. A `#if FABLE_COMPILER`
in the test files picks Fable.Mocha in place of Expecto and the JSON reader of the runtime. `app/marola.sln` does not
exist: each recipe names its project.

| Recipe | What it does |
|---|---|
| `just app-test` | `dotnet test`, then `fable` on `Tests.Fable`, then `node Tests.Fable/run.mjs`. NuGet restores in locked mode |
| `just app-fmt` | Fantomas over `app/` (`--check` only reports, as CI does) |
| `just golden` | Writes `app/Tests/golden.json` |
| `just quality` | Runs all three |

The golden file is the parity contract with the old page. `scripts/golden.js` runs the pure functions of
`ui.js`, `app.js` and `flow.js` over a table of inputs and writes what they return. The F# tests
read the file and must give the same answers on .NET and on Node. Change the old code or the table,
run `just golden`, commit the new file; `just golden --check` fails a stale one.

NuGet packages are pinned by `packages.lock.json` in each project (`RestorePackagesWithLockFile`).
`just app-test` sets `RestoreLockedMode=true`, so a stale lock fails the run. To add or update a
package, edit the `fsproj`, run `dotnet restore` in that project folder (without the variable) and
commit the new lock. The restore downloads from nuget.org: it is the only download, and there is no
`npm`. The dev shell sets `DOTNET_CLI_TELEMETRY_OPTOUT`, `DOTNET_NOLOGO`, `DOTNET_CLI_HOME` and
`NUGET_PACKAGES`; the last two point into the shell's temporary folder, so each new shell downloads
the packages again.

`flake.nix` gives the dev shell `dotnet-sdk_10`, `fable` and `fantomas` from the flake's own `nixpkgs`.
The repo does not commit a `flake.lock`, so the versions are the ones that `nixos-unstable` has when
`nix develop` first writes one. On 2026-11-07 that was Fable 5.26.0, .NET SDK 10.0.403 and Fantomas
7.0.3. Never run `dotnet tool install`: the tools come from Nix.

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
just app-build            # Fable compiles app/Client/App, then app/dist/ is assembled
just app-build --fixtures # also writes data/<area>/ boards from site/fixtures/board.json
just server-run           # http://127.0.0.1:8080, with the security headers (see below)
just client-check         # a Node smoke test of the compiled client
just pages-test           # the static pages: renderer, Markdown subset, every page in both languages
just pages-build          # write the pages into app/dist alone (app-build does it too)
```

`scripts/app_build.sh` runs `fable app/Client/App --outDir app/Client/out` with a locked NuGet
restore, then builds `app/dist/`: `index.html`, `style.css`, `vendor/` and `data/trails/` from
`app/Client/public/`, Fable's output in `app/dist/app/` (with its `fable_modules/`), the two files of
`app/Client/ffi/` in `app/dist/ffi/`, and the catalogs of `site/i18n/`. It writes `csp.txt` from
`Csp.fs`. There is no `boot.mjs`: `index.html` loads `app/Program.js`, whose last line calls `main`.
The build also renders every static page (about, support, contact, contact-sent, 404, news, members) and the
metadata files (`robots.txt`, `sitemap.xml`, `llms.txt`, `humans.txt`, `.well-known/security.txt`) into
`app/dist/` and `app/dist/en/` ([ADR 0003](adr/0003-pages-in-fsharp.md)). Edit the Markdown in
`site/content/pages/` and the posts in `site/content/news/`, and the chrome words in `site/i18n/`,
never the HTML. The members page reads MEMBERS.md of marola-dev/.github at the commit of
`site/members.version`, so `just app-build` needs the network; set `MEMBERS_SOURCE=<file>` to build
without it. `--no-fable` reuses `app/Client/out`.
`app/dist/` and `app/Client/out/` are not in git.

Fable writes each FFI import as the path from its output file to the `.mjs` in the source tree. That
is why the build compiles into `app/Client/out`, next to `app/Client/ffi`, and `app/dist/app` and
`app/dist/ffi` keep the same relation. `app/dist/app/package.json` says `"type": "module"` because Node
(the check) needs it for Fable's `.js` files; a browser does not read it.

`just client-check` runs the compiled client in Node with a small DOM and a MapLibre stub. It
does not start a browser, so it does not prove that the real MapLibre draws the map.

### Run and test the server

```bash
just server-run           # http://127.0.0.1:8080 over app/dist and data/, with every security header
just server-test          # the server's tests: the real pipeline in memory (Expecto and TestHost)
just server-build         # publish the server into app/Server/out
scripts/server_smoke.sh   # start the built server on a free port, check it, stop it
```

`app/Server` replaces `scripts/serve.mjs`. It builds the CSP header from `Csp.fs`, so the page and the
server cannot drift. `just server-run` keeps the contact database in `.tmp/marola.db`, which git
ignores. The smoke script needs `just app-build --fixtures` first. How it runs on a host, with the
variables and the nginx and systemd settings, is in [the hosting page](5-hosting.md).

