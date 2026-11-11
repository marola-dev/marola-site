#!/usr/bin/env bash
# Checks that site/members/MEMBERS.md is the blob site/members.version pins on its second line
# ("blob <sha>", what `git hash-object` prints). The Nix build and `just pages-build` read the copy
# and refuse one that drifted; this check says so earlier, and needs neither git nor the network.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
file="$root/site/members/MEMBERS.md"
pin="$root/site/members.version"

want="$(sed -n '2s/^blob \([0-9a-f]\{40\}\)$/\1/p' "$pin")"
[ -n "$want" ] || { echo "members_vendor_check: $pin needs a second line 'blob <sha>'" >&2; exit 1; }
[ -f "$file" ] || { echo "members_vendor_check: $file is missing" >&2; exit 1; }

have="$({ printf 'blob %s\0' "$(wc -c <"$file")"; cat "$file"; } | sha1sum | cut -d' ' -f1)"
if [ "$have" != "$want" ]; then
  echo "members_vendor_check: $file is blob $have, the pin says $want" >&2
  exit 1
fi
echo "members_vendor_check: ok ($want)"
