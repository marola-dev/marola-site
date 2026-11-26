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
const SEA = "#5bb8d8";
const flavor = {
  background: SEA,
  water: SEA,
  earth: "#f7efd8",
  beach: "#f4c65a",
  sand: "#f2d88f",
  park_a: "#c7e6a2",
  park_b: "#9fd17e",
  wood_a: "#bfe2a0",
  wood_b: "#84c47a",
  scrub_a: "#d7e9b4",
  scrub_b: "#b2d792",
  glacier: "#ffffff",
  hospital: "#f5e7dc",
  industrial: "#efe6da",
  school: "#f7ecd0",
  zoo: "#cfe8b0",
  military: "#e9e2d2",
  aerodrome: "#ece9e1",
  runway: "#dedbd4",
  pedestrian: "#f7eeda",
  pier: "#e9dfc9",
  buildings: "#e8deca",
  other: "#f0e8d5",
  minor_service: "#fffdf7",
  minor_a: "#fffdf7",
  minor_b: "#fffdf7",
  link: "#fffdf7",
  major: "#fffdf7",
  highway: "#f9d56f",
  minor_service_casing: "#d8cfb8",
  minor_casing: "#d8cfb8",
  link_casing: "#d2c8b2",
  major_casing_early: "#d2c8b2",
  major_casing_late: "#d2c8b2",
  highway_casing_early: "#d9b85c",
  highway_casing_late: "#d9b85c",
  railway: "#b0b6bd",
  boundaries: "#4f7088",
  bridges_other: "#f0e8d5",
  bridges_minor: "#fffdf7",
  bridges_link: "#fffdf7",
  bridges_major: "#fffdf7",
  bridges_highway: "#f9d56f",
  bridges_other_casing: "#d2c8b2",
  bridges_minor_casing: "#d2c8b2",
  bridges_link_casing: "#d2c8b2",
  bridges_major_casing: "#d2c8b2",
  bridges_highway_casing: "#d9b85c",
  roads_label_minor: "#46535f",
  roads_label_minor_halo: "#ffffff",
  roads_label_major: "#3f4c59",
  roads_label_major_halo: "#ffffff",
  ocean_label: "#0a4d66",
  subplace_label: "#3f5668",
  subplace_label_halo: "#f7efd8",
  city_label: "#0f2433",
  city_label_halo: "#f7efd8",
  state_label: "#5f7182",
  state_label_halo: "#f7efd8",
  country_label: "#3f5668",
  address_label: "#46535f",
  address_label_halo: "#ffffff",
  landcover: {
    grassland: "#d7e9b0",
    barren: "#f3e6c6",
    urban_area: "#efe6d6",
    farmland: "#e4edbf",
    glacier: "#ffffff",
    scrub: "#cfe4a6",
    forest: "#b7d99a",
  },
};
const BEACH_LABEL = "#7a4a00";

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
