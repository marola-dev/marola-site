// Writes the JSON files app_build.sh cannot make with shell alone: the page reads
// data/areas.json as {"areas": [...]} while site/areas.json is a bare list, and with
// "boards" each area gets latest.json plus the fixture board it names (offline preview).
// Usage: node scripts/app_fixtures.mjs <areas|boards> <dist-dir>
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const [mode, dist] = process.argv.slice(2);
if (!["areas", "boards"].includes(mode) || !dist) {
  console.error("usage: app_fixtures.mjs <areas|boards> <dist-dir>");
  process.exit(2);
}
const readJson = (p) => JSON.parse(readFileSync(join(root, p), "utf8"));
const writeJson = (p, v) => {
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, JSON.stringify(v) + "\n");
};

const areas = readJson("site/areas.json");
if (mode === "areas") {
  writeJson(join(dist, "data/areas.json"), { areas });
} else {
  const board = readJson("site/fixtures/board.json");
  const file = `${board.day}.json`;
  for (const area of areas) {
    writeJson(join(dist, "data", area.id, "latest.json"), { days: [{ day: board.day, file }] });
    writeJson(join(dist, "data", area.id, file), board);
  }
}
