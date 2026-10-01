#!/usr/bin/env bash
# mip-trailer-check — a commit touching site/static/** carries `MIP: MIP-NNNN` or
# `MIP: none — <reason>` (the rule marola's pre-push hook enforced; MIP-0070 §5.6 keeps it here).
#
#   scripts/mip-trailer-check.sh [<rev-list args>]   check those commits
#   scripts/mip-trailer-check.sh < pre-push-lines    check what a push sends
#   scripts/mip-trailer-check.sh --self-test
#
# With no arguments it reads git's pre-push lines ("<local ref> <local sha> <remote ref> <remote
# sha>") from stdin when stdin is not a terminal; `just prepush` passes them on once the devkit hook
# does. With none, it checks origin/main..HEAD, or every commit of HEAD on no remote when there is
# no origin/main. A merge is checked against its first parent, as marola's hook did.
set -euo pipefail

zero=0000000000000000000000000000000000000000

# Prints the rev-list arguments (one per line) for each pushed ref read from stdin.
pushed_ranges() {
  local _lref lsha _rref rsha
  while read -r _lref lsha _rref rsha; do
    [ -n "${lsha:-}" ] && [ "$lsha" != "$zero" ] || continue
    if [ "${rsha:-$zero}" = "$zero" ] || ! git cat-file -e "$rsha^{commit}" 2>/dev/null; then
      printf '%s\n' "$lsha --not --remotes"
    else
      printf '%s\n' "$rsha..$lsha"
    fi
  done
}

check() {
  local ranges=() sha bad=() r
  if [ "$#" -gt 0 ]; then
    ranges=("$*")
  else
    local lines=()
    [ -t 0 ] || mapfile -t lines
    # A push of deletions only sends lines but nothing to check: no fallback then.
    [ "${#lines[@]}" -eq 0 ] || mapfile -t ranges < <(printf '%s\n' "${lines[@]}" | pushed_ranges)
    if [ "${#lines[@]}" -eq 0 ]; then
      if git rev-parse -q --verify origin/main >/dev/null; then ranges=(origin/main..HEAD)
      else ranges=("HEAD --not --remotes"); fi
    fi
  fi
  for r in "${ranges[@]}"; do
    # shellcheck disable=SC2086  # each entry is a list of rev-list arguments
    while read -r sha; do
      [ -n "$sha" ] || continue
      git diff-tree -m --first-parent --no-commit-id --name-only -r --root "$sha" | grep -q '^site/static/' || continue
      git log -1 --format=%B "$sha" | grep -qE '^MIP: (MIP-[0-9]{4}|none — .+)$' || bad+=("$sha")
    done < <(git rev-list $r)
  done
  [ "${#bad[@]}" -gt 0 ] || return 0
  echo "mip-trailer-check: commit(s) touching site/static/** with no 'MIP:' trailer:" >&2
  for sha in $(printf '%s\n' "${bad[@]}" | sort -u); do echo "  $(git log -1 --format='%h %s' "$sha")" >&2; done
  echo "Add 'MIP: MIP-NNNN' (the design it is for) or 'MIP: none — <reason>' (a fix, typo or" >&2
  echo "refactor with no behaviour change; the mip skill's 'Not for' list) to each commit's trailers." >&2
  return 1
}

self_test() {
  local t f=0 base page
  t="$(mktemp -d)"
  trap 'rm -rf "$t"' RETURN
  git init -q -b main "$t/r"
  g() { git -C "$t/r" -c user.name=t -c user.email=t@t "$@"; }
  c() { (cd "$t/r" && check "$@") >/dev/null 2>&1; }
  mkdir -p "$t/r/site/static" "$t/r/scripts"
  echo a >"$t/r/README.md"; g add -A; g commit -qm root
  base="$(g rev-parse HEAD)"
  echo b >"$t/r/scripts/x.sh"; g add -A; g commit -qm "not the page"
  echo c >"$t/r/site/static/app.js"; g add -A; g commit -qm "page" -m "MIP: MIP-0009"
  echo d >>"$t/r/site/static/app.js"; g add -A; g commit -qm "page fix" -m "MIP: none — a typo"
  c "$base..HEAD" </dev/null || { echo "FAIL: trailered page commits were blocked"; f=1; }
  echo e >>"$t/r/site/static/app.js"; g add -A; g commit -qm "page, no trailer" -m "MIP: maybe"
  page="$(g rev-parse HEAD)"
  c "$base..HEAD" </dev/null && { echo "FAIL: a page commit with no valid trailer passed"; f=1; }
  c </dev/null && { echo "FAIL: with no origin/main, HEAD's unpushed commits went unchecked"; f=1; }
  echo "refs/heads/main $page refs/heads/main $zero" | c && { echo "FAIL: a new branch's pushed commits went unchecked"; f=1; }
  echo "refs/heads/main $page refs/heads/main $page~1" | c && { echo "FAIL: the pushed range missed its untrailered commit"; f=1; }
  echo "refs/heads/main $page~1 refs/heads/main $base" | c || { echo "FAIL: a pushed range with only trailered commits was blocked"; f=1; }
  echo "refs/heads/gone $zero refs/heads/gone $page" | c || { echo "FAIL: a branch deletion was checked"; f=1; }
  g update-ref refs/remotes/origin/main HEAD
  echo g >"$t/r/scripts/y.sh"; g add -A; g commit -qm "past origin/main, no page"
  c </dev/null || { echo "FAIL: the default range reached below origin/main"; f=1; }
  g checkout -q -b side
  echo h >>"$t/r/site/static/app.js"; g add -A; g commit -qm "side page" -m "MIP: MIP-0009"
  g checkout -q main
  g merge -q --no-ff -m "merge side" side
  c HEAD~1..HEAD </dev/null && { echo "FAIL: a merge bringing in site/static with no trailer passed"; f=1; }
  echo "mip-trailer-check self-test:" "$([ "$f" -eq 0 ] && echo ok || echo FAILED)"
  [ "$f" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) check "$@" ;;
esac
