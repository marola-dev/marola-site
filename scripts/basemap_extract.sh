#!/usr/bin/env bash
# basemap_extract — cuts the one PMTiles file the map reads (docs/adr/0006-self-hosted-basemap.md) from the
# Protomaps daily build pinned in site/basemap.version. The file is a sparse pyramid: the whole world at
# low zoom, Brazil a little deeper, and street level only around each area of site/areas.json. Where a
# deep tile is missing the page draws its nearest ancestor, so the map never ends in a void.
#
#   scripts/basemap_extract.sh <out.pmtiles>            the host's file (about 250 MB; reads only the ranges it needs)
#   scripts/basemap_extract.sh --fixture <out.pmtiles>  the small file of site/fixtures/ (tests, offline preview)
#   scripts/basemap_extract.sh --dry-run [--fixture]    print the plan and stop: no network, nothing written
#   scripts/basemap_extract.sh --self-test
#
# Needs node, curl, and the pmtiles CLI and tippecanoe's tile-join (`nix shell nixpkgs#pmtiles
# nixpkgs#tippecanoe`). The pieces stay in .tmp/basemap/ and are reused by the next run of the same pin.
set -euo pipefail

root="${BASEMAP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
builds_index="https://build-metadata.protomaps.dev/builds.json"
builds_host="https://build.protomaps.com"

# The pyramid. Zoom ranges never overlap, so tile-join only copies tiles and merges none.
world_maxzoom=6
country_bbox="-74.5,-34.5,-28,6" # Brazil, with its islands out to Trindade
country_maxzoom=9
area_maxzoom=15
area_margin_km=50 # beyond the area's own radius_km

say() { echo "basemap_extract: $*" >&2; }
die() { say "$*"; exit 1; }

pin() {
  local key sum
  key="$(sed -n '1p' "$root/site/basemap.version" | tr -d '[:space:]')"
  sum="$(sed -n '2p' "$root/site/basemap.version" | tr -d '\r')"
  [[ "$key" =~ ^[0-9]{8}\.pmtiles$ ]] || die "site/basemap.version line 1 must be <yyyymmdd>.pmtiles, got '$key'"
  [[ "$sum" =~ ^b3sum\ [0-9a-f]{64}$ ]] || die "site/basemap.version line 2 must be 'b3sum <64 hex digits>'"
  echo "$key ${sum#b3sum }"
}

# One line per piece: <name> <minzoom> <maxzoom> <bbox or ->.
plan() {
  local mode=$1
  node -e '
    const [file, mode, worldMax, countryBbox, countryMax, areaMax, margin] = process.argv.slice(1);
    const areas = JSON.parse(require("fs").readFileSync(file, "utf8"));
    const box = (a, km) => {
      const dLat = km / 111.32, dLon = km / (111.32 * Math.cos((a.lat * Math.PI) / 180));
      return [a.lon - dLon, a.lat - dLat, a.lon + dLon, a.lat + dLat].map((v) => v.toFixed(4)).join(",");
    };
    const out = [];
    if (mode === "fixture") {
      out.push(["world", 0, 1, "-"], [areas[0].id, 2, 11, box(areas[0], 3)]);
    } else {
      out.push(["world", 0, worldMax, "-"], ["country", +worldMax + 1, countryMax, countryBbox]);
      for (const a of areas) out.push([a.id, +countryMax + 1, areaMax, box(a, a.radius_km + +margin)]);
    }
    for (const row of out) {
      if (!/^[a-z0-9-]+$/.test(row[0])) { console.error("bad area id: " + row[0]); process.exit(1); }
      console.log(row.join(" "));
    }
  ' "$root/site/areas.json" "$mode" "$world_maxzoom" "$country_bbox" "$country_maxzoom" "$area_maxzoom" "$area_margin_km"
}

# The pinned build must still be listed, with the checksum the pin recorded. The 139 GB build itself is
# never downloaded, so its bytes are not hashed here: this catches a wrong key and a replaced build.
check_pin() {
  local key=$1 sum=$2
  curl -fsS "$builds_index" | node -e '
    const [key, sum] = process.argv.slice(1);
    const build = JSON.parse(require("fs").readFileSync(0, "utf8")).find((b) => b.key === key);
    if (!build) { console.error("basemap_extract: " + key + " is no longer listed; move site/basemap.version to a newer build"); process.exit(1); }
    if (build.b3sum !== sum) { console.error("basemap_extract: " + key + " is listed with b3sum " + build.b3sum + ", not the pinned one"); process.exit(1); }
    console.error("basemap_extract: " + key + " (basemap " + build.version + ", " + build.size + " bytes) is listed with the pinned b3sum");
  ' "$key" "$sum"
}

extract() {
  local mode=$1 out=$2 dry=$3 key sum work rows name minzoom maxzoom bbox piece
  key="$(pin)"
  sum="${key#* }"
  key="${key%% *}"
  rows="$(plan "$mode")"
  work="$root/.tmp/basemap/${key%.pmtiles}-$mode"
  local pieces=()
  if [ "$dry" -eq 0 ]; then
    for tool in node curl pmtiles tile-join; do
      command -v "$tool" >/dev/null || die "$tool is not installed (nix shell nixpkgs#pmtiles nixpkgs#tippecanoe)"
    done
    [ -n "$out" ] || die "name the file to write"
    check_pin "$key" "$sum"
    mkdir -p "$work"
  fi
  while read -r name minzoom maxzoom bbox; do
    piece="$work/$name.pmtiles"
    pieces+=("$piece")
    local args=("$builds_host/$key" "$piece" "--minzoom=$minzoom" "--maxzoom=$maxzoom")
    [ "$bbox" = "-" ] || args+=("--bbox=$bbox")
    if [ "$dry" -eq 1 ]; then
      echo "pmtiles extract ${args[*]#"$root/"}"
    elif [ -s "$piece" ] && pmtiles verify "$piece" >/dev/null 2>&1; then
      say "$name: reusing ${piece#"$root/"}"
    else
      say "$name: z$minzoom to z$maxzoom${bbox:+ in $bbox}"
      rm -f "$piece"
      pmtiles extract "${args[@]}" >&2
    fi
  done <<<"$rows"
  if [ "$dry" -eq 1 ]; then
    echo "tile-join --force --no-tile-size-limit -o <out> ${pieces[*]#"$root/"}"
    return 0
  fi
  # -pk is --no-tile-size-limit: a dropped tile would be a hole in the map.
  tile-join --force --quiet --no-tile-size-limit \
    --name="marola basemap" --attribution='<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap</a>' \
    -o "$out" "${pieces[@]}" >&2
  pmtiles verify "$out" >&2
  say "$(wc -c <"$out") bytes, sha256 $(sha256sum "$out" | cut -d' ' -f1), from $key"
  echo "$out"
}

self_test() {
  local t f=0 got
  t="$(mktemp -d)"
  mkdir -p "$t/site"
  cat >"$t/site/areas.json" <<'EOF'
[{"id": "equator", "lat": 0, "lon": 10, "radius_km": 61.32},
 {"id": "south", "lat": -60, "lon": -40, "radius_km": 5.66}]
EOF
  printf '20260102.pmtiles\nb3sum %064d\n' 0 >"$t/site/basemap.version"
  run() { BASEMAP_ROOT="$t" bash "${BASH_SOURCE[0]}" "$@"; }

  got="$(run --dry-run)" || { echo "FAIL: --dry-run"; f=1; }
  # 61.32 + 50 km is one degree on the equator; at 60 degrees south a degree of longitude is half as long.
  for want in \
    "pmtiles extract $builds_host/20260102.pmtiles .tmp/basemap/20260102-host/world.pmtiles --minzoom=0 --maxzoom=6" \
    "--minzoom=7 --maxzoom=9 --bbox=$country_bbox" \
    "equator.pmtiles --minzoom=10 --maxzoom=15 --bbox=9.0000,-1.0000,11.0000,1.0000" \
    "south.pmtiles --minzoom=10 --maxzoom=15 --bbox=-41.0000,-60.5000,-39.0000,-59.5000" \
    "tile-join --force --no-tile-size-limit -o <out> .tmp/basemap/20260102-host/world.pmtiles"; do
    case "$got" in *"$want"*) ;; *) echo "FAIL: the plan lacks: $want"; f=1 ;; esac
  done
  got="$(run --dry-run --fixture)" || { echo "FAIL: --dry-run --fixture"; f=1; }
  [ "$(echo "$got" | grep -c '^pmtiles extract')" -eq 2 ] || { echo "FAIL: the fixture is not two pieces"; f=1; }
  case "$got" in *"equator.pmtiles --minzoom=2 --maxzoom=11 --bbox=9.973"*) ;; *) echo "FAIL: the fixture's area piece"; f=1 ;; esac
  [ ! -e "$t/.tmp" ] || { echo "FAIL: --dry-run wrote something"; f=1; }

  echo "latest.pmtiles" >"$t/site/basemap.version"
  run --dry-run >/dev/null 2>&1 && { echo "FAIL: a moving key was accepted as the pin"; f=1; }
  printf '20260102.pmtiles\nb3sum abc\n' >"$t/site/basemap.version"
  run --dry-run >/dev/null 2>&1 && { echo "FAIL: a short checksum was accepted"; f=1; }
  printf '20260102.pmtiles\nb3sum %064d\n' 0 >"$t/site/basemap.version"
  echo '[{"id": "../x", "lat": 0, "lon": 0, "radius_km": 1}]' >"$t/site/areas.json"
  run --dry-run >/dev/null 2>&1 && { echo "FAIL: an area id that is not a plain name was accepted"; f=1; }

  rm -f "$t/site/areas.json" "$t/site/basemap.version"
  rmdir "$t/site" "$t"
  echo "basemap_extract self-test:" "$([ "$f" -eq 0 ] && echo ok || echo FAILED)"
  [ "$f" -eq 0 ]
}

mode=host
dry=0
out=""
for arg in "$@"; do
  case "$arg" in
    --self-test) self_test; exit ;;
    --fixture) mode=fixture ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 0 ;;
    -*) say "unknown flag: $arg"; exit 2 ;;
    *) out="$arg" ;;
  esac
done
if [ "$dry" -eq 0 ] && [ -z "$out" ]; then
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
extract "$mode" "$out" "$dry"
