#!/usr/bin/env bash
# Builds the Elm map page with Vite and assembles front/dist/, a folder any static server can serve.
# Vite bundles only front/ports.js, the Elm page and the two FFI files; the stylesheet, the vendored
# MapLibre, fonts, sound and trail files are copied as they are, because the page loads MapLibre by
# URL at run time and style.css is shared with the static pages.
set -euo pipefail

usage() {
  echo "usage: scripts/front_build.sh [--fixtures] [--no-install]" >&2
  echo "  --fixtures    add data/<area>/latest.json and a fixture board per area (offline preview)" >&2
  echo "  --no-install  skip 'npm ci'; reuse front/node_modules" >&2
}

fixtures=0
install=1
for arg in "$@"; do
  case "$arg" in
    --fixtures) fixtures=1 ;;
    --no-install) install=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "front_build: unknown flag: $arg" >&2; usage; exit 2 ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

command -v node >/dev/null || { echo "front_build: node is not installed" >&2; exit 1; }
command -v npm >/dev/null || { echo "front_build: npm is not installed" >&2; exit 1; }
# vite-plugin-elm calls the elm on PATH; the npm 'elm' package is not used because it downloads a binary.
command -v elm >/dev/null || { echo "front_build: elm 0.19.1 is not on PATH" >&2; exit 1; }

if [ "$install" -eq 1 ]; then
  (cd front && npm ci --no-audit --no-fund)
fi
[ -x front/node_modules/.bin/vite ] || { echo "front_build: front/node_modules is missing; run without --no-install" >&2; exit 1; }
(cd front && ./node_modules/.bin/vite build)

dist="front/dist"
[ -f "$dist/index.html" ] || { echo "front_build: vite wrote no $dist/index.html" >&2; exit 1; }

# Everything public except the F# page's own index.html, which Vite's output replaces.
for entry in app/Client/public/*; do
  name="$(basename "$entry")"
  [ "$name" = "index.html" ] && continue
  cp -r "$entry" "$dist/"
done
mkdir -p "$dist/i18n"
cp site/i18n/en.json site/i18n/pt-BR.json "$dist/i18n/"
cp site/board.schema.json "$dist/"

node scripts/app_fixtures.mjs areas "$dist"
if [ "$fixtures" -eq 1 ]; then
  node scripts/app_fixtures.mjs boards "$dist"
fi

echo "front_build: $dist ready (serve it with: python3 -m http.server -d $dist)"
