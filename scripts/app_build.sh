#!/usr/bin/env bash
# Builds the Gleam client and assembles app/dist/, the folder scripts/serve.mjs serves.
# Why a script: Gleam emits ES modules with relative imports and never calls main, so the
# tree is copied whole and a generated boot.mjs starts it; there is no bundler.
set -euo pipefail

usage() {
  echo "usage: scripts/app_build.sh [--fixtures] [--no-gleam]" >&2
  echo "  --fixtures  add data/<area>/latest.json and a fixture board per area (offline preview)" >&2
  echo "  --no-gleam  skip 'gleam build'; reuse app/client/build" >&2
}

fixtures=0
build=1
for arg in "$@"; do
  case "$arg" in
    --fixtures) fixtures=1 ;;
    --no-gleam) build=0 ;;
    *) echo "app_build: unknown flag: $arg" >&2; usage; exit 2 ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [ "$build" -eq 1 ]; then
  command -v gleam >/dev/null || { echo "app_build: gleam is not installed; run inside 'nix develop'" >&2; exit 1; }
  (cd app/client && gleam build --target javascript)
fi

js="app/client/build/dev/javascript"
[ -f "$js/marola_client/marola_client.mjs" ] || { echo "app_build: $js/marola_client/marola_client.mjs missing; build without --no-gleam" >&2; exit 1; }
command -v node >/dev/null || { echo "app_build: node is not installed; run inside 'nix develop'" >&2; exit 1; }

dist="app/dist"
rm -rf "$dist"
mkdir -p "$dist/app" "$dist/i18n"
cp -r app/client/static/. "$dist/"
cp -r "$js/." "$dist/app/"
cp site/i18n/en.json site/i18n/pt-BR.json "$dist/i18n/"
printf 'import { main } from "./app/marola_client/marola_client.mjs";\nmain();\n' > "$dist/boot.mjs"

node scripts/app_fixtures.mjs areas "$dist"
if [ "$fixtures" -eq 1 ]; then
  node scripts/app_fixtures.mjs boards "$dist"
fi

# serve.mjs sends this header; the policy lives in Gleam so the page and the server cannot drift.
node --input-type=module -e '
import { policy } from "./app/dist/app/marola_shared/marola/csp.mjs";
process.stdout.write(policy());
' > "$dist/csp.txt"

echo "app_build: $dist ready (serve with: just app-serve)"
