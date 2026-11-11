#!/usr/bin/env bash
# Starts the built server on a free port against app/dist, checks what it answers (headers, hostile
# paths, the contact form), and stops it. Run `just app-build --fixtures` first.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

for tool in node dotnet; do
  command -v "$tool" >/dev/null || { echo "server_smoke: $tool is not installed; run inside 'nix develop'" >&2; exit 1; }
done
[ -f app/dist/index.html ] || { echo "server_smoke: app/dist is missing; run 'just app-build --fixtures'" >&2; exit 1; }

RestoreLockedMode=true dotnet build app/Server -c Release --nologo -v q >/dev/null
dll="$root/app/Server/bin/Release/net10.0/marola-server.dll"

tmp="$(mktemp -d)"
pid=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/data/floripa"
printf '{"smoke":true}\n' > "$tmp/data/floripa/latest.json"

port="$(node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); });')"
export MAROLA_PORT="$port" MAROLA_STATIC="$root/app/dist" MAROLA_DATA="$tmp/data" MAROLA_DB="$tmp/marola.db"

dotnet "$dll" > "$tmp/server.log" 2>&1 &
pid=$!

ready=0
for _ in $(seq 1 100); do
  if node -e 'fetch(process.argv[1]).then(() => process.exit(0), () => process.exit(1))' "http://127.0.0.1:$port/" 2>/dev/null; then
    ready=1
    break
  fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.2
done
[ "$ready" -eq 1 ] || { echo "server_smoke: the server did not start" >&2; cat "$tmp/server.log" >&2; exit 1; }

# The target is MemoryMax=256M; the process must start well under 100 MB.
rss_kb="$(grep VmRSS "/proc/$pid/status" | tr -dc '0-9')"
echo "server_smoke: resident set after start: $((rss_kb / 1024)) MB"
[ "$rss_kb" -lt 102400 ] || { echo "server_smoke: the server uses more than 100 MB at start" >&2; exit 1; }

node scripts/server_smoke.mjs "http://127.0.0.1:$port" dotnet "$dll" inbox

# Logging: no address, no query, no body in the server's log (LGPD).
grep -v Microsoft.Hosting.Lifetime "$tmp/server.log" > "$tmp/requests.log" || true
if grep -q -e '127\.0\.0\.1' -e 'smoke@example' -e 'evil.example' -e 'sent=1' "$tmp/requests.log"; then
  echo "server_smoke: the log holds a client address, an email, an origin or a query" >&2
  grep -e '127\.0\.0\.1' -e 'smoke@example' -e 'evil.example' -e 'sent=1' "$tmp/requests.log" >&2
  exit 1
fi
echo "server_smoke: the log holds no address, email or query"
