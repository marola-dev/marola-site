#!/usr/bin/env bash
# Assembles dist/, the folder the server (back/server) serves: the Elm map page (front_build.sh), the
# static pages and metadata files (marola-pages site dist), the catalogs, images and board schema
# the pages and the page read, data/areas.json, and csp.txt, the server's own policy, which
# front_check.js and the smoke tests compare with the page's <meta> and the header.
# MAROLA_PAGES_BIN and MAROLA_SERVER_BIN name built binaries (the Nix build); without them, cabal
# builds both from the root cabal.project.
set -euo pipefail

usage() {
  echo "usage: scripts/site_build.sh [--fixtures] [--no-install]" >&2
  echo "  --fixtures    add data/<area>/latest.json, a fixture board per area and the fixture base map (offline preview)" >&2
  echo "  --no-install  skip 'npm ci'; reuse front/node_modules" >&2
}

fixtures=0
front_args=()
for arg in "$@"; do
  case "$arg" in
    --fixtures) fixtures=1 ;;
    --no-install) front_args+=(--no-install) ;;
    -h|--help) usage; exit 0 ;;
    *) echo "site_build: unknown flag: $arg" >&2; usage; exit 2 ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

pages="${MAROLA_PAGES_BIN:-}"
server="${MAROLA_SERVER_BIN:-}"
if [ -z "$pages" ] || [ -z "$server" ]; then
  command -v cabal >/dev/null || { echo "site_build: cabal is not installed; run inside 'nix develop'" >&2; exit 1; }
  cabal build -v0 exe:marola-pages exe:marola-server >&2
  [ -n "$pages" ] || pages="$(cabal list-bin marola-pages)"
  [ -n "$server" ] || server="$(cabal list-bin marola-server)"
fi

scripts/front_build.sh "${front_args[@]}"

dist="dist"
rm -rf "$dist"
cp -r front/dist "$dist"
"$pages" site "$dist" >&2
mkdir -p "$dist/i18n" "$dist/img"
cp site/i18n/en.json site/i18n/pt-BR.json "$dist/i18n/"
cp site/static/img/umbrella.svg site/static/img/umbrella.pt-BR.svg "$dist/img/"
cp -r site/static/img/members "$dist/img/members"
cp site/board.schema.json "$dist/"
"$server" csp > "$dist/csp.txt"

node scripts/site_fixtures.mjs areas "$dist"
if [ "$fixtures" -eq 1 ]; then
  node scripts/site_fixtures.mjs boards "$dist"
  # The base map is host data (MAROLA_TILES, docs/5-hosting.md); the server falls back to this copy.
  mkdir -p "$dist/tiles"
  cp site/fixtures/basemap.pmtiles "$dist/tiles/marola.pmtiles"
fi

echo "site_build: $dist ready (run it with: just server-run)" >&2
