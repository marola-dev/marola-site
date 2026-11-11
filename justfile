set shell := ["bash", "-euo", "pipefail", "-c"]
set allow-duplicate-recipes

# The devkit's shared recipes (uprd, pr, stack, issue-*, ...), from the tree `nix develop` links.
import? '.devkit/devkit.just'

default:
    @just --list

# Build the boards with the pinned app image into site/dist, plus the page (needs docker, network).
# INEA and INEMA answer only Brazilian addresses: run it from a machine in Brazil, as site.yml does.
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

# Deploy the map (site.yml: the Cloudflare Worker behind marola.dev, GitHub Pages as fallback).
site-deploy:
    gh workflow run site.yml && echo "queued site.yml — watch it: gh run list --workflow site.yml"

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

# Format the F# code in app/ with Fantomas (--check only reports, as CI does).
app-fmt *args:
    cd app && fantomas {{ args }} .

# The F# tests of app/ on .NET (Expecto) and on Node (the same tests compiled by Fable). NuGet restores
# in locked mode: it fails when a packages.lock.json is stale, and downloads the packages it pins.
app-test:
    #!/usr/bin/env bash
    set -euo pipefail
    export RestoreLockedMode=true
    cd app
    dotnet test Tests
    rm -rf Tests.Fable/out
    (cd Tests.Fable && fable --outDir out)
    node Tests.Fable/run.mjs Tests.Fable/out/Main.js

# The old page's pure functions run into app/Tests/golden.json, which the F# tests compare against: --check fails on a stale file.
golden *args:
    node scripts/golden.js {{ args }}

# Every gate CI runs that needs no docker (app-test and server-test download their NuGet packages).
quality:
    #!/usr/bin/env bash
    set -euo pipefail
    for tool in node python3 ruff shellcheck actionlint agents-check docs-lint dotnet fable fantomas; do command -v "$tool" >/dev/null || { echo "quality: $tool not installed — run inside 'nix develop'" >&2; exit 1; }; done
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
    just app-fmt --check
    just app-test
    just server-test
    just pages-test
    python3 scripts/site_live_check.py --self-test
    python3 scripts/i18n_bundle.py --self-test
    python3 scripts/news_build.py --self-test
    python3 scripts/members_build.py --self-test
    scripts/members_vendor_check.sh
    python3 scripts/site_meta.py --self-test
    scripts/site-data-push.sh --self-test
    scripts/board-schema.sh --self-test
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

# Build the client with Fable into app/dist (--fixtures adds a board per area for an offline preview).
app-build *args:
    scripts/app_build.sh {{ args }}

# Run the .NET server at http://127.0.0.1:8080 over app/dist and data/ (run app-build first). MAROLA_PORT, MAROLA_STATIC, MAROLA_DATA and MAROLA_DB change the defaults.
server-run:
    MAROLA_DB="${MAROLA_DB:-.tmp/marola.db}" RestoreLockedMode=true dotnet run --project app/Server

# The server's tests (Expecto on the ASP.NET test host). NuGet restores in locked mode.
server-test:
    RestoreLockedMode=true dotnet test app/Server.Tests

# Publish the server (framework-dependent, Release) into app/Server/out, the folder a host runs.
server-build:
    RestoreLockedMode=true dotnet publish app/Server -c Release -o app/Server/out

# The static pages' tests (Expecto): the renderer, the Markdown subset and every page in both languages. NuGet restores in locked mode.
pages-test:
    RestoreLockedMode=true dotnet test app/Pages.Tests

# Render the static pages (site/content/pages) into a folder: pt-BR at its root, English under en/. app-build does this into app/dist.
pages-build out="app/dist":
    RestoreLockedMode=true dotnet run --project app/Pages.Build -c Release -- site {{ out }}

# Start the built server on a free port against app/dist and check its headers, hostile paths and contact form (run app-build --fixtures first).
server-smoke:
    scripts/server_smoke.sh

# Node smoke test of the compiled client in app/dist: DOM and MapLibre stubs, no browser (run app-build --fixtures first).
client-check:
    node scripts/client_check.js

# Build the whole site (server, static pages, Fable client) as one Nix package with no network in the build. Output: result/ (bin/marola-server, share/marola/dist).
nix-build:
    nix build .#default

# Rewrite nix/deps.json (the NuGet packages the offline build uses) after a change to any fsproj or packages.lock.json. Needs the network.
nix-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    script="$(nix build .#default.passthru.fetch-deps --no-link --print-out-paths)"
    "$script" "$PWD/nix/deps.json"

# Start the Nix package's server on a free port with its state in a temp dir and check four URLs for 200 and the CSP header.
package-smoke *args:
    scripts/package_smoke.sh {{ args }}
