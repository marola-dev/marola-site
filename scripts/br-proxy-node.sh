#!/usr/bin/env bash
# br-proxy-node — run this machine as a node of the Brazilian proxy pool (#4): ops/br-proxy/JOIN.md.
# Containers only (ops/br-proxy/compose.yml); it never installs anything on the host and never
# touches the host's network or your router.
#
#   scripts/br-proxy-node.sh up                     start the proxy; make the password if there is none
#   scripts/br-proxy-node.sh down                   stop it
#   scripts/br-proxy-node.sh status                 container state and uptime
#   scripts/br-proxy-node.sh check                  the test CI's flight check makes, plus the refusals
#   scripts/br-proxy-node.sh check --from-outside URL
#                                                   the same through the public address
#                                                   http://user:pass@host:port (or BR_PROXY_URL), from
#                                                   another network: proves the router's port forward
#
# BR_PROXY_NODE_EXEC overrides how check runs a command next to the proxy (default: docker compose
# exec into the proxy service), so the check can be pointed at a bare proxy container.
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
    compose exec -T proxy "$@"
  fi
}

env_get() { grep -m1 "^$1=" "$dir/.env" 2>/dev/null | cut -d= -f2- || true; }

up() {
  need_docker
  local user pass port
  [ -f "$dir/.env" ] || cp "$dir/.env.example" "$dir/.env"
  pass="$(env_get BR_PROXY_PASSWORD)"
  if [ -z "$pass" ]; then
    pass="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
    [ "${#pass}" -eq 24 ] || die "could not read /dev/urandom"
    if grep -q '^BR_PROXY_PASSWORD=' "$dir/.env"; then
      sed -i "s/^BR_PROXY_PASSWORD=.*/BR_PROXY_PASSWORD=$pass/" "$dir/.env"
    else
      echo "BR_PROXY_PASSWORD=$pass" >>"$dir/.env"
    fi
    say "made a password in ops/br-proxy/.env (never commit that file)"
  fi
  user="$(env_get BR_PROXY_USER)"
  port="$(env_get BR_PROXY_PORT)"
  compose up -d --build
  say "up. Forward TCP ${port:-8888} on your router to this machine, then: just br-proxy-node check"
  say "Send the admin this line, privately (a DM; never an issue, a PR or a group chat), with your"
  say "public IP or DNS name in place of the placeholder (this script cannot know it):"
  echo "http://$user:$pass@<YOUR_PUBLIC_IP_OR_DNS>:${port:-8888}"
}

down() {
  need_docker
  compose down
  say "stopped. To leave the pool for good, tell the admin first, then see ops/br-proxy/JOIN.md (Leaving)"
}

status() {
  need_docker
  local id
  id="$(compose ps -q proxy 2>/dev/null)"
  if [ -z "$id" ]; then
    say "not running (just br-proxy-node up)"
    return 1
  fi
  docker inspect -f 'state:    {{.State.Status}}{{"\n"}}up since: {{.State.StartedAt}}{{"\n"}}ports:    {{range $p, $b := .NetworkSettings.Ports}}{{$p}} -> {{range $b}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "$id"
}

# "<HTTP status> <CONNECT status>" of a request through a proxy ($1 = proxy URL, $2 = user:pass or
# empty, $3 = target). The password is a curl argument, never printed.

via() {
  local cred=()
  [ -z "$2" ] || cred=(--proxy-user "$2")
  "${curl[@]}" -sS -m 20 -o /dev/null -w '%{http_code} %{http_connect}' -x "$1" "${cred[@]}" "$3" 2>/dev/null || true
}

check() {
  local proxy cred outside fails=0 out code connect url wrong
  if [ "${1:-}" = --from-outside ]; then
    outside="${2:-${BR_PROXY_URL:-}}"
    [ -n "$outside" ] || die "check --from-outside needs the public address: http://user:pass@host:port (or BR_PROXY_URL)"
    [[ "$outside" =~ ^http://([^:@/]+:[^@/]+)@([^@/]+)$ ]] || die "not http://user:pass@host:port"
    cred="${BASH_REMATCH[1]}"
    proxy="http://${BASH_REMATCH[2]}"
    curl=(curl)
  else
    [ -n "${BR_PROXY_NODE_EXEC:-}" ] || need_docker
    cred="$(near printenv BR_PROXY_AUTH)" || die "the proxy is not running (just br-proxy-node up)"
    proxy="http://127.0.0.1:8888"
    curl=(near curl)
  fi
  wrong="${cred%%:*}:wrong-password-0000"
  ok() { echo "  ok   $*"; }
  bad() {
    echo "  FAIL $*"
    fails=$((fails + 1))
  }
  for url in https://www.inea.rj.gov.br/ http://balneabilidade.inema.ba.gov.br/; do
    out="$(via "$proxy" "$cred" "$url")"
    code="${out%% *}"
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then ok "$url answers through the node (HTTP $code)"; else
      bad "$url does not answer through the node (HTTP ${code:-none}); CI's flight check would skip this node"
    fi
  done
  out="$(via "$proxy" "$cred" http://example.com/)"
  if [ "${out%% *}" = 403 ]; then ok "http://example.com/ is refused (403)"; else bad "http://example.com/ is not refused: [$out]"; fi
  out="$(via "$proxy" "$cred" https://example.com/)"
  connect="${out#* }"
  if [ "$connect" = 403 ]; then ok "https://example.com/ is refused (CONNECT 403)"; else bad "https://example.com/ is not refused: [$out]"; fi
  out="$(via "$proxy" "$cred" https://www.inea.rj.gov.br:8443/)"
  connect="${out#* }"
  if [ "$connect" = 403 ]; then ok "a tunnel to a port other than 443 is refused (CONNECT 403)"; else bad "a tunnel to port 8443 is not refused: [$out]"; fi
  out="$(via "$proxy" "" https://www.inea.rj.gov.br/)"
  connect="${out#* }"
  if [ "$connect" = 407 ]; then ok "no password: refused (407)"; else bad "no password is not refused with 407: [$out]"; fi
  out="$(via "$proxy" "$wrong" https://www.inea.rj.gov.br/)"
  connect="${out#* }"
  if [ "$connect" = 407 ]; then ok "a wrong password: refused (407)"; else bad "a wrong password is not refused with 407: [$out]"; fi

  if [ "$fails" -eq 0 ]; then echo "br-proxy-node check: ok"; else
    echo "br-proxy-node check: $fails failure(s)" >&2
    return 1
  fi
}

case "${1:-status}" in
  up) up ;;
  down) down ;;
  status) status ;;
  check)
    shift
    check "$@"
    ;;
  *)
    echo "usage: scripts/br-proxy-node.sh up | down | status | check [--from-outside URL]" >&2
    exit 2
    ;;
esac
