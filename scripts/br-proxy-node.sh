#!/usr/bin/env bash
# br-proxy-node — run this machine as a node of the Brazilian proxy pool (#4): ops/br-proxy/JOIN.md.
# Containers only (ops/br-proxy/compose.yml); it never installs anything on the host and never
# touches the host's network or its own Tailscale.
#
#   scripts/br-proxy-node.sh up       join (with the one-off key from ops/br-proxy/.env or a prompt)
#   scripts/br-proxy-node.sh down     stop; the node keeps its identity for the next `up`
#   scripts/br-proxy-node.sh status   tailnet, name, tag, uptime
#   scripts/br-proxy-node.sh check    the same test CI's flight check makes, plus the refusals
#
# BR_PROXY_NODE_EXEC overrides how check runs a command next to the proxy (default: docker compose
# exec into the tinyproxy service), so the check can be pointed at a bare tinyproxy container.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$root/ops/br-proxy"

say() { echo "br-proxy-node: $*" >&2; }
die() {
  say "$*"
  exit 1
}

compose() { docker compose --project-directory "$dir" -f "$dir/compose.yml" "$@"; }

need_docker() {
  command -v docker >/dev/null || die "docker is not installed; install Docker first (this recipe installs nothing)"
  docker compose version >/dev/null 2>&1 || die "docker compose (v2) is not available; install the compose plugin first"
  docker info >/dev/null 2>&1 || die "the docker daemon is not reachable (is it running, and may you use it?)"
}

near() {
  if [ -n "${BR_PROXY_NODE_EXEC:-}" ]; then
    # shellcheck disable=SC2086 # a command prefix, split on purpose
    ${BR_PROXY_NODE_EXEC} "$@"
  else
    compose exec -T tinyproxy "$@"
  fi
}
in_tailscale() { compose exec -T tailscale "$@"; }

joined() { compose run --rm --no-deps -T --entrypoint test tailscale -s /var/lib/tailscale/tailscaled.state 2>/dev/null; }

up() {
  need_docker
  local key=""
  if ! grep -qs '^TS_AUTHKEY=..*' "$dir/.env" && ! joined; then
    [ -t 0 ] || die "no TS_AUTHKEY in ops/br-proxy/.env and no terminal to ask for it"
    read -rsp "One-off auth key from the marola admin (not shown): " key
    echo >&2
    [ -n "$key" ] || die "no key given"
  fi
  if [ -n "$key" ]; then
    TS_AUTHKEY="$key" compose up -d --build
  else
    compose up -d --build
  fi
  for _ in $(seq 1 30); do
    if [ "$(state)" = Running ]; then
      status
      say "up. Next: just br-proxy-node check"
      return 0
    fi
    sleep 2
  done
  say "the node has not joined the tailnet yet (state: $(state)); see: docker compose -f ops/br-proxy/compose.yml logs tailscale"
  return 1
}

down() {
  need_docker
  compose down
  say "stopped. To leave the pool for good, ask the admin to remove the device, then: docker volume rm marola-br-proxy_state"
}

ts_json() { in_tailscale tailscale status --json 2>/dev/null; }
state() { ts_json | near jq -r '.BackendState // "unknown"' 2>/dev/null || echo "not running"; }

status() {
  need_docker
  local started
  if ! started="$(docker inspect -f '{{.State.StartedAt}}' "$(compose ps -q tailscale)" 2>/dev/null)"; then
    say "not running (just br-proxy-node up)"
    return 1
  fi
  ts_json | near jq -r '"tailnet: \(.CurrentTailnet.Name // "none (not joined)")",
    "node:    \(.Self.DNSName // "?" | rtrimstr("."))  \(.Self.TailscaleIPs // [] | join(" "))",
    "state:   \(.BackendState)",
    "tags:    \(.Self.Tags // [] | join(", ") | if . == "" then "none (the admin'"'"'s key must carry tag:br-proxy)" else . end)"'
  echo "up since: $started"
}

# HTTP status of a request through the node's proxy; for https, the CONNECT's own status as well.
via() { near curl -sS -m 20 -o /dev/null -w '%{http_code} %{http_connect}' -x http://127.0.0.1:8888 "$1" 2>/dev/null || true; }

check() {
  [ -n "${BR_PROXY_NODE_EXEC:-}" ] || need_docker
  local fails=0 out code connect
  ok() { echo "  ok   $*"; }
  bad() {
    echo "  FAIL $*"
    fails=$((fails + 1))
  }
  for url in https://www.inea.rj.gov.br/ http://balneabilidade.inema.ba.gov.br/; do
    out="$(via "$url")"
    code="${out%% *}"
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then ok "$url answers through the node (HTTP $code)"; else
      bad "$url does not answer through the node (HTTP ${code:-none}); CI's flight check would skip this node"
    fi
  done
  out="$(via http://example.com/)"
  if [ "${out%% *}" = 403 ]; then ok "http://example.com/ is refused (403)"; else bad "http://example.com/ is not refused: [$out]"; fi
  out="$(via https://example.com/)"
  connect="${out#* }"
  if [ "$connect" = 403 ]; then ok "https://example.com/ is refused (CONNECT 403)"; else bad "https://example.com/ is not refused: [$out]"; fi
  out="$(via https://www.inea.rj.gov.br:8443/)"
  connect="${out#* }"
  if [ "$connect" = 403 ]; then ok "a tunnel to a port other than 443 is refused (CONNECT 403)"; else bad "a tunnel to port 8443 is not refused: [$out]"; fi

  # Where the node egresses, without asking a third-party IP service: Tailscale's own nearest relay.
  if [ -z "${BR_PROXY_NODE_EXEC:-}" ]; then
    out="$(in_tailscale tailscale netcheck 2>/dev/null | grep -i 'nearest derp' || true)"
    case "$out" in
      *Paulo*) ok "egress looks Brazilian (${out#*: })" ;;
      "") say "warning: could not ask tailscale netcheck where the node is" ;;
      *) say "warning: the nearest Tailscale relay is ${out#*: }, not São Paulo: is this machine in Brazil? The agencies refuse non-Brazilian addresses" ;;
    esac
    if [ "$(state)" = Running ]; then ok "on the tailnet"; else say "warning: not on the tailnet yet (state: $(state))"; fi
  fi

  if [ "$fails" -eq 0 ]; then echo "br-proxy-node check: ok"; else
    echo "br-proxy-node check: $fails failure(s)" >&2
    return 1
  fi
}

case "${1:-status}" in
  up) up ;;
  down) down ;;
  status) status ;;
  check) check ;;
  *)
    echo "usage: scripts/br-proxy-node.sh up | down | status | check" >&2
    exit 2
    ;;
esac
