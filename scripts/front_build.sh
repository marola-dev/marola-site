#!/usr/bin/env bash
# Builds the Elm map page with Vite into front/dist/: the bundle (ports.js, the Elm page, the two FFI
# files) and front/public/ copied as it is. scripts/site_build.sh puts it into dist/ with the pages.
set -euo pipefail

usage() {
  echo "usage: scripts/front_build.sh [--no-install]" >&2
  echo "  --no-install  skip 'npm ci'; reuse front/node_modules" >&2
}

install=1
for arg in "$@"; do
  case "$arg" in
    --no-install) install=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "front_build: unknown flag: $arg" >&2; usage; exit 2 ;;
  esac
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/front"

for tool in node npm elm; do
  command -v "$tool" >/dev/null || { echo "front_build: $tool is not installed; run inside 'nix develop'" >&2; exit 1; }
done
# vite-plugin-elm calls the elm on PATH; the npm 'elm' package is not used because it downloads a binary.

if [ "$install" -eq 1 ]; then
  npm ci --no-audit --no-fund
fi
[ -x node_modules/.bin/vite ] || { echo "front_build: front/node_modules is missing; run without --no-install" >&2; exit 1; }
./node_modules/.bin/vite build
[ -f dist/index.html ] || { echo "front_build: vite wrote no front/dist/index.html" >&2; exit 1; }
echo "front_build: front/dist ready" >&2
