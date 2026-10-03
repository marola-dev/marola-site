#!/usr/bin/env bash
# Write <dist>/mapbox-config.js from MAPBOX_PUBLIC_TOKEN and MAPBOX_STYLE (site.yml, at deploy).
#
#   MAPBOX_PUBLIC_TOKEN=pk.… scripts/mapbox_config.sh site/dist
#   scripts/mapbox_config.sh --self-test
#
# The file reaches every visitor, so only a public pk. token may go in it; an sk. token fails the
# build. No token leaves the committed empty config, and the page says the map needs one.
set -euo pipefail

write() {
  local dist="$1" token="${MAPBOX_PUBLIC_TOKEN:-}" style="${MAPBOX_STYLE:-}"
  [ -d "$dist" ] || { echo "mapbox_config: no $dist — build the site first" >&2; exit 1; }
  case "$token" in
    sk.*) echo "mapbox_config: MAPBOX_PUBLIC_TOKEN is a secret (sk.) token; use a public pk. token" >&2; exit 1 ;;
    "") echo "::warning::mapbox_config: MAPBOX_PUBLIC_TOKEN is not set, so marola.dev shows no base map" >&2 ;;
    pk.*) [[ "$token" =~ ^pk\.[A-Za-z0-9._-]+$ ]] || { echo "mapbox_config: the token has characters a Mapbox token never has" >&2; exit 1; } ;;
    *) echo "mapbox_config: MAPBOX_PUBLIC_TOKEN does not start with pk." >&2; exit 1 ;;
  esac
  if [ -n "$style" ] && ! [[ "$style" =~ ^mapbox://styles/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$ ]]; then
    echo "mapbox_config: MAPBOX_STYLE must look like mapbox://styles/<user>/<style id>" >&2; exit 1
  fi
  printf '// written by scripts/mapbox_config.sh at deploy\nwindow.MAROLA_MAPBOX = { token: "%s", style: "%s" };\n' \
    "$token" "$style" >"$dist/mapbox-config.js"
  echo "mapbox_config: wrote $dist/mapbox-config.js (token ${token:+${token:0:8}…}${token:-none}, style ${style:-default})" >&2
}

self_test() {
  local t f=0
  t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  run() { env -u MAPBOX_PUBLIC_TOKEN -u MAPBOX_STYLE "$@" bash "${BASH_SOURCE[0]}" "$t" 2>/dev/null; }
  run MAPBOX_PUBLIC_TOKEN=pk.eyJabc.def-1_2 MAPBOX_STYLE=mapbox://styles/marola/abc123 || { echo "FAIL: a pk. token and a style"; f=1; }
  grep -qx 'window.MAROLA_MAPBOX = { token: "pk.eyJabc.def-1_2", style: "mapbox://styles/marola/abc123" };' "$t/mapbox-config.js" \
    || { echo "FAIL: the config does not carry the token and style"; f=1; }
  run MAPBOX_PUBLIC_TOKEN=sk.eyJsecret && { echo "FAIL: an sk. token was written"; f=1; }
  grep -qF 'sk.' "$t/mapbox-config.js" && { echo "FAIL: an sk. token reached the file"; f=1; }
  run MAPBOX_PUBLIC_TOKEN='pk.a"; alert(1); "' && { echo "FAIL: a token with quotes was written"; f=1; }
  run MAPBOX_PUBLIC_TOKEN=tk.abc && { echo "FAIL: a token that is not pk. was written"; f=1; }
  run MAPBOX_PUBLIC_TOKEN=pk.abc MAPBOX_STYLE='https://evil.example/style.json' && { echo "FAIL: a non-mapbox:// style was written"; f=1; }
  run || { echo "FAIL: no token should warn, not fail"; f=1; }
  grep -q 'token: ""' "$t/mapbox-config.js" || { echo "FAIL: no token should leave it empty"; f=1; }
  echo "mapbox_config self-test:" "$([ "$f" -eq 0 ] && echo ok || echo FAILED)"
  [ "$f" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  "" | -*) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  *) write "$1" ;;
esac
