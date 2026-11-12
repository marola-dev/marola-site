#!/usr/bin/env bash
# Renders the static pages with the Haskell renderer (back/pages) into a temporary folder and
# compares every file the F# renderer (app/Pages.Build) writes with the same file in a reference
# folder, byte for byte. Usage: scripts/pages_parity.sh <reference-dir>, e.g. app/dist.
# MAROLA_PAGES_BIN names a built binary; without it the script builds one with cabal.
# security.txt's Expires follows the build date, so the date is taken from the reference's own
# security.txt unless MAROLA_PAGES_TODAY is set.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ref="${1:?usage: scripts/pages_parity.sh <reference-dir>}"
[ -d "$ref" ] || { echo "pages_parity: $ref is not a folder" >&2; exit 2; }

# What app/Pages.Build writes: Site.all (every slug in both languages) and Meta.files.
expected=(
  news.html about.html contact.html members.html support.html privacy.html takedown.html contact-sent.html 404.html
  en/news.html en/about.html en/contact.html en/members.html en/support.html en/privacy.html en/takedown.html
  en/contact-sent.html en/404.html
  robots.txt sitemap.xml llms.txt humans.txt .well-known/security.txt
)

bin="${MAROLA_PAGES_BIN:-}"
if [ -z "$bin" ]; then
  (cd "$root" && cabal build -v0 exe:marola-pages) >&2
  bin="$(cd "$root" && cabal list-bin marola-pages)"
fi

if [ -z "${MAROLA_PAGES_TODAY:-}" ]; then
  expires="$(sed -n 's/^Expires: \([0-9-]\{10\}\)T.*/\1/p' "$ref/.well-known/security.txt")"
  [ -n "$expires" ] || { echo "pages_parity: no Expires line in $ref/.well-known/security.txt" >&2; exit 2; }
  MAROLA_PAGES_TODAY="$(date -u -d "$expires - 364 days" +%F)"
fi
export MAROLA_PAGES_TODAY

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
(cd "$root" && "$bin" site "$out") >&2

written="$(cd "$out" && find . -type f | sed 's|^\./||' | sort)"
wanted="$(printf '%s\n' "${expected[@]}" | sort)"
fail=0
if [ "$written" != "$wanted" ]; then
  echo "pages_parity: the Haskell renderer writes another set of files than the F# one:" >&2
  diff <(echo "$wanted") <(echo "$written") >&2 || true
  fail=1
fi

same=0
for f in "${expected[@]}"; do
  if [ ! -f "$ref/$f" ]; then
    echo "pages_parity: missing in the reference: $f" >&2
    fail=1
  elif [ ! -f "$out/$f" ]; then
    fail=1
  elif cmp -s "$ref/$f" "$out/$f"; then
    same=$((same + 1))
  else
    echo "pages_parity: differs: $f" >&2
    diff -u "$ref/$f" "$out/$f" | head -20 >&2 || true
    fail=1
  fi
done

echo "pages_parity: $same of ${#expected[@]} files identical (date $MAROLA_PAGES_TODAY)"
exit "$fail"
