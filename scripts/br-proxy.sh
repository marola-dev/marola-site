#!/usr/bin/env bash
# br-proxy — send the hosts that only answer Brazilian addresses through a proxy in Brazil, and
# everything else direct (#4). GitHub's runners are not in Brazil, and INEA (Rio) and INEMA (Bahia)
# time out from them. site.yml and `just site-build` use it when MAROLA_BR_PROXY is set;
# ops/br-proxy/ is the Brazilian end.
#
#   scripts/br-proxy.sh start [HOST...]  with MAROLA_BR_PROXY=[http://][user:pass@]host:port, start a
#                                        tinyproxy on 127.0.0.1:$BR_ROUTER_PORT (8899) that sends
#                                        HOST... (default: ops/br-proxy/hosts) through it, and print
#                                        the JVM options for it
#   scripts/br-proxy.sh stop             stop that tinyproxy
#   scripts/br-proxy.sh config [HOST...] print that tinyproxy config, with a placeholder upstream
#   scripts/br-proxy.sh --self-test
#
# start always exits 0, and prints nothing when the route cannot be trusted: no MAROLA_BR_PROXY, a
# malformed one, no tinyproxy, a router that does not come up, or no host answering through it.
# The caller then runs exactly as without the proxy. Its log is $BR_PROXY_DIR/tinyproxy.log.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${BR_ROUTER_PORT:-8899}"
tinyproxy="${TINYPROXY:-tinyproxy}"
dir="${BR_PROXY_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/marola-br-proxy}"
hosts_file="$root/ops/br-proxy/hosts"

say() { echo "br-proxy: $*" >&2; }
warn() { echo "::warning::br-proxy: $*" >&2; }

# MAROLA_BR_PROXY without an http:// in front, or nothing (status 1) when it is not
# [user:pass@]host:port.
upstream() {
  local v="${1#http://}"
  v="${v%/}"
  [[ "$v" =~ ^([^:@/[:space:]]+:[^@/[:space:]]+@)?[A-Za-z0-9.-]+:[0-9]+$ ]] || return 1
  printf '%s\n' "$v"
}

hosts() { grep -v '^[[:space:]]*\(#\|$\)' "$hosts_file"; }

# A host that matches no Upstream line goes direct: there is deliberately no default upstream.
config() { # <upstream> <log file> <pid file> HOST...
  local up=$1 log=$2 pid=$3 h
  shift 3
  cat <<EOF
Port $port
Listen 127.0.0.1
Allow 127.0.0.1
Timeout 120
MaxClients 50
LogLevel Info
LogFile "$log"
PidFile "$pid"
EOF
  for h in "$@"; do printf 'Upstream http %s "%s"\n' "$up" "$h"; done
}

jvm_options() {
  echo "-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=$port -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=$port"
}

# A 2xx or 3xx means the host answered through Brazil. tinyproxy answers 5xx itself when the
# upstream is down, and the Brazilian end 403 (filter) or 407 (password) when it is misconfigured.
answered() { [[ "$1" =~ ^[23][0-9][0-9]$ ]]; }

# Status 0 when at least one host answers through the route.
probe() {
  local h code ok=1
  for h in "$@"; do
    code="$(curl -sS -m "${BR_PROBE_TIMEOUT:-20}" -o /dev/null -w '%{http_code}' \
      -x "http://127.0.0.1:$port" "http://$h/" 2>/dev/null || true)"
    if answered "$code"; then
      say "$h answers through MAROLA_BR_PROXY (HTTP $code)"
      ok=0
    else
      warn "$h did not answer through MAROLA_BR_PROXY (HTTP ${code:-none})"
    fi
  done
  return "$ok"
}

# tinyproxy can take seconds to exit on TERM, holding the port a restart needs.
stop() {
  local pid
  [ -f "$dir/tinyproxy.pid" ] || return 0
  pid="$(cat "$dir/tinyproxy.pid")"
  rm -f "$dir/tinyproxy.pid"
  kill "$pid" 2>/dev/null || return 0
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.5
  done
  kill -9 "$pid" 2>/dev/null || true
}

start() {
  local up
  if [ "$#" -eq 0 ]; then mapfile -t hosts_given < <(hosts) && set -- "${hosts_given[@]}"; fi
  if [ -z "${MAROLA_BR_PROXY:-}" ]; then
    say "MAROLA_BR_PROXY is not set: no route, $* reached direct as before"
    return 0
  fi
  if ! up="$(upstream "$MAROLA_BR_PROXY")"; then
    warn "MAROLA_BR_PROXY is not [http://][user:pass@]host:port; no route"
    return 0
  fi
  if ! command -v "$tinyproxy" >/dev/null; then
    warn "tinyproxy is not installed; no route"
    return 0
  fi
  stop
  mkdir -p "$dir"
  config "$up" "$dir/tinyproxy.log" "$dir/tinyproxy.pid" "$@" >"$dir/tinyproxy.conf"
  if ! "$tinyproxy" -c "$dir/tinyproxy.conf"; then
    warn "tinyproxy did not start; no route"
    return 0
  fi
  for _ in $(seq 1 20); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      if probe "$@"; then
        jvm_options
      else
        warn "no host answered through MAROLA_BR_PROXY; no route"
        stop
      fi
      return 0
    fi
    sleep 0.5
  done
  warn "tinyproxy is not listening on 127.0.0.1:$port; no route"
  stop
}

self_test() {
  local fails=0 out t
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
  check "an http:// in front and a / behind are dropped" "$(upstream http://u:p@br.example:8888/)" "u:p@br.example:8888"
  check "no port is refused" "$(upstream br.example || true)" ""
  check "a path is refused" "$(upstream br.example:8888/x || true)" ""

  check "the default hosts are the two Brazil-only agencies" "$(hosts | tr '\n' ' ')" \
    "www.inea.rj.gov.br balneabilidade.inema.ba.gov.br "
  check "the Brazilian end's filter allows each of them" \
    "$(hosts | grep -cEf "$root/ops/br-proxy/filter")" 2
  check "and nothing else" "$(printf 'open-meteo.com\noverpass-api.de\ninea.rj.gov.br.evil.example\n' |
    grep -cEf "$root/ops/br-proxy/filter" || true)" 0

  out="$(config 'u:p@br.example:8888' /tmp/br-proxy.log /tmp/br-proxy.pid www.inea.rj.gov.br balneabilidade.inema.ba.gov.br)"
  check "each host given goes through Brazil" \
    "$(grep -cE '^Upstream http u:p@br\.example:8888 "(www\.inea\.rj|balneabilidade\.inema\.ba)\.gov\.br"$' <<<"$out")" 2
  check "no default upstream: every Upstream line names a host" \
    "$(grep '^Upstream' <<<"$out" | grep -cv ' "[^"]*"$' || true)" 0
  check "the router listens on loopback only" "$(grep -cFx 'Listen 127.0.0.1' <<<"$out")" 1
  check "the JVM options point both schemes at the router" "$(jvm_options)" \
    "-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=8899 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=8899"

  check "a redirect counts as an answer" "$(answered 301 && echo y)" y
  check "tinyproxy's own 5xx (upstream down) does not" "$(answered 502 || echo n)" n
  check "a refusal by the Brazilian end does not" "$(answered 403 || echo n)" n
  check "no answer at all does not" "$(answered 000 || echo n)" n

  # start prints JVM options only for a route that answers; none of these starts a proxy, and each
  # exits 0, so the build carries on without one.
  t="$(mktemp -d)"
  check "no MAROLA_BR_PROXY: no JVM options" "$(MAROLA_BR_PROXY='' start 2>/dev/null)" ""
  check "a malformed one: none either" "$(MAROLA_BR_PROXY='not a proxy' start 2>/dev/null)" ""
  check "no tinyproxy: none either" \
    "$(tinyproxy=/nonexistent/tinyproxy MAROLA_BR_PROXY=br.example:8888 start 2>/dev/null)" ""
  check "a tinyproxy that fails: none either, and status 0" \
    "$(dir="$t" tinyproxy=false MAROLA_BR_PROXY=br.example:8888 start 2>/dev/null && echo exit0)" "exit0"
  rm -rf "$t"

  if [ "$fails" -eq 0 ]; then echo "br-proxy self-test: ok"; else
    echo "br-proxy self-test: $fails failure(s)" >&2
    return 1
  fi
}

case "${1:-}" in
  start) shift && start "$@" ;;
  stop) stop ;;
  config)
    shift
    if [ "$#" -eq 0 ]; then mapfile -t hosts_given < <(hosts) && set -- "${hosts_given[@]}"; fi
    config "user:pass@br-proxy.example:8888" "$dir/tinyproxy.log" "$dir/tinyproxy.pid" "$@"
    ;;
  --self-test) self_test ;;
  *)
    echo "usage: scripts/br-proxy.sh start [HOST...] | stop | config [HOST...] | --self-test" >&2
    exit 2
    ;;
esac
