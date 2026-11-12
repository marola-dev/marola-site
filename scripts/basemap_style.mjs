// Writes front/public/map/style.json, the base map's style, and front/public/map/fonts/, its glyphs.
// The layers are @protomaps/basemaps' own for its light flavor, recoloured toward marola and cut
// down: no sprite (so no POI icon, road shield or town dot), labels in Portuguese, and one layer of
// our own for beach names. docs/adr/0006-self-hosted-basemap.md has the reasons.
//
//   node scripts/basemap_style.mjs           write the style and the glyphs
//   node scripts/basemap_style.mjs --check   fail when the committed style differs
//
// The package and the glyph repository are not dependencies of the page (front/package-lock.json
// stays as it is): the first run fetches both into .tmp/basemap-tools/, pinned below.
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const BASEMAPS = "5.7.2";
const ASSETS = "https://github.com/protomaps/basemaps-assets";
const ASSETS_COMMIT = "028c18f713baecad011301ff7a69acc39bcc2ae7";
const TILES = "pmtiles:///tiles/marola.pmtiles";

// The page's file names are plain (Marola.Server.Files refuses a space), so each stack is renamed.
const STACKS = {
  "Noto Sans Regular": "noto-sans-regular",
  "Noto Sans Medium": "noto-sans-medium",
  "Noto Sans Italic": "noto-sans-italic",
};
// Latin, Latin-1 and Latin Extended, their modifiers and combining marks, and general punctuation.
// A name in any other script is not drawn (see `label`), so no other range is ever requested.
const RANGES = ["0-255", "256-511", "512-767", "768-1023", "7680-7935", "8192-8447"];

// DESIGN.md, "The base map", lists these. Water is --map-sea, so the page's ground and the map's sea
// are one colour and a missing tile reads as open water.
const SEA = "#cfe6f1";
const flavor = {
  background: SEA,
  water: SEA,
  earth: "#f4f2ec",
  beach: "#f1dc98",
  sand: "#f1e4b4",
  park_a: "#dcead3",
  park_b: "#c9e2bd",
  wood_a: "#d9e8d2",
  wood_b: "#c3dfb9",
  scrub_a: "#e0ead4",
  scrub_b: "#cfe2c0",
  glacier: "#ffffff",
  hospital: "#f0ebe6",
  industrial: "#ebe9e6",
  school: "#f0ece2",
  zoo: "#dcead3",
  military: "#ebe9e6",
  aerodrome: "#e9e8ea",
  runway: "#dcdbe0",
  pedestrian: "#efece3",
  pier: "#e6e2d8",
  buildings: "#e4e0d8",
  other: "#ece8df",
  minor_service: "#ffffff",
  minor_a: "#ffffff",
  minor_b: "#ffffff",
  link: "#ffffff",
  major: "#ffffff",
  highway: "#fbe7b0",
  minor_service_casing: "#dcd7cc",
  minor_casing: "#dcd7cc",
  link_casing: "#d6d0c3",
  major_casing_early: "#d6d0c3",
  major_casing_late: "#d6d0c3",
  highway_casing_early: "#dfc98c",
  highway_casing_late: "#dfc98c",
  railway: "#b9bcc2",
  boundaries: "#9aa3ad",
  bridges_other: "#ece8df",
  bridges_minor: "#ffffff",
  bridges_link: "#ffffff",
  bridges_major: "#ffffff",
  bridges_highway: "#fbe7b0",
  bridges_other_casing: "#d6d0c3",
  bridges_minor_casing: "#d6d0c3",
  bridges_link_casing: "#d6d0c3",
  bridges_major_casing: "#d6d0c3",
  bridges_highway_casing: "#dfc98c",
  roads_label_minor: "#6b7480",
  roads_label_minor_halo: "#ffffff",
  roads_label_major: "#59626e",
  roads_label_major_halo: "#ffffff",
  ocean_label: "#4d7a9c",
  subplace_label: "#5b6672",
  subplace_label_halo: "#f4f2ec",
  city_label: "#1d2733",
  city_label_halo: "#f4f2ec",
  state_label: "#7d8792",
  state_label_halo: "#f4f2ec",
  country_label: "#59626e",
  address_label: "#6b7480",
  address_label_halo: "#ffffff",
  landcover: {
    grassland: "#e3edd6",
    barren: "#f1ecdc",
    urban_area: "#ebe9e6",
    farmland: "#e9eeda",
    glacier: "#ffffff",
    scrub: "#e0ead4",
    forest: "#d3e5ca",
  },
};
const BEACH_LABEL = "#7a5c12";

// Sprite icons, and an address label that only starts past the page's highest zoom.
const DROPPED = ["pois", "roads_shields", "roads_oneway", "address_label"];

// Portuguese, then the local name when it is in Latin script (the tiles mark every other script with
// `script`), then English. Upstream's expression also draws the local script under the translation,
// which would need a glyph set per script.
const label = ["coalesce", ["get", "name:pt"], ["case", ["has", "script"], ["get", "name:en"], ["get", "name"]], ["get", "name:en"]];

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const tools = join(root, ".tmp", "basemap-tools");
const out = join(root, "front", "public", "map");

function fetchTools() {
  mkdirSync(tools, { recursive: true });
  const pkg = join(tools, "node_modules", "@protomaps", "basemaps", "package.json");
  if (!existsSync(pkg) || JSON.parse(readFileSync(pkg, "utf8")).version !== BASEMAPS) {
    execFileSync("npm", ["install", "--prefix", tools, "--no-audit", "--no-fund", "--no-save", `@protomaps/basemaps@${BASEMAPS}`], { stdio: ["ignore", 2, 2] });
  }
  const assets = join(tools, "basemaps-assets");
  if (!existsSync(join(assets, ".git"))) {
    execFileSync("git", ["clone", "--quiet", ASSETS, assets], { stdio: ["ignore", 2, 2] });
  }
  const git = (...args) => execFileSync("git", ["-C", assets, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", 2] }).trim();
  if (git("rev-parse", "HEAD") !== ASSETS_COMMIT) {
    git("fetch", "--quiet", "origin", ASSETS_COMMIT);
    git("checkout", "--quiet", "--detach", ASSETS_COMMIT);
  }
  return assets;
}

const renameStacks = (value) => {
  if (Array.isArray(value)) return value.map(renameStacks);
  if (typeof value !== "string" || !(value in STACKS)) return value;
  return STACKS[value];
};

function tune(layer) {
  const l = { ...layer, source: "basemap" };
  if (l.layout) {
    l.layout = { ...l.layout };
    for (const key of Object.keys(l.layout)) if (key.startsWith("icon-")) delete l.layout[key];
    if ("text-field" in l.layout) l.layout["text-field"] = label;
    if ("text-font" in l.layout) l.layout["text-font"] = renameStacks(l.layout["text-font"]);
  }
  // Upstream sizes its town labels to sit beside a dot the sprite drew.
  if (l.id === "places_locality" && l.layout) {
    delete l.layout["text-radial-offset"];
    delete l.layout["text-variable-anchor"];
    l.layout["text-anchor"] = "center";
  }
  return l;
}

const beachLabel = {
  id: "pois_beach",
  type: "symbol",
  source: "basemap",
  "source-layer": "pois",
  minzoom: 12,
  filter: ["==", ["get", "kind"], "beach"],
  layout: {
    "text-field": label,
    "text-font": [STACKS["Noto Sans Italic"]],
    "text-size": ["interpolate", ["linear"], ["zoom"], 12, 11, 16, 13],
    "text-max-width": 8,
    "symbol-sort-key": ["get", "min_zoom"],
  },
  paint: { "text-color": BEACH_LABEL, "text-halo-color": "#ffffff", "text-halo-width": 1.2 },
};

function build() {
  const require = createRequire(join(tools, "noop.js"));
  const basemaps = require("@protomaps/basemaps");
  const upstream = basemaps.layers("basemap", { ...basemaps.namedFlavor("light"), ...flavor }, { lang: "pt" });
  const layers = upstream.filter((l) => !DROPPED.includes(l.id)).map(tune);
  // Beach names go under the place names, which win a collision.
  const at = layers.findIndex((l) => l.id === "places_subplace");
  layers.splice(at < 0 ? layers.length : at, 0, beachLabel);
  const style = {
    version: 8,
    name: "marola",
    metadata: { generator: `scripts/basemap_style.mjs, @protomaps/basemaps ${BASEMAPS}` },
    sources: { basemap: { type: "vector", url: TILES } },
    glyphs: "/map/fonts/{fontstack}/{range}.pbf",
    layers,
  };
  const text = JSON.stringify(style);
  for (const stack of Object.keys(STACKS)) {
    if (text.includes(stack)) throw new Error(`a layer still names "${stack}"`);
  }
  if (/Devanagari|icon-image|"sprite"/.test(text)) throw new Error("a layer still needs a sprite or a font this site does not ship");
  return text + "\n";
}

const check = process.argv.includes("--check");
const assets = fetchTools();
const text = build();
const file = join(out, "style.json");
if (check) {
  if (!existsSync(file) || readFileSync(file, "utf8") !== text) {
    console.error("basemap_style: front/public/map/style.json is stale; run node scripts/basemap_style.mjs");
    process.exit(1);
  }
  for (const [stack, dir] of Object.entries(STACKS)) {
    for (const range of RANGES) {
      const want = readFileSync(join(assets, "fonts", stack, `${range}.pbf`));
      const have = join(out, "fonts", dir, `${range}.pbf`);
      if (!existsSync(have) || !readFileSync(have).equals(want)) {
        console.error(`basemap_style: ${dir}/${range}.pbf differs from basemaps-assets@${ASSETS_COMMIT.slice(0, 7)}`);
        process.exit(1);
      }
    }
  }
  console.error("basemap_style: the style and the glyphs are current");
} else {
  mkdirSync(out, { recursive: true });
  writeFileSync(file, text);
  let bytes = 0;
  for (const [stack, dir] of Object.entries(STACKS)) {
    mkdirSync(join(out, "fonts", dir), { recursive: true });
    for (const range of RANGES) {
      const from = join(assets, "fonts", stack, `${range}.pbf`);
      copyFileSync(from, join(out, "fonts", dir, `${range}.pbf`));
      bytes += readFileSync(from).length;
    }
  }
  copyFileSync(join(assets, "fonts", "OFL.txt"), join(out, "fonts", "LICENSE.noto-sans"));
  console.error(`basemap_style: style.json ${text.length} bytes, ${JSON.parse(text).layers.length} layers; glyphs ${bytes} bytes in ${Object.keys(STACKS).length * RANGES.length} files`);
}
