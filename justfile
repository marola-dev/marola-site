set shell := ["bash", "-euo", "pipefail", "-c"]
set allow-duplicate-recipes

# The devkit's shared recipes (uprd, pr, stack, issue-*, ...), from the tree `nix develop` links.
import? '.devkit/devkit.just'

default:
    @just --list

# Build the boards with the pinned app image into site/dist, plus the page (needs docker, network).
# With MAROLA_BR_PROXY set (and tinyproxy installed), INEA and INEMA go through it, as in site.yml.
site-build area="":
    #!/usr/bin/env bash
    set -euo pipefail
    image="$(scripts/board-schema.sh --image)"
    args=(--site); [ -z "{{ area }}" ] || args+=("{{ area }}")
    br=()
    opts="$(scripts/br-proxy.sh start)"
    [ -z "$opts" ] || { br=(--network host -e "JDK_JAVA_OPTIONS=$opts"); trap 'scripts/br-proxy.sh stop' EXIT; }
    mkdir -p site/dist
    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp "${br[@]}" -v "$PWD/site:/work/site" -w /work "$image" \
      "${args[@]}" --areas site/areas.json --site-out site/dist
    cp -r site/static/. site/dist/
    scripts/mapbox_config.sh site/dist  # MAPBOX_PUBLIC_TOKEN=pk.… from your shell, or no base map
    scripts/stamp_site_version.sh site/dist

# Serve site/dist at http://localhost:8000.
site-serve port="8000":
    python3 -m http.server -d site/dist {{ port }}

# Deploy the map (site.yml on GitHub Pages).
site-deploy:
    gh workflow run site.yml && echo "queued site.yml — watch it: gh run list --workflow site.yml"

# Check what marola.dev actually serves (or --base http://localhost:8000).
site-live-check *args:
    python3 scripts/site_live_check.py {{ args }}

# The pinned image's board schema: --check, --update after bumping marola-image, --image.
board-schema *args:
    scripts/board-schema.sh {{ args }}

# Every gate CI runs that needs no docker or network.
quality:
    #!/usr/bin/env bash
    set -euo pipefail
    for tool in node python3 ruff shellcheck actionlint agents-check docs-lint; do command -v "$tool" >/dev/null || { echo "quality: $tool not installed — run inside 'nix develop'" >&2; exit 1; }; done
    ruff check .
    ruff format --check .
    shellcheck --severity=error scripts/*.sh
    actionlint
    node --check site/static/app.js
    node --check site/static/flow.js
    node --check site/static/ui.js
    node --check site/static/i18n.js
    python3 scripts/i18n_bundle.py --check
    node scripts/site_check.js
    node scripts/redirect_check.js
    python3 scripts/site_live_check.py --self-test
    python3 scripts/i18n_bundle.py --self-test
    scripts/site-data-push.sh --self-test
    scripts/board-schema.sh --self-test
    scripts/mapbox_config.sh --self-test
    scripts/mip-trailer-check.sh --self-test
    scripts/br-proxy.sh --self-test
    scripts/br-proxy-preflight.sh --self-test
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
