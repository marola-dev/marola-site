#!/usr/bin/env bash
# Starts the server of the Nix package (bin/marola-server over share/marola/dist) on a free port with
# its state in a temp dir, and checks that the pages and the study API answer 200 with the CSP header.
# Usage: scripts/package_smoke.sh [<package path>]   (default: `nix build .#default`, as `just package-smoke`)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [ -n "${MAROLA_TOOLS_BIN:-}" ]; then
  tools="$MAROLA_TOOLS_BIN"
else
  command -v cabal >/dev/null || { echo "package_smoke: cabal is not installed; run inside 'nix develop'" >&2; exit 1; }
  cabal build -v0 exe:marola-tools >&2
  tools="$(cabal list-bin marola-tools)"
fi

out="${1:-}"
if [ -z "$out" ]; then
  out="$(nix build .#default --no-link --print-out-paths)"
fi
bin="$out/bin/marola-server"
dist="$out/share/marola/dist"
[ -x "$bin" ] || { echo "package_smoke: $bin is not an executable" >&2; exit 1; }
[ -f "$dist/index.html" ] || { echo "package_smoke: $dist/index.html is missing" >&2; exit 1; }

tmp="$(mktemp -d)"
pid=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

port="$("$tools" free-port)"

# Only the variables a host sets: an empty PATH, no secret.
env -i PATH=/nonexistent HOME="$tmp" \
  MAROLA_PORT="$port" MAROLA_STATIC="$dist" MAROLA_DATA="$tmp/data" MAROLA_DB="$tmp/marola.db" MAROLA_STUDIES="$tmp/studies" \
  "$bin" > "$tmp/server.log" 2>&1 &
pid=$!

"$tools" package-smoke "http://127.0.0.1:$port" "$dist/csp.txt" "$pid"
