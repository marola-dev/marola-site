#!/usr/bin/env bash
# Starts the server of the Nix package (bin/marola-server over share/marola/dist) on a free port with
# its state in a temp dir, and checks that the pages and the study API answer 200 with the CSP header.
# Usage: scripts/package_smoke.sh [<package path>]   (default: `nix build .#default`, as `just package-smoke`)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

command -v node >/dev/null || { echo "package_smoke: node is not installed; run inside 'nix develop'" >&2; exit 1; }

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

port="$(node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); });')"

# Only the variables a host sets: an empty PATH, no secret.
env -i PATH=/nonexistent HOME="$tmp" \
  MAROLA_PORT="$port" MAROLA_STATIC="$dist" MAROLA_DATA="$tmp/data" MAROLA_DB="$tmp/marola.db" MAROLA_STUDIES="$tmp/studies" \
  "$bin" > "$tmp/server.log" 2>&1 &
pid=$!

node --input-type=module - "http://127.0.0.1:$port" "$dist/csp.txt" "$pid" <<'JS'
import { readFileSync } from "node:fs";

const [base, cspFile, pid] = process.argv.slice(2);
// The server's header is csp.txt (the page's policy) plus form-action, which a <meta> cannot carry.
const csp = readFileSync(cspFile, "utf8").trim();

const get = async (path) => {
  for (let i = 0; i < 100; i++) {
    try {
      return await fetch(base + path);
    } catch {
      await new Promise((r) => setTimeout(r, 200));
    }
  }
  throw new Error("the server did not start");
};

let bad = 0;
for (const path of ["/", "/about.html", "/en/studies", "/api/v1/skill.md"]) {
  const res = await get(path);
  const header = res.headers.get("content-security-policy");
  await res.arrayBuffer();
  const same = header !== null && header.startsWith(csp);
  const ok = res.status === 200 && same;
  if (!ok) bad++;
  console.log(`package_smoke: ${ok ? "ok  " : "FAIL"} ${res.status} ${path}${same ? "" : " (no CSP header, or not csp.txt's policy)"}`);
}

const rss = readFileSync(`/proc/${pid}/status`, "utf8").match(/VmRSS:\s+(\d+) kB/);
console.log(`package_smoke: resident set after the requests: ${rss ? Math.round(Number(rss[1]) / 1024) : "?"} MB`);
process.exit(bad === 0 ? 0 : 1);
JS
