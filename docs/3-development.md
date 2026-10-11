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

Runs on a schedule (every three hours), on a push to `main` touching `site/**`, `marola-image` or
the workflow itself, on `repository_dispatch: site-data-updated` (sent by every `site-data`
writer), and on `workflow_dispatch` (optionally one area). `concurrency: site` queues a run rather
than cancelling one that is already building.

The job: pull the pinned image (two tries) → check the harness and the page against the image's
own board schema → restore the beach lists → build every area's boards (or one, with an area input) → copy the static page
into `site/dist` → write the Mapbox token and style into `mapbox-config.js` → cache-bust
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

### The Brazilian proxy and the flight check

INEA (Rio) and INEMA (Bahia) answer only Brazilian addresses, and the runners are not in Brazil.
Before the image is pulled, `site.yml` joins the org's tailnet (`TAILSCALE_OAUTH_CLIENT_ID` and
`TAILSCALE_OAUTH_SECRET`), runs the flight check (`scripts/br-proxy-preflight.sh`: the first online
`tag:br-proxy` node through which INEA really answers) and routes those two hosts, and only those,
through it (`scripts/br-proxy.sh`, with the app's JVM pointed at it). The `MAROLA_BR_PROXY` secret
overrides the pool with any HTTP proxy in Brazil.

The flight check **fails closed**, on every trigger: no tailnet or no healthy node stops the job with an `::error::` naming the cause, before any board is
built. Nothing deploys, and marola.dev keeps serving the last deployed site, for every area. The
repo variable `BR_PROXY_REQUIRED=false` is the break glass: the build then goes on without the
proxy and those two agencies read "no data". Unset means required; set it only while the pool is
down. `just site-build` routes the same way when `MAROLA_BR_PROXY` is set in your shell, and
without it builds as before. The pool, its nodes and the whole Tailscale setup:
[`ops/br-proxy/README.md`](../ops/br-proxy/README.md) and
[`ops/br-proxy/JOIN.md`](../ops/br-proxy/JOIN.md).

## Secrets and 1Password

The values of `site.yml`'s secrets live in 1Password, vault `marola-ci`, one *API Credential* item
per secret, titled with the secret's name and holding the value in its `credential` field.
`just secrets-sync` ([`scripts/secrets-sync.sh`](../scripts/secrets-sync.sh)) reads each one with
`op read` and writes it with `gh secret set`, through a pipe. GitHub never shows a secret again, so
1Password is the only copy anyone can read, and every run overwrites GitHub's: change a value in
1Password, never on GitHub. A new secret is an item in `marola-ci` plus a name in the script's list;
removing one is `gh secret delete <NAME> --repo marola-dev/marola-site` and the name out of the
list. The 1Password account, its vaults and the values are a human's.

On Ubuntu the setup is one command, below. Then, from this checkout:

```bash
nix develop
gh auth login                 # once, with admin on marola-dev/marola-site
just secrets-sync --dry-run   # reads every item, writes nothing
just secrets-sync
```

## For Ubuntu users

```bash
just setup-ubuntu              # or scripts/setup-ubuntu.sh before just is installed
just setup-ubuntu --dry-run    # print what it would run
```

[`scripts/setup-ubuntu.sh`](../scripts/setup-ubuntu.sh) installs
[Determinate Nix](https://determinate.systems/nix/) (flakes on by default), the Nix the
maintainer's own Ubuntu runs ([h0ffmann/nix-config](https://github.com/h0ffmann/nix-config)), then
the 1Password app and CLI from 1Password's apt repository, with the commands from its
[get-started page](https://www.1password.dev/cli/get-started). Last it checks out the `nix-config`
submodule. It asks for `sudo` and skips what is already installed, so running it again is
harmless. Nix then gives `just`, `gh`, node and the lint
tools through `nix develop`; only 1Password stays outside Nix, because the desktop app hands the CLI
a session only when `op` belongs to the `onepassword-cli` group with setgid, which a binary in the
Nix store cannot be.

What no script can do is in the 1Password app, once: sign in, turn on Settings → Security →
"Unlock using system authentication" and Settings → Developer → "Integrate with 1Password CLI"
(it needs PolKit and a running agent, which Ubuntu's desktop has), then check `op vault list` from
a new terminal. `op` talks to the app over a desktop socket, so it does not work inside an agent
sandbox such as ai-jail: run `just secrets-sync` from a plain terminal.

`nix-config/` is [h0ffmann/nix-config](https://github.com/h0ffmann/nix-config) as a shallow
submodule, at the commit this repo pins: the maintainer's Nix labs, read here and changed there. No
workflow checks it out and nothing in the build reads it. Its `labs/agentic` runs Claude Code inside
[ai-jail](https://github.com/akitaonrails/ai-jail) on this checkout:

```bash
just -f nix-config/labs/agentic/justfile jco
```

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
never translated) are checked and bundled into `site/static/i18n.js` by `scripts/i18n_bundle.py`
(MIP-0054 §5.8): every locale has exactly `pt-BR`'s keys with no empty value, every message parses
in the ICU subset `ui.js` implements and names the same arguments as `pt-BR`'s, and every key has a
note in `context.json`. Edit the catalogs, never `i18n.js`; `--check` fails a stale committed
bundle.

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
