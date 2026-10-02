#!/usr/bin/env bash
# board-schema — the board contract comes from the pinned app image, never from an app checkout
# (MIP-0070 §5.4). marola-image holds the one pinned reference; site/board.schema.json is its schema.
#
#   scripts/board-schema.sh --image            print the pinned image reference
#   scripts/board-schema.sh --extract <file>   write the pinned image's board.schema.json to <file>
#   scripts/board-schema.sh --check            fail when site/board.schema.json differs from it
#   scripts/board-schema.sh --update           rewrite site/board.schema.json from it (after a bump)
#   scripts/board-schema.sh --self-test
#
# Needs docker (podman as `docker` works) and python3.
set -euo pipefail

root="${BOARD_SCHEMA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

image() {
  local ref
  ref="$(tr -d '[:space:]' <"$root/marola-image")"
  # Only the jvm image has /app/marola.jar to read the schema from; the native one compiles it in.
  [[ "$ref" =~ ^ghcr\.io/[a-z0-9-]+/marola-app:jvm-[0-9a-f]{7,40}@sha256:[0-9a-f]{64}$ ]] \
    || { echo "board-schema: marola-image must be ghcr.io/<owner>/marola-app:jvm-<sha>@sha256:<digest>, got '$ref'" >&2; return 1; }
  echo "$ref"
}

extract() {
  local dest=$1 ref tmp cid
  ref="$(image)"
  tmp="$(mktemp -d)"
  cid="$(docker create "$ref")"
  if ! docker cp "$cid:/app/marola.jar" "$tmp/marola.jar" >/dev/null; then
    docker rm "$cid" >/dev/null; rm -rf "$tmp"; return 1
  fi
  docker rm "$cid" >/dev/null
  python3 -c 'import sys, zipfile; open(sys.argv[2], "wb").write(zipfile.ZipFile(sys.argv[1]).read("board.schema.json"))' \
    "$tmp/marola.jar" "$dest"
  rm -rf "$tmp"
}

check() {
  local got
  got="$(mktemp)"
  extract "$got"
  if cmp -s "$got" "$root/site/board.schema.json"; then
    rm -f "$got"; echo "board-schema: site/board.schema.json matches $(image)"
  else
    diff -u "$root/site/board.schema.json" "$got" >&2 || true
    rm -f "$got"
    echo "board-schema: site/board.schema.json differs from $(image)'s; run scripts/board-schema.sh --update" >&2
    return 1
  fi
}

self_test() {
  local t f=0
  t="$(mktemp -d)"
  trap 'rm -rf "$t"' RETURN
  mkdir -p "$t/repo/site" "$t/bin"
  echo '{"v":2}' >"$t/schema.json"
  python3 -c 'import sys, zipfile; z = zipfile.ZipFile(sys.argv[1], "w"); z.write(sys.argv[2], "board.schema.json"); z.close()' \
    "$t/marola.jar" "$t/schema.json"
  # A docker that only knows create/cp/rm, serving the jar built above.
  cat >"$t/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
  create) echo "\$2" >>"$t/created"; echo cid ;;
  cp) cp "$t/marola.jar" "\$3" ;;
  rm) : ;;
esac
EOF
  chmod +x "$t/bin/docker"
  run() { BOARD_SCHEMA_ROOT="$t/repo" PATH="$t/bin:$PATH" bash "${BASH_SOURCE[0]}" "$@"; }
  local pin=ghcr.io/marola-dev/marola-app:jvm-8a29976@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  echo "$pin" >"$t/repo/marola-image"

  [ "$(run --image)" = "$pin" ] || { echo "FAIL: --image prints the pin"; f=1; }
  echo '{"v":1}' >"$t/repo/site/board.schema.json"
  run --check >/dev/null 2>&1 && { echo "FAIL: --check passed a stale vendored schema"; f=1; }
  run --update >/dev/null || { echo "FAIL: --update"; f=1; }
  cmp -s "$t/repo/site/board.schema.json" "$t/schema.json" || { echo "FAIL: --update did not write the image's schema"; f=1; }
  run --check >/dev/null || { echo "FAIL: --check failed right after --update"; f=1; }
  [ "$(sort -u "$t/created")" = "$pin" ] || { echo "FAIL: docker create was not given the pinned image"; f=1; }
  echo "ghcr.io/marola-dev/marola-app:native-8a29976" >"$t/repo/marola-image"
  run --image >/dev/null 2>&1 && { echo "FAIL: a native image was accepted as the pin"; f=1; }
  echo "ghcr.io/marola-dev/marola-app:jvm-8a29976" >"$t/repo/marola-image"
  run --image >/dev/null 2>&1 && { echo "FAIL: a tag with no digest was accepted as the pin"; f=1; }
  echo "ghcr.io/marola-dev/marola-app:jvm" >"$t/repo/marola-image"
  run --image >/dev/null 2>&1 && { echo "FAIL: a moving tag was accepted as the pin"; f=1; }
  echo "ghcr.io/marola-dev/marola:jvm-8a29976@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" >"$t/repo/marola-image"
  run --image >/dev/null 2>&1 && { echo "FAIL: the pre-split image name was accepted as the pin"; f=1; }
  echo "board-schema self-test:" "$([ "$f" -eq 0 ] && echo ok || echo FAILED)"
  [ "$f" -eq 0 ]
}

case "${1:-}" in
  --image) image ;;
  --extract) extract "${2:?usage: $0 --extract <file>}" ;;
  --check) check ;;
  --update) extract "$root/site/board.schema.json" && echo "board-schema: site/board.schema.json from $(image)" ;;
  --self-test) self_test ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
