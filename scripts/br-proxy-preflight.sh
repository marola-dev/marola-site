#!/usr/bin/env bash
# br-proxy-preflight — the flight check before site.yml's board build (#4): find a working node in
# the Brazilian proxy pool, the tailnet's online peers tagged tag:br-proxy (ops/br-proxy/JOIN.md),
# each tried with a real request through it to an allowlisted agency. Prints the first healthy one
# as http://<tailnet IP>:8888, for `MAROLA_BR_PROXY=... scripts/br-proxy.sh start`.
#
#   scripts/br-proxy-preflight.sh               find a node, or fail
#   scripts/br-proxy-preflight.sh --fail CAUSE  fail for CAUSE (site.yml's own causes)
#   scripts/br-proxy-preflight.sh --self-test
#
# Fails closed: with no healthy node it exits 1 with an ::error:: naming the cause, and the build
# stops before any board is built, so nothing deploys and marola.dev keeps the last deployed site.
# BR_PROXY_REQUIRED=false (the repo variable, a break-glass switch) turns that into a warning and
# exit 0, and the build runs without the proxy (INEA and INEMA "no data").
#
# BR_TAILNET is the outcome of site.yml's tailnet step (success, skipped, failure, cancelled; empty
# when run by hand) and BR_FORK_PR=true marks a fork's PR, which gets no secrets.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tailscale="${TAILSCALE:-tailscale}"
curl="${CURL:-curl}"
node_port="${BR_PROXY_NODE_PORT:-8888}"
per_node="${BR_PREFLIGHT_TIMEOUT:-10}"
budget="${BR_PREFLIGHT_BUDGET:-60}"
required="${BR_PROXY_REQUIRED:-true}"
tailnet="${BR_TAILNET:-}"
fork_pr="${BR_FORK_PR:-false}"

say() { echo "br-proxy-preflight: $*" >&2; }

# Only an explicit "false" lets the build go on without the proxy; unset or anything else is true.
fail() {
  if [ "$required" = false ]; then
    echo "::warning::br-proxy flight check: $*. BR_PROXY_REQUIRED=false, so the build goes on without the proxy: INEA (Rio) and INEMA (Bahia) read 'no data'." >&2
    return 0
  fi
  echo "::error::br-proxy flight check: $*. The build stops here: no boards, no deploy, and marola.dev keeps serving the last deployed site. Fix the pool (ops/br-proxy/JOIN.md), or, to deploy without it for now (Rio and Salvador water quality 'no data'), set the repo variable BR_PROXY_REQUIRED=false and set it back afterwards." >&2
  return 1
}

# The first host in ops/br-proxy/hosts, over HTTPS: the request the build itself will make.
target() { echo "https://$(grep -v '^[[:space:]]*\(#\|$\)' "$root/ops/br-proxy/hosts" | head -n 1)/"; }

# `tailscale status --json` on stdin -> "<IPv4> <DNS name>" per online peer tagged tag:br-proxy.
pool() {
  python3 -c '
import json, sys
for p in (json.load(sys.stdin).get("Peer") or {}).values():
    if p.get("Online") and "tag:br-proxy" in (p.get("Tags") or []):
        ip = next((a for a in p.get("TailscaleIPs") or [] if "." in a), None)
        if ip:
            print(ip, (p.get("DNSName") or p.get("HostName") or ip).rstrip("."))
'
}

preflight() {
  local status nodes ip name out code secs url
  if [ "$fork_pr" = true ]; then
    fail "this is a fork's PR: no secrets reach it, so it cannot join the tailnet and cannot run the build check; a maintainer must run it from a branch of this repo"
    return
  fi
  case "$tailnet" in
    "" | success) ;;
    skipped)
      fail "TS_OAUTH_CLIENT_ID/TS_OAUTH_SECRET are not set, so the runner did not join the tailnet"
      return
      ;;
    *)
      fail "the tailnet join failed ($tailnet): see the 'Join the tailnet' step"
      return
      ;;
  esac
  if ! command -v "$tailscale" >/dev/null; then
    fail "no tailscale on this machine, so no tailnet"
    return
  fi
  if ! status="$("$tailscale" status --json 2>/dev/null)"; then
    fail "tailscale status failed: the runner is not connected to the tailnet"
    return
  fi
  nodes="$(pool <<<"$status" || true)"
  if [ -z "$nodes" ]; then
    fail "no tag:br-proxy node is online in the tailnet"
    return
  fi
  url="$(target)"
  SECONDS=0
  while read -r ip name; do
    if [ "$SECONDS" -ge "$budget" ]; then
      say "out of time (${budget}s) before trying $name"
      break
    fi
    out="$("$curl" -x "http://$ip:$node_port" -sS -m "$per_node" -o /dev/null \
      -w '%{http_code} %{time_total}' "$url" 2>/dev/null || true)"
    code="${out%% *}"
    secs="${out#* }"
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
      say "using $name ($ip): $url answered HTTP $code in ${secs}s"
      echo "http://$ip:$node_port"
      return 0
    fi
    say "skipping $name ($ip): $url gave HTTP ${code:-none}"
  done <<<"$nodes"
  fail "tag:br-proxy nodes are online, but none passed the request to $url through it"
}

self_test() {
  local fails=0 t got
  t="$(mktemp -d)"
  trap 'rm -rf "$t"' RETURN
  check() {
    if [ "$2" = "$3" ]; then
      echo "  ok   $1"
    else
      echo "  FAIL $1 — got [$2], want [$3]"
      fails=$((fails + 1))
    fi
  }
  # Four peers: two healthy-able pool nodes (A, B), one offline and one untagged, neither ever tried.
  cat >"$t/status.json" <<'EOF'
{"Peer": {
  "k1": {"HostName": "a", "DNSName": "br-a.example.ts.net.", "Online": true, "Tags": ["tag:br-proxy"], "TailscaleIPs": ["100.64.0.1", "fd7a::1"]},
  "k2": {"HostName": "off", "DNSName": "br-off.example.ts.net.", "Online": false, "Tags": ["tag:br-proxy"], "TailscaleIPs": ["100.64.0.9"]},
  "k3": {"HostName": "laptop", "DNSName": "laptop.example.ts.net.", "Online": true, "TailscaleIPs": ["100.64.0.7"]},
  "k4": {"HostName": "b", "DNSName": "br-b.example.ts.net.", "Online": true, "Tags": ["tag:br-proxy"], "TailscaleIPs": ["fd7a::2", "100.64.0.2"]}
}}
EOF
  printf '#!/usr/bin/env bash\ncat %q\n' "$t/status.json" >"$t/tailscale"
  # The curl stub answers per node from $HEALTHY ("100.64.0.1=200 100.64.0.2=000") and logs each try.
  cat >"$t/curl" <<EOF
#!/usr/bin/env bash
ip="\${2#http://}"; ip="\${ip%:*}"
echo "\$ip" >>"$t/tries"
for kv in \$HEALTHY; do [ "\${kv%%=*}" = "\$ip" ] && { printf '%s 0.25' "\${kv#*=}"; exit 0; }; done
printf '000 10.0'; exit 28
EOF
  chmod +x "$t/tailscale" "$t/curl"
  run() { rm -f "$t/tries"; HEALTHY="$1" tailscale="$t/tailscale" curl="$t/curl" preflight 2>"$t/err"; }
  rc() { "$@" >/dev/null && echo 0 || echo "$?"; }

  check "the pool is the online tag:br-proxy peers, by IPv4" "$(pool <"$t/status.json" | tr '\n' ' ')" \
    "100.64.0.1 br-a.example.ts.net 100.64.0.2 br-b.example.ts.net "
  check "it probes the first allowlisted agency over HTTPS" "$(target)" "https://www.inea.rj.gov.br/"
  got="$(run "100.64.0.1=200 100.64.0.2=200")"
  check "first node healthy: it is the upstream" "$got" "http://100.64.0.1:8888"
  check "and the second is never tried" "$(tr '\n' ' ' <"$t/tries")" "100.64.0.1 "
  check "first node dead, second healthy (a redirect): the second" "$(run "100.64.0.2=301")" "http://100.64.0.2:8888"
  check "a node refusing the host (403) is not healthy: exit 1" "$(rc run "100.64.0.1=403 100.64.0.2=407")" 1
  check "none healthy: exit 1" "$(rc run "")" 1
  check "and the ::error:: names the cause and the consequence" \
    "$(grep -c '^::error::.*none passed the request.*no deploy.*BR_PROXY_REQUIRED=false' "$t/err")" 1
  check "the offline and the untagged peers are never tried" "$(sort "$t/tries" | tr '\n' ' ')" "100.64.0.1 100.64.0.2 "
  printf '#!/usr/bin/env bash\necho %q\n' '{"Peer": {}}' >"$t/ts-empty" && chmod +x "$t/ts-empty"
  check "no node online at all: exit 1, said so" \
    "$(tailscale="$t/ts-empty" rc preflight 2>"$t/err"; grep -c 'no tag:br-proxy node is online' "$t/err")" "1
1"
  check "tailscale missing: exit 1" "$(tailscale="$t/none" rc preflight 2>"$t/err")" 1
  check "and the error says so" "$(grep -c '^::error::.*no tailscale' "$t/err")" 1
  printf '#!/usr/bin/env bash\nexit 1\n' >"$t/ts-down" && chmod +x "$t/ts-down"
  check "tailscale not connected: exit 1" "$(tailscale="$t/ts-down" rc preflight 2>/dev/null)" 1
  check "the tailnet step skipped (no secrets): exit 1, naming the secrets" \
    "$(tailnet=skipped rc preflight 2>"$t/err"; grep -c 'TS_OAUTH_CLIENT_ID/TS_OAUTH_SECRET are not set' "$t/err")" "1
1"
  check "the tailnet join failed: exit 1, naming the step" \
    "$(tailnet=failure rc preflight 2>"$t/err"; grep -c 'the tailnet join failed (failure)' "$t/err")" "1
1"
  check "a fork's PR: exit 1, saying a maintainer must run it" \
    "$(fork_pr=true tailscale="$t/tailscale" rc preflight 2>"$t/err"; grep -c "fork's PR.*a maintainer must run it" "$t/err")" "1
1"
  check "out of time: no further node is tried, exit 1" "$(budget=0 rc run "100.64.0.1=200")" 1
  check "BR_PROXY_REQUIRED=false and no healthy node: exit 0, nothing printed" \
    "$(required=false run "" && echo exit0)" "exit0"
  check "with a ::warning::, not an ::error::" "$(grep -c '^::warning::.*BR_PROXY_REQUIRED=false' "$t/err")/$(grep -c '^::error::' "$t/err" || true)" "1/0"
  check "BR_PROXY_REQUIRED=false with no tailscale: exit 0" "$(required=false tailscale="$t/none" rc preflight 2>/dev/null)" 0
  check "any other value is still required" "$(required=no tailscale="$t/none" rc preflight 2>/dev/null)" 1
  check "--fail CAUSE fails with that cause" "$(rc fail "the override MAROLA_BR_PROXY did not answer" 2>"$t/err"; grep -c 'the override MAROLA_BR_PROXY did not answer' "$t/err")" "1
1"

  if [ "$fails" -eq 0 ]; then echo "br-proxy-preflight self-test: ok"; else
    echo "br-proxy-preflight self-test: $fails failure(s)" >&2
    return 1
  fi
}

case "${1:-}" in
  "") preflight ;;
  --fail) fail "${2:?--fail needs a cause}" ;;
  --self-test) self_test ;;
  *)
    echo "usage: scripts/br-proxy-preflight.sh [--fail CAUSE | --self-test]" >&2
    exit 2
    ;;
esac
