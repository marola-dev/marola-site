set shell := ["bash", "-euo", "pipefail", "-c"]
set allow-duplicate-recipes

# The devkit's shared recipes (uprd, pr, stack, issue-*, ...), from the tree `nix develop` links.
import? '.devkit/devkit.just'

default:
    @just --list

# Build the boards with the pinned app image into site/dist, plus the page (needs docker, network).
# INEA and INEMA answer only Brazilian addresses: run it from a machine in Brazil, as piabrota2 does.
site-build area="":
    #!/usr/bin/env bash
    set -euo pipefail
    image="$(scripts/board-schema.sh --image)"
    args=(--site); [ -z "{{ area }}" ] || args+=("{{ area }}")
    mkdir -p site/dist
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD/site:/work/site" -w /work "$image" \
      "${args[@]}" --areas site/areas.json --site-out site/dist
    cp -r site/static/. site/dist/
    scripts/mapbox_config.sh site/dist  # MAPBOX_PUBLIC_TOKEN=pk.… from your shell, or no base map
    scripts/stamp_site_version.sh site/dist

# Serve site/dist at http://localhost:8000.
site-serve port="8000":
    python3 -m http.server -d site/dist {{ port }}

# Check what marola.dev actually serves (or --base http://localhost:8000).
site-live-check *args:
    python3 scripts/site_live_check.py {{ args }}

# The members page from marola-dev/.github's MEMBERS.md at site/members.version: --check, --source FILE (network without --source).
members *args:
    python3 scripts/members_build.py {{ args }}

# The vendored site/members/MEMBERS.md against the blob id on the second line of site/members.version.
members-check:
    scripts/members_vendor_check.sh

# The pinned image's board schema: --check, --update after bumping marola-image, --image.
board-schema *args:
    scripts/board-schema.sh {{ args }}

# The old page's pure functions run into front/tests/golden.json, which the Elm tests compare against: --check fails on a stale file.
golden *args:
    node scripts/golden.js {{ args }}

# DESIGN.md against front/public/style.css: every :root token is documented with its value, and no hex colour sits outside :root. Runs its self-test first.
design-check:
    cabal run -v0 exe:marola-tools -- design-check --self-test
    cabal run -v0 exe:marola-tools -- design-check

# ADR 0007: every JavaScript file git tracks is on scripts/js-allowlist.tsv with the reason it cannot be Elm or Haskell.
js-check:
    cabal run -v0 exe:marola-tools -- js-check

# npm packages of front/ with a known vulnerability. By hand, needs network (it asks the npm registry); not in `quality`.
audit:
    cd front && npm audit

# Every gate CI runs that needs no docker (front-test and back-test download their npm, Elm and Hackage packages once).
quality:
    #!/usr/bin/env bash
    set -euo pipefail
    for tool in node npm elm ghc cabal ormolu python3 ruff shellcheck actionlint agents-check docs-lint; do command -v "$tool" >/dev/null || { echo "quality: $tool not installed — run inside 'nix develop'" >&2; exit 1; }; done
    ruff check .
    ruff format --check .
    shellcheck --severity=error scripts/*.sh
    actionlint
    node --check site/static/app.js
    node --check site/static/flow.js
    node --check site/static/ui.js
    node --check site/static/i18n.js
    python3 scripts/i18n_bundle.py --check
    python3 scripts/news_build.py --check
    node scripts/site_check.js
    node scripts/redirect_check.js
    node scripts/golden.js --check
    just design-check
    just js-check
    just front-fmt
    just back-fmt
    just front-test
    just back-test
    python3 scripts/site_live_check.py --self-test
    python3 scripts/i18n_bundle.py --self-test
    python3 scripts/news_build.py --self-test
    python3 scripts/members_build.py --self-test
    scripts/members_vendor_check.sh
    python3 scripts/site_meta.py --self-test
    scripts/site-data-push.sh --self-test
    scripts/board-schema.sh --self-test
    scripts/basemap_extract.sh --self-test
    scripts/mapbox_config.sh --self-test
    scripts/mip-trailer-check.sh --self-test
    agents-check
    docs-lint

# The devkit hooks' contract: fast checks at commit, the full gate (and the MIP: rule) at push.
precommit:
    node --check site/static/app.js
    node scripts/site_check.js
    ruff check .
    agents-check

prepush:
    scripts/mip-trailer-check.sh
    just quality

# Cut the base map's PMTiles file from the Protomaps build pinned in site/basemap.version (pmtiles, tile-join, network): `just basemap-extract <out.pmtiles>`, `--fixture`, `--dry-run`.
basemap-extract *args:
    scripts/basemap_extract.sh {{ args }}

# Write front/public/map/ (the base map's style and glyphs) from @protomaps/basemaps; `--check` compares. Fetches its tools into .tmp/ once.
basemap-style *args:
    node scripts/basemap_style.mjs {{ args }}

# Build the Elm map page with Vite into front/dist (the bundle and front/public). dist-build puts it into dist.
front-build *args:
    scripts/front_build.sh {{ args }}

# The Elm tests (elm-test): the decoders, the URL parameters, update and the golden cases of the old page.
front-test:
    #!/usr/bin/env bash
    set -euo pipefail
    cd front
    [ -x node_modules/.bin/elm-test ] || npm ci --no-audit --no-fund
    npm test

# elm-format 0.8.8 (npm devDependency of front/) over the Elm sources: check (default) fails on an unformatted file, write rewrites them.
front-fmt mode="check":
    #!/usr/bin/env bash
    set -euo pipefail
    cd front
    [ -x node_modules/.bin/elm-format ] || npm ci --no-audit --no-fund
    # tracked files only: tests/Fixtures.elm is generated by `npm test` and git-ignored
    mapfile -d '' files < <(git ls-files -z '*.elm')
    case "{{ mode }}" in
      check) ./node_modules/.bin/elm-format --validate --elm-version=0.19 "${files[@]}" ;;
      write) ./node_modules/.bin/elm-format --yes --elm-version=0.19 "${files[@]}" ;;
      *) echo "front-fmt: mode is check or write" >&2; exit 2 ;;
    esac

# Node smoke test of the built page in dist: DOM and MapLibre stubs, no browser (run dist-build --fixtures first).
front-check:
    node scripts/front_check.js

# Build the Haskell packages (back/pages, back/server, back/tools) from the root cabal.project.
back-build:
    cabal build all

# ormolu 0.7.7.0 (release binary, or `cabal install ormolu-0.7.7.0`) over back/: check (default) fails on an unformatted file, write rewrites them.
back-fmt mode="check":
    #!/usr/bin/env bash
    set -euo pipefail
    command -v ormolu >/dev/null || { echo "back-fmt: ormolu is not installed (0.7.7.0)" >&2; exit 1; }
    case "{{ mode }}" in
      check|write) ;;
      *) echo "back-fmt: mode is check or write" >&2; exit 2 ;;
    esac
    [ "{{ mode }}" = write ] && ormolu_mode=inplace || ormolu_mode=check
    git ls-files -z 'back/*.hs' | xargs -0 ormolu --mode "$ormolu_mode"

# The Haskell tests (hspec): the page renderer and every page in both languages, the server on its WAI pipeline, and marola-tools' checks.
back-test:
    cabal test all

# Assemble dist/, the folder the server serves: the Elm page, the static pages, the assets and csp.txt (--fixtures: a fixture board per area; --no-install: reuse front/node_modules). Not the legacy site-build.
dist-build *args:
    scripts/site_build.sh {{ args }}

# Render the static pages and compare them byte for byte with the same files in a reference folder (a dist of another commit).
pages-parity ref:
    scripts/pages_parity.sh {{ ref }}

# Run the Haskell server at http://127.0.0.1:8080 over dist and data/ (run dist-build first). MAROLA_PORT, MAROLA_STATIC, MAROLA_DATA, MAROLA_TILES and MAROLA_DB change the defaults.
server-run:
    cabal build -v0 exe:marola-server
    MAROLA_DB="${MAROLA_DB:-.tmp/marola.db}" "$(cabal list-bin marola-server)"

# Start the built server on a free port against dist and check its headers, hostile paths, contact form and study API (run dist-build --fixtures first).
server-smoke:
    scripts/server_smoke.sh

# Build the whole site (Haskell server, static pages, Elm page) as one Nix package with no network in the build. Output: result/ (bin/marola-server, share/marola/dist).
nix-build:
    nix build .#default

# Start the Nix package's server on a free port with its state in a temp dir and check four URLs for 200 and the CSP header.
package-smoke *args:
    scripts/package_smoke.sh {{ args }}
