#!/usr/bin/env bash
# br-proxy — send the hosts that only answer Brazilian addresses through a proxy in Brazil, and
# everything else direct (#4). GitHub's runners are not in Brazil, and INEA (Rio) and INEMA (Bahia)
# time out from them. water.yml uses it for those agencies' fetches; ops/br-proxy/ sets up the
# Brazilian end.
#
#   scripts/br-proxy.sh start HOST...   with MAROLA_BR_PROXY=[user:pass@]host:port, start a
#                                       tinyproxy on 127.0.0.1:$BR_ROUTER_PORT (8899) that sends
#                                       HOST... through it, and print the JVM options for it
#   scripts/br-proxy.sh config HOST...  print that tinyproxy config, with a placeholder upstream
#   scripts/br-proxy.sh --self-test
#
# start prints nothing (and warns) when the route cannot exist: no MAROLA_BR_PROXY, a malformed
# one, or a router that does not come up. The fetch then goes direct and, outside Brazil, fails.
set -euo pipefail

port="${BR_ROUTER_PORT:-8899}"
tinyproxy="${TINYPROXY:-tinyproxy}"

warn() { echo "::warning::br-proxy: $*" >&2; }

# MAROLA_BR_PROXY without an http:// in front, or nothing (status 1) when it is not
# [user:pass@]host:port.
upstream() {
  local v="${1#http://}"
  v="${v%/}"
  [[ "$v" =~ ^([^:@/[:space:]]+:[^@/[:space:]]+@)?[A-Za-z0-9.-]+:[0-9]+$ ]] || return 1
  printf '%s\n' "$v"
}

# A host that matches no Upstream line goes direct: there is deliberately no default upstream.
config() { # <upstream> <log file> HOST...
  local up=$1 log=$2 h
  shift 2
  cat <<EOF
Port $port
Listen 127.0.0.1
Allow 127.0.0.1
Timeout 120
MaxClients 50
LogLevel Notice
LogFile "$log"
EOF
  for h in "$@"; do printf 'Upstream http %s "%s"\n' "$up" "$h"; done
}

jvm_options() {
  echo "-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=$port -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=$port"
}

# Informational: any HTTP answer (a redirect included) means the host is reached through Brazil.
probe() {
  local h code
  for h in "$@"; do
    code="$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -x "http://127.0.0.1:$port" "http://$h/" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "$code" != 000 ]; then
      echo "br-proxy: $h answers through MAROLA_BR_PROXY (HTTP $code)" >&2
    else
      warn "$h did not answer through MAROLA_BR_PROXY"
    fi
  done
}

start() {
  local up dir
  if [ "$#" -eq 0 ]; then
    warn "no hosts to route"
    return 0
  fi
  if [ -z "${MAROLA_BR_PROXY:-}" ]; then
    warn "MAROLA_BR_PROXY is not set: $* fetched direct, which times out outside Brazil (#4)"
    return 0
  fi
  if ! up="$(upstream "$MAROLA_BR_PROXY")"; then
    warn "MAROLA_BR_PROXY is not [user:pass@]host:port; fetching direct"
    return 0
  fi
  if ! command -v "$tinyproxy" >/dev/null; then
    warn "tinyproxy is not installed; fetching direct"
    return 0
  fi
  dir="$(mktemp -d)"
  config "$up" "$dir/tinyproxy.log" "$@" >"$dir/tinyproxy.conf"
  if ! "$tinyproxy" -c "$dir/tinyproxy.conf"; then
    warn "tinyproxy did not start; fetching direct"
    return 0
  fi
  for _ in $(seq 1 20); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      probe "$@"
      jvm_options
      return 0
    fi
    sleep 0.5
  done
  warn "tinyproxy is not listening on 127.0.0.1:$port; fetching direct"
}

self_test() {
  local fails=0 out
  check() {
    if [ "$2" = "$3" ]; then
      echo "  ok   $1"
    else
      echo "  FAIL $1 — got [$2], want [$3]"
      fails=$((fails + 1))
    fi
  }
  check "a bare host:port is an upstream" "$(upstream 203.0.113.7:8888)" "203.0.113.7:8888"
  check "credentials are kept" "$(upstream 'marola:s3cret@br.example:8888')" "marola:s3cret@br.example:8888"
  check "an http:// in front and a / behind are dropped" "$(upstream http://br.example:8888/)" "br.example:8888"
  check "no port is refused" "$(upstream br.example || true)" ""
  check "a path is refused" "$(upstream br.example:8888/x || true)" ""

  out="$(config 'u:p@br.example:8888' /tmp/br-proxy.log www.inea.rj.gov.br balneabilidade.inema.ba.gov.br)"
  check "each host given goes through Brazil" \
    "$(grep -cE '^Upstream http u:p@br\.example:8888 "(www\.inea\.rj|balneabilidade\.inema\.ba)\.gov\.br"$' <<<"$out")" 2
  check "no default upstream: every Upstream line names a host" \
    "$(grep '^Upstream' <<<"$out" | grep -cv ' "[^"]*"$' || true)" 0
  check "the router listens on loopback only" "$(grep -cFx 'Listen 127.0.0.1' <<<"$out")" 1
  check "the JVM options point both schemes at the router" "$(jvm_options)" \
    "-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=8899 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=8899"

  # start prints JVM options only for a route that exists; none of these starts a proxy.
  check "no MAROLA_BR_PROXY: no JVM options" "$(MAROLA_BR_PROXY='' start www.inea.rj.gov.br 2>/dev/null)" ""
  check "a malformed one: none either" "$(MAROLA_BR_PROXY='not a proxy' start www.inea.rj.gov.br 2>/dev/null)" ""
  check "no tinyproxy: none either" \
    "$(tinyproxy=/nonexistent/tinyproxy MAROLA_BR_PROXY=br.example:8888 start www.inea.rj.gov.br 2>/dev/null)" ""
  check "no hosts: none either" "$(MAROLA_BR_PROXY=br.example:8888 start 2>/dev/null)" ""

  if [ "$fails" -eq 0 ]; then echo "br-proxy self-test: ok"; else
    echo "br-proxy self-test: $fails failure(s)" >&2
    return 1
  fi
}

case "${1:-}" in
  start) shift && start "$@" ;;
  config) shift && config "user:pass@br-proxy.example:8888" "/tmp/br-proxy.log" "$@" ;;
  --self-test) self_test ;;
  *)
    echo "usage: scripts/br-proxy.sh start HOST... | config HOST... | --self-test" >&2
    exit 2
    ;;
esac
