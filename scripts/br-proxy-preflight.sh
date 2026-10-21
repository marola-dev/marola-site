#!/usr/bin/env bash
# br-proxy-preflight — the flight check before site.yml's board build (#4): find a working node in
# the Brazilian proxy pool, the entries of MAROLA_BR_PROXY (ops/br-proxy/JOIN.md), each tried in
# order with a real request through it to an allowlisted agency. Prints the first healthy entry
# (http://user:pass@host:port) on stdout, for `MAROLA_BR_PROXY=... scripts/br-proxy.sh start`.
#
#   scripts/br-proxy-preflight.sh               find a node, or fail
#   scripts/br-proxy-preflight.sh --fail CAUSE  fail for CAUSE (site.yml's own causes)
#   scripts/br-proxy-preflight.sh --self-test
#
# MAROLA_BR_PROXY is one or more http://user:pass@host:port entries, separated by whitespace.
# Every message shows host:port only; under GitHub Actions every password is masked first.
#
# Fails closed: with no healthy node it exits 1 with an ::error:: naming the cause, and the build
# stops before any board is built, so nothing deploys and marola.dev keeps the last deployed site.
# BR_PROXY_REQUIRED=false (the repo variable, a break-glass switch) turns that into a warning and
# exit 0, and the build runs without the proxy (INEA and INEMA "no data").
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
curl="${CURL:-curl}"
per_node="${BR_PREFLIGHT_TIMEOUT:-10}"
budget="${BR_PREFLIGHT_BUDGET:-60}"
required="${BR_PROXY_REQUIRED:-true}"

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

# host:port of an entry, or nothing when it is not http://user:pass@host:port.
hostport() {
  [[ "$1" =~ ^http://[^:@/]+:[^@/]+@([^@/]+)$ ]] && echo "${BASH_REMATCH[1]}"
}

# Masks go to stderr: stdout carries the chosen entry.
mask() {
  local e rest
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  for e in "$@"; do
    rest="${e#http://}"
    echo "::add-mask::$e" >&2
    echo "::add-mask::${rest%@*}" >&2
    rest="${rest%@*}"
    echo "::add-mask::${rest#*:}" >&2
  done
}

preflight() {
  local entries=() e hp out code secs url n=0 tried=""
  read -ra entries <<<"$(tr -s '[:space:]' ' ' <<<"${MAROLA_BR_PROXY:-}")"
  if [ "${#entries[@]}" -eq 0 ]; then
    fail "MAROLA_BR_PROXY is not set: the pool has no node"
    return
  fi
  mask "${entries[@]}"
  url="$(target)"
  SECONDS=0
  for e in "${entries[@]}"; do
    n=$((n + 1))
    if ! hp="$(hostport "$e")"; then
      say "skipping entry #$n: not http://user:pass@host:port"
      tried+="entry #$n (malformed), "
      continue
    fi
    if [ "$SECONDS" -ge "$budget" ]; then
      say "out of time (${budget}s) before trying $hp"
      tried+="$hp (not tried), "
      continue
    fi
    out="$("$curl" -x "$e" -sS -m "$per_node" -o /dev/null \
      -w '%{http_code} %{time_total}' "$url" 2>/dev/null || true)"
    code="${out%% *}"
    secs="${out#* }"
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
      say "using $hp: $url answered HTTP $code in ${secs}s"
      echo "$e"
      return 0
    fi
    say "skipping $hp: $url gave HTTP ${code:-none}"
    tried+="$hp (HTTP ${code:-none}), "
  done
  fail "none of the ${#entries[@]} pool node(s) passed the request to $url through it: ${tried%, }"
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
  # The curl stub answers per node from $HEALTHY ("a.example:8888=200 b.example:8888=301") and logs each try.
  cat >"$t/curl" <<EOF
#!/usr/bin/env bash
hp="\${2#http://*@}"
echo "\$hp" >>"$t/tries"
for kv in \$HEALTHY; do [ "\${kv%%=*}" = "\$hp" ] && { printf '%s 0.25' "\${kv#*=}"; exit 0; }; done
printf '000 10.0'; exit 28
EOF
  chmod +x "$t/curl"
  local A="http://u1:pwAAAAAAAAAAAAAA1@a.example:8888" B="http://u2:pwBBBBBBBBBBBBBB2@b.example:9000"
  run() { rm -f "$t/tries"; HEALTHY="$1" curl="$t/curl" preflight 2>"$t/err"; }
  rc() { "$@" >/dev/null && echo 0 || echo "$?"; }

  check "it probes the first allowlisted agency over HTTPS" "$(target)" "https://www.inea.rj.gov.br/"
  check "host:port of an entry" "$(hostport "$A")" "a.example:8888"
  check "a malformed entry has none" "$(hostport "http://a.example:8888" || true)" ""
  got="$(MAROLA_BR_PROXY="$A $B" run "a.example:8888=200 b.example:9000=200")"
  check "first node healthy: it is the upstream" "$got" "$A"
  check "and the second is never tried" "$(tr '\n' ' ' <"$t/tries")" "a.example:8888 "
  check "first dead, second healthy (a redirect), newline-separated: the second" \
    "$(MAROLA_BR_PROXY="$A"$'\n'"$B" run "b.example:9000=301")" "$B"
  check "a node refusing (403, 407) is not healthy: exit 1" "$(MAROLA_BR_PROXY="$A $B" rc run "a.example:8888=403 b.example:9000=407")" 1
  check "all dead: exit 1" "$(MAROLA_BR_PROXY="$A $B" rc run "")" 1
  check "the ::error:: names each node by host:port" \
    "$(grep -c '^::error::.*none of the 2.*a\.example:8888 (HTTP 000).*b\.example:9000 (HTTP 000).*no deploy.*BR_PROXY_REQUIRED=false' "$t/err")" 1
  # The ::add-mask:: lines carry the passwords by design (under Actions, CI's own run included).
  check "and no password appears in the output outside the masks" \
    "$(grep -v '^::add-mask::' "$t/err" | grep -c 'pwAAAA\|pwBBBB' || true)" 0
  check "unset: exit 1, saying so" "$(MAROLA_BR_PROXY='' rc run "" ; grep -c 'MAROLA_BR_PROXY is not set' "$t/err")" "1
1"
  check "blank is unset too" "$(MAROLA_BR_PROXY=$' \n ' rc run "")" 1
  check "a malformed entry is skipped, the next used" "$(MAROLA_BR_PROXY="http://nope $B" run "b.example:9000=200")" "$B"
  GITHUB_ACTIONS=true MAROLA_BR_PROXY="$A $B" run "" || true
  check "under Actions every password and entry is masked first" \
    "$(grep -c '^::add-mask::\(pwAAAAAAAAAAAAAA1\|pwBBBBBBBBBBBBBB2\|http://u1:pwAAAAAAAAAAAAAA1@a.example:8888\|http://u2:pwBBBBBBBBBBBBBB2@b.example:9000\)$' "$t/err")" 4
  check "and the first line is a mask" "$(head -n 1 "$t/err" | cut -c1-12)" "::add-mask::"
  check "out of time: no further node is tried, exit 1" "$(budget=0 MAROLA_BR_PROXY=$A rc run "a.example:8888=200")" 1
  check "BR_PROXY_REQUIRED=false and no healthy node: exit 0, nothing printed" \
    "$(required=false MAROLA_BR_PROXY=$A run "" && echo exit0)" "exit0"
  check "with a ::warning::, not an ::error::" "$(grep -c '^::warning::.*BR_PROXY_REQUIRED=false' "$t/err")/$(grep -c '^::error::' "$t/err" || true)" "1/0"
  check "BR_PROXY_REQUIRED=false and unset: exit 0" "$(required=false MAROLA_BR_PROXY='' rc run "")" 0
  check "any other value is still required" "$(required=no MAROLA_BR_PROXY='' rc run "")" 1
  check "--fail CAUSE fails with that cause" "$(rc fail "could not install tinyproxy" 2>"$t/err"; grep -c 'could not install tinyproxy' "$t/err")" "1
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
