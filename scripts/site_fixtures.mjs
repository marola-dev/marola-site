// Writes the JSON files site_build.sh cannot make with shell alone: the page reads
// data/areas.json as {"areas": [...]} while site/areas.json is a bare list, and with
// "boards" each area gets latest.json plus the fixture board it names (offline preview).
// Usage: node scripts/site_fixtures.mjs <areas|boards> <dist-dir>
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const [mode, dist] = process.argv.slice(2);
if (!["areas", "boards"].includes(mode) || !dist) {
  console.error("usage: site_fixtures.mjs <areas|boards> <dist-dir>");
  process.exit(2);
}
const readJson = (p) => JSON.parse(readFileSync(join(root, p), "utf8"));
const writeJson = (p, v) => {
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, JSON.stringify(v) + "\n");
};

// Fixture beaches (not live data): the template board's two beaches moved to real places in each city, so
// the map centres on the city offline. Florianopolis keeps the template as it is. Point coordinates move
// with their beach.
const fixtureBeaches = {
  rio: [
    { name: "Praia de Copacabana", lat: -22.9711, lon: -43.1822 },
    { name: "Praia de Ipanema", lat: -22.9868, lon: -43.2058 },
  ],
  salvador: [
    { name: "Praia do Porto da Barra", lat: -13.0107, lon: -38.5326 },
    { name: "Praia de Itapuã", lat: -12.9547, lon: -38.364 },
  ],
};
const boardFor = (template, id) => {
  const places = fixtureBeaches[id];
  if (!places) return template;
  const board = structuredClone(template);
  board.beaches.forEach((beach, i) => {
    const { name, lat, lon } = places[i];
    Object.assign(beach, { name, lat, lon });
    for (const point of beach.water.points) Object.assign(point, { location: name, lat, lon });
  });
  return board;
};

const areas = readJson("site/areas.json");
if (mode === "areas") {
  writeJson(join(dist, "data/areas.json"), { areas });
} else {
  const template = readJson("site/fixtures/board.json");
  const file = `${template.day}.json`;
  for (const area of areas) {
    writeJson(join(dist, "data", area.id, "latest.json"), { days: [{ day: template.day, file }] });
    writeJson(join(dist, "data", area.id, file), boardFor(template, area.id));
  }
}
