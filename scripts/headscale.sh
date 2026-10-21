#!/usr/bin/env bash
# headscale — the tailnet's coordination server (#171), in a container: ops/br-proxy/headscale/.
#
#   scripts/headscale.sh up        start it (needs ops/br-proxy/headscale/.env, tcp 443 open)
#   scripts/headscale.sh down      stop; the database stays in its volume
#   scripts/headscale.sh logs      follow its log
#   scripts/headscale.sh nodes     the devices that joined
#   scripts/headscale.sh key-ci    a reusable, ephemeral key for tag:ci: the HEADSCALE_AUTHKEY secret
#   scripts/headscale.sh key-node  a one-off key for tag:br-proxy: a volunteer's TS_AUTHKEY
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$root/ops/br-proxy/headscale"
owner=marola # the policy's tagOwners name this user

say() { echo "headscale: $*" >&2; }
die() {
  say "$*"
  exit 1
}

compose() { docker compose --project-directory "$dir" -f "$dir/compose.yml" "$@"; }
hs() { compose exec -T headscale headscale "$@"; }

need_docker() {
  command -v docker >/dev/null || die "docker is not installed; install Docker first (this recipe installs nothing)"
  docker compose version >/dev/null 2>&1 || die "docker compose (v2) is not available; install the compose plugin first"
  docker info >/dev/null 2>&1 || die "the docker daemon is not reachable (is it running, and may you use it?)"
}

# preauthkeys takes the user's numeric ID; creating twice fails on the unique name, which is fine.
key() {
  need_docker
  command -v jq >/dev/null || die "jq is not installed (nix develop has it)"
  local id
  hs users create "$owner" >/dev/null 2>&1 || true
  id="$(hs users list -n "$owner" -o json | jq -r '.[0].id // empty')"
  [ -n "$id" ] || die "could not find or create the user $owner; is it running? (just headscale up)"
  hs preauthkeys create -u "$id" "$@" -o json | jq -r .key
}

case "${1:-}" in
  up)
    need_docker
    [ -f "$dir/.env" ] || die "no ops/br-proxy/headscale/.env: copy .env.example and set HEADSCALE_HOST"
    compose up -d
    ;;
  down) need_docker && compose down ;;
  logs) need_docker && compose logs -f headscale ;;
  nodes) need_docker && hs nodes list ;;
  key-ci) key --reusable --ephemeral --tags tag:ci -e 90d ;;
  key-node) key --tags tag:br-proxy -e 1d ;;
  *)
    echo "usage: scripts/headscale.sh up | down | logs | nodes | key-ci | key-node" >&2
    exit 2
    ;;
esac
