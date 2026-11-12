#!/usr/bin/env bash
# Starts the built server (back/server) on a free port against dist, checks what it answers (headers,
# hostile paths, the contact form, the study API), and stops it. Run `scripts/site_build.sh --fixtures` first.
# MAROLA_SERVER_BIN=<path> runs that executable instead of the one cabal builds (the Nix package's,
# for example); SMOKE_STATIC=<dir> serves another built page than dist.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

static="${SMOKE_STATIC:-$root/dist}"
tools=(node)
[ -n "${MAROLA_SERVER_BIN:-}" ] || tools+=(cabal)
for tool in "${tools[@]}"; do
  command -v "$tool" >/dev/null || { echo "server_smoke: $tool is not installed; run inside 'nix develop'" >&2; exit 1; }
done
[ -f "$static/index.html" ] || { echo "server_smoke: $static is missing; run 'just dist-build --fixtures'" >&2; exit 1; }

if [ -n "${MAROLA_SERVER_BIN:-}" ]; then
  server=("$MAROLA_SERVER_BIN")
else
  cabal build -v0 exe:marola-server >&2
  server=("$(cabal list-bin marola-server)")
fi

tmp="$(mktemp -d)"
pid=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  [ -z "${gh_pid:-}" ] || kill "$gh_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/data/floripa"
printf '{"smoke":true}\n' > "$tmp/data/floripa/latest.json"

port="$(node -e 'const s = require("net").createServer().listen(0, "127.0.0.1", () => { console.log(s.address().port); s.close(); });')"
# A file only MAROLA_TILES holds; the base map itself, tiles/marola.pmtiles, is the fixture in dist.
mkdir -p "$tmp/tiles"
printf 'smoke tiles\n' > "$tmp/tiles/smoke.pmtiles"
[ -f "$static/tiles/marola.pmtiles" ] || { echo "server_smoke: $static/tiles/marola.pmtiles is missing; run 'just dist-build --fixtures'" >&2; exit 1; }
export MAROLA_PORT="$port" MAROLA_STATIC="$static" MAROLA_DATA="$tmp/data" MAROLA_DB="$tmp/marola.db" MAROLA_STUDIES="$tmp/studies" MAROLA_TILES="$tmp/tiles"

# The GitHub login runs against a fake GitHub (scripts/fake_github.mjs). MAROLA_DEV=1 lets the server take its
# URLs from the environment and drop `Secure` and the `__Host-` prefix, which plain HTTP cannot carry.
gh_secret="fake-smoke-client-secret"
printf '%s\n' "$gh_secret" > "$tmp/github-secret"
node scripts/fake_github.mjs "$gh_secret" > "$tmp/github.port" &
gh_pid=$!
for _ in $(seq 1 50); do [ -s "$tmp/github.port" ] && break; sleep 0.1; done
gh_port="$(cat "$tmp/github.port")"
export MAROLA_DEV=1 MAROLA_GITHUB_CLIENT_ID=smoke-client MAROLA_GITHUB_CLIENT_SECRET_FILE="$tmp/github-secret" \
  MAROLA_GITHUB_BASE="http://127.0.0.1:$gh_port" MAROLA_GITHUB_API_BASE="http://127.0.0.1:$gh_port"

"${server[@]}" > "$tmp/server.log" 2>&1 &
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

node scripts/server_smoke.mjs "http://127.0.0.1:$port" "${server[@]}" inbox


# Studies: an account and a key from the CLI (MAROLA_DEV=1 for that one command only), a 2 MB PDF built here,
# so the upload route's own body limit is proved, while every other route keeps the 1 MB one.
{
  printf '%%PDF-1.4\n%%'
  head -c 2000000 /dev/zero | tr '\0' 'x'
  printf '\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\nstartxref\n9\n%%%%EOF\n'
} > "$tmp/study.pdf"
sha="$(sha256sum "$tmp/study.pdf" | cut -d' ' -f1)"
key="$("${server[@]}" dev-account --login smoke --age-days 30)"
node scripts/server_smoke_studies.mjs "http://127.0.0.1:$port" "$key" "$tmp/study.pdf" "$sha" "$tmp/studies"
if grep -q "$key" "$tmp/server.log"; then
  echo "server_smoke: the API key is in the server log" >&2
  exit 1
fi


# The web side: login, a key, the form with its token, the study page, a report, a withdrawal.
node scripts/server_smoke_submit.mjs "http://127.0.0.1:$port" "$tmp/study.pdf" "$sha"

# The board's commands on the same database (docs/6-board.md): hide a study, see its tombstone and that its file is
# not served, purge it, see the file go, and see the exit codes.
board() { "${server[@]}" "$@"; }
read -r api_id _ < <(board studies list --status public)
[ -n "$api_id" ] || { echo "server_smoke: the board's list shows no public study" >&2; exit 1; }
board studies hide "$api_id" --reason "smoke: hidden by the board" > /dev/null
node scripts/server_smoke_board.mjs "http://127.0.0.1:$port" "$api_id" "$sha" "$tmp/studies" hidden
purged="$(board studies hide "$api_id" --reason "smoke: purge" --purge)"
case "$purged" in "purged $sha"*) ;; *) echo "server_smoke: the purge printed no record line: $purged" >&2; exit 1 ;; esac
node scripts/server_smoke_board.mjs "http://127.0.0.1:$port" "$api_id" "$sha" "$tmp/studies" purged
rc=0; board studies unhide "$api_id" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { echo "server_smoke: unhide of a purged study exited $rc, not 1" >&2; exit 1; }
rc=0; board studies hide "$api_id" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "server_smoke: hide with no reason exited $rc, not 2" >&2; exit 1; }
board reports --open | grep -q '^#1 ' || { echo "server_smoke: the board's report list lacks the report" >&2; exit 1; }
board reports close 1 --note "smoke: closed" > /dev/null
[ -z "$(board reports --open)" ] || { echo "server_smoke: a closed report is still open" >&2; exit 1; }
echo "server_smoke: the board's commands hide, purge and close as documented"
for secret in "$gh_secret" gho_fakeSmokeToken0123456789 fakecode; do
  if grep -q -e "$secret" "$tmp/server.log"; then
    echo "server_smoke: a GitHub token, code or secret is in the server log" >&2
    exit 1
  fi
done
echo "server_smoke: the log holds no GitHub token, code or secret"
# Logging: no address, no query, no body in the server's log (LGPD).
cp "$tmp/server.log" "$tmp/requests.log"
if grep -q -e '127\.0\.0\.1' -e 'smoke@example' -e 'evil.example' -e 'sent=1' "$tmp/requests.log"; then
  echo "server_smoke: the log holds a client address, an email, an origin or a query" >&2
  grep -e '127\.0\.0\.1' -e 'smoke@example' -e 'evil.example' -e 'sent=1' "$tmp/requests.log" >&2
  exit 1
fi
echo "server_smoke: the log holds no address, email or query"
