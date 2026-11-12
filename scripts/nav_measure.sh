#!/usr/bin/env bash
# Measures the utility strip (`.sitenav`) of every static page at phone widths, in a real browser's
# layout, and fails when the strip is wider than the screen (it would scroll sideways).
# The repo's stub DOM has no layout, so `just quality` cannot see this; run it by hand:
#
#   just dist-build --fixtures
#   CHROMIUM=/path/to/chromium scripts/nav_measure.sh [WIDTH ...]     # default: 390 375
#
# It copies dist to a temp dir, serves it with python3 on 127.0.0.1, loads every page in an iframe
# as wide as the screen and reads scrollWidth of the strip. A browser with its own sandbox needs no
# flag; CHROMIUM_FLAGS adds some (`--no-sandbox` on a host with no user namespaces).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
: "${CHROMIUM:?set CHROMIUM to a chromium binary}"
widths=("$@")
[ "${#widths[@]}" -gt 0 ] || widths=(390 375)
[ -f "$root/dist/about.html" ] || { echo "nav_measure: run 'just dist-build --fixtures' first" >&2; exit 1; }

tmp="$(mktemp -d)"
server=""
# shellcheck disable=SC2329 # run by the trap
cleanup() {
  [ -z "$server" ] || kill "$server" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

cp -r "$root/dist/." "$tmp/"
cat >"$tmp/measure.html" <<'HTML'
<!doctype html><meta charset=utf-8><pre id=out>wait</pre>
<script>
const pages = ["about", "contact", "news", "members", "support", "privacy", "takedown"]
  .flatMap((p) => [p + ".html", "en/" + p + ".html"]);
const width = Number(new URLSearchParams(location.search).get("w")) || 390;
const lines = [];
for (const page of pages) {
  const frame = document.createElement("iframe");
  // Tall, so the frame has no scrollbar of its own: a phone's is an overlay and takes no width.
  frame.style.cssText = "width:" + width + "px;height:20000px;border:0;display:block";
  frame.src = "/" + page;
  frame.onload = () => {
    const nav = frame.contentDocument.querySelector(".sitenav");
    lines.push("NAV " + page + " " + nav.scrollWidth + " " + width);
    if (lines.length === pages.length) document.getElementById("out").textContent = "RESULT\n" + lines.sort().join("\n") + "\nEND";
  };
  document.body.appendChild(frame);
}
</script>
HTML

port=$((20000 + RANDOM % 20000))
python3 -m http.server "$port" --bind 127.0.0.1 -d "$tmp" >/dev/null 2>&1 &
server=$!
sleep 1

status=0
for width in "${widths[@]}"; do
  # CHROMIUM_FLAGS is meant to split into words.
  # shellcheck disable=SC2086
  out="$("$CHROMIUM" ${CHROMIUM_FLAGS:-} --headless --disable-gpu --virtual-time-budget=10000 --dump-dom "http://127.0.0.1:$port/measure.html?w=$width" 2>/dev/null | grep '^NAV ')"
  [ -n "$out" ] || { echo "nav_measure: the browser printed no result at $width px" >&2; exit 1; }
  while read -r tag page scroll screen; do
    [ "$tag" = NAV ] || continue
    if [ "$scroll" -gt "$screen" ]; then
      echo "nav_measure: $page at $width px: the strip is $scroll px wide, $((scroll - screen)) px too wide"
      status=1
    fi
  done <<<"$out"
done

[ "$status" -eq 0 ] && echo "nav_measure: ok (${widths[*]} px)"
exit "$status"
