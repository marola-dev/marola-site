#!/usr/bin/env bash
# Builds the F# client with Fable and assembles app/dist/, the folder app/Server serves.
# Why a script: Fable emits ES modules with relative imports and calls main from the last module,
# so the tree is copied whole and index.html loads that one module; there is no bundler.
# Fable writes each FFI import as the path from the output file to the .mjs in the source tree, so
# the build compiles into app/Client/out, beside app/Client/ffi, and dist/app and dist/ffi keep
# that relation.
set -euo pipefail

usage() {
  echo "usage: scripts/app_build.sh [--fixtures] [--no-fable]" >&2
  echo "  --fixtures  add data/<area>/latest.json and a fixture board per area (offline preview)" >&2
  echo "  --no-fable  skip 'fable'; reuse app/Client/out" >&2
}

fixtures=0
build=1
for arg in "$@"; do
  case "$arg" in
    --fixtures) fixtures=1 ;;
    --no-fable) build=0 ;;
    *) echo "app_build: unknown flag: $arg" >&2; usage; exit 2 ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

command -v node >/dev/null || { echo "app_build: node is not installed; run inside 'nix develop'" >&2; exit 1; }

out="app/Client/out"
if [ "$build" -eq 1 ]; then
  command -v fable >/dev/null || { echo "app_build: fable is not installed; run inside 'nix develop'" >&2; exit 1; }
  rm -rf "$out"
  # Locked restore, as `just app-test`: a stale packages.lock.json fails here too.
  RestoreLockedMode=true fable app/Client/App --outDir "$out"
fi
[ -f "$out/Program.js" ] || { echo "app_build: $out/Program.js missing; build without --no-fable" >&2; exit 1; }

dist="app/dist"
rm -rf "$dist"
mkdir -p "$dist/app" "$dist/ffi" "$dist/i18n"
cp -r app/Client/public/. "$dist/"
cp -r "$out/." "$dist/app/"
cp app/Client/ffi/*.mjs "$dist/ffi/"
cp site/i18n/en.json site/i18n/pt-BR.json "$dist/i18n/"
# Fable's own .js files import each other as ES modules; Node needs to be told (a browser does not).
printf '{ "type": "module" }\n' > "$dist/app/package.json"

node scripts/app_fixtures.mjs areas "$dist"
if [ "$fixtures" -eq 1 ]; then
  node scripts/app_fixtures.mjs boards "$dist"
fi

# The server builds its header from Csp.fs; this copy lets client_check.js compare it with the page's <meta>.
node --input-type=module -e '
import { policy } from "./app/dist/app/Shared/Csp.js";
process.stdout.write(policy());
' > "$dist/csp.txt"

echo "app_build: $dist ready (run with: just server-run)"
