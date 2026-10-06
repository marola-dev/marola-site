#!/usr/bin/env bash
# br-proxy-preflight — find a working node in the Brazilian proxy pool (#4): the tailnet's online
# peers tagged tag:br-proxy (ops/br-proxy/JOIN.md), each tried with a real request through it to an
# allowlisted agency. Prints the first healthy one as http://<tailnet IP>:8888, for
# `MAROLA_BR_PROXY=... scripts/br-proxy.sh start`, and nothing when none is healthy.
#
#   scripts/br-proxy-preflight.sh
#   scripts/br-proxy-preflight.sh --self-test
#
# Always exits 0: no node means no route, and the build runs as it would without the pool.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tailscale="${TAILSCALE:-tailscale}"
curl="${CURL:-curl}"
node_port="${BR_PROXY_NODE_PORT:-8888}"
per_node="${BR_PREFLIGHT_TIMEOUT:-10}"
budget="${BR_PREFLIGHT_BUDGET:-60}"

say() { echo "br-proxy-preflight: $*" >&2; }
warn() { echo "::warning::br-proxy-preflight: $*" >&2; }

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
  if ! command -v "$tailscale" >/dev/null; then
    warn "no tailscale on this machine (the tailnet step did not run or failed): no pool, no route"
    return 0
  fi
  if ! status="$("$tailscale" status --json 2>/dev/null)"; then
    warn "tailscale status failed (not connected?): no pool, no route"
    return 0
  fi
  nodes="$(pool <<<"$status" || true)"
  if [ -z "$nodes" ]; then
    warn "no online tag:br-proxy node in the tailnet: no route"
    return 0
  fi
  url="$(target)"
  SECONDS=0
  while read -r ip name; do
    if [ "$SECONDS" -ge "$budget" ]; then
      warn "out of time (${budget}s) before trying $name"
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
  warn "no healthy tag:br-proxy node: no route"
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
  run() { rm -f "$t/tries"; HEALTHY="$1" tailscale="$t/tailscale" curl="$t/curl" preflight 2>/dev/null; }

  check "the pool is the online tag:br-proxy peers, by IPv4" "$(pool <"$t/status.json" | tr '\n' ' ')" \
    "100.64.0.1 br-a.example.ts.net 100.64.0.2 br-b.example.ts.net "
  check "it probes the first allowlisted agency over HTTPS" "$(target)" "https://www.inea.rj.gov.br/"
  got="$(run "100.64.0.1=200 100.64.0.2=200")"
  check "first node healthy: it is the upstream" "$got" "http://100.64.0.1:8888"
  check "and the second is never tried" "$(tr '\n' ' ' <"$t/tries")" "100.64.0.1 "
  check "first node dead, second healthy (a redirect): the second" "$(run "100.64.0.2=301")" "http://100.64.0.2:8888"
  check "a node refusing the host (403) is not healthy" "$(run "100.64.0.1=403 100.64.0.2=407")" ""
  check "none healthy: nothing, status 0" "$(run "" && echo exit0)" "exit0"
  check "the offline and the untagged peers are never tried" "$(sort "$t/tries" | tr '\n' ' ')" "100.64.0.1 100.64.0.2 "
  check "tailscale missing: nothing, status 0" "$(tailscale="$t/none" preflight 2>/dev/null && echo exit0)" "exit0"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$t/ts-down" && chmod +x "$t/ts-down"
  check "tailscale not connected: nothing, status 0" "$(tailscale="$t/ts-down" preflight 2>/dev/null && echo exit0)" "exit0"
  check "out of time: no further node is tried" "$(budget=0 run "100.64.0.1=200")" ""

  if [ "$fails" -eq 0 ]; then echo "br-proxy-preflight self-test: ok"; else
    echo "br-proxy-preflight self-test: $fails failure(s)" >&2
    return 1
  fi
}

case "${1:-}" in
  "") preflight ;;
  --self-test) self_test ;;
  *)
    echo "usage: scripts/br-proxy-preflight.sh [--self-test]" >&2
    exit 2
    ;;
esac
