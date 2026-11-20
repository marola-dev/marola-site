// Temporary, for one PR's screenshots. Starts the built server of each tree against its own dist
// (a fake GitHub for the login), publishes a study through the API, and captures the pages the PR
// touches with a headless Chrome: the map page (the playlist layer, the four languages), the
// submit form and a study page, before and after, desktop and phone.
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import puppeteer from "puppeteer";

const GH_PORT = 8222;
const GH_HOST = `http://127.0.0.1:${GH_PORT}`;
const SECRET = "fake-shot-secret";
const TREES = [
  { name: "before", tree: "/tmp/before-tree", port: 8123, host: "127.0.0.1" },
  { name: "after", tree: "/tmp/after-tree", port: 8124, host: "localhost" },
];
const SIZES = { desktop: [1280, 800], phone: [390, 844] };

const bin = (tree, exe) =>
  spawnSync("cabal", ["list-bin", exe], { cwd: tree, encoding: "utf8" }).stdout.trim();

const run = (cmd, args, opts = {}) => {
  const r = spawnSync(cmd, args, { encoding: "utf8", ...opts });
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")}: ${r.stderr || r.status}`);
  return r.stdout.trim();
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const tmp = mkdtempSync(join(tmpdir(), "marola-shot-"));
  const secretFile = join(tmp, "github-secret");
  writeFileSync(secretFile, SECRET + "\n");
  mkdirSync(join(tmp, "shots"), { recursive: true });

  // One fake GitHub for both servers.
  const gh = spawn(bin(TREES[0].tree, "marola-tools"), ["fake-github", SECRET, String(GH_PORT)], {
    stdio: "ignore",
  });

  const servers = [];
  for (const t of TREES) {
    t.base = `http://${t.host}:${t.port}`;
    t.tmp = mkdtempSync(join(tmpdir(), `marola-${t.name}-`));
    t.env = {
      ...process.env,
      MAROLA_PORT: String(t.port),
      MAROLA_STATIC: join(t.tree, "dist"),
      MAROLA_DATA: join(t.tree, "dist", "data"),
      MAROLA_DB: join(t.tmp, "marola.db"),
      MAROLA_STUDIES: join(t.tmp, "studies"),
      MAROLA_TILES: join(t.tree, "dist", "tiles"),
      MAROLA_DEV: "1",
      MAROLA_GITHUB_CLIENT_ID: "shot-client",
      MAROLA_GITHUB_CLIENT_SECRET_FILE: secretFile,
      MAROLA_GITHUB_BASE: GH_HOST,
      MAROLA_GITHUB_API_BASE: GH_HOST,
    };
    t.server = spawn(bin(t.tree, "marola-server"), [], { env: t.env, stdio: "ignore" });
    servers.push(t.server, gh);
  }

  // Both servers up?
  for (const t of TREES) {
    for (let i = 0; i < 100; i++) {
      try {
        const r = await fetch(`${t.base}/`);
        if (r.ok) break;
      } catch {}
      if (i === 99) throw new Error(`${t.name} server did not start`);
      await sleep(300);
    }
  }

  // One study per server, submitted through the API with a dev-account key.
  const pdf = `%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\nstartxref\n0\n%%EOF\n`;
  for (const t of TREES) {
    const key = run(bin(t.tree, "marola-server"), ["dev-account", "--login", "shot", "--age-days", "30"], { env: t.env });
    const form = new FormData();
    form.set("title", "Enterococcus at Leblon, 2026 (a screenshot study)");
    form.set("authors", "Ana Silva | 0000-0002-1825-0097");
    form.set("abstract", "Sampling of bathing water at six points, repeated weekly through the summer. ".repeat(4));
    form.set("area", "rio");
    form.set("topic", "data");
    form.set("repository", "https://github.com/marola-dev/marola");
    form.set("archive", "https://zenodo.org/records/23224155");
    form.set("rights", "true");
    form.set("ai_contribution", "none");
    form.set("pdf", new Blob([pdf], { type: "application/pdf" }), "study.pdf");
    const r = await fetch(`${t.base}/api/v1/studies`, { method: "POST", headers: { Authorization: `Bearer ${key}` }, body: form });
    const j = await r.json().catch(() => ({}));
    if (r.status !== 201) throw new Error(`${t.name} submit: ${r.status} ${JSON.stringify(j)}`);
    t.study = j.id;
    console.log(`${t.name}: study ${t.study}`);
  }

  const browser = await puppeteer.launch({ headless: true, args: ["--no-sandbox"] });

  // The languages a tree's map page offers.
  const langsOf = (t) => (t.name === "before" ? ["pt-BR", "en"] : ["pt-BR", "en", "ja", "zh-Hant"]);
  const prefixOf = (lang) => ({ "pt-BR": "", en: "/en", ja: "/ja", "zh-Hant": "/zh-Hant" })[lang];

  async function shoot(page, t, name) {
    for (const [size, [w, h]] of Object.entries(SIZES)) {
      await page.setViewport({ width: w, height: h });
      await page.screenshot({ path: join(tmp, "shots", `${t.name}_${name}_${size}.png`) });
    }
  }

  // A fresh page per target so no state leaks between them.
  async function open(url) {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 90000 });
    return page;
  }

  for (const t of TREES) {
    // The map page, each language, the playlist open.
    for (const lang of langsOf(t)) {
      const page = await open(`${t.base}/?area=floripa`);
      await page.waitForSelector("#playlist", { timeout: 60000 });
      if (lang !== "pt-BR") {
        await page.click(`#lang button[lang="${lang}"]`);
        await sleep(2500);
      }
      await page.waitForFunction(() => document.querySelectorAll("canvas").length > 0, { timeout: 60000 }).catch(() => null);
      await sleep(4000);
      await page.click("#playlist");
      await page.waitForFunction(() => !!document.querySelector("#player iframe"), { timeout: 60000 });
      await sleep(6000);
      await shoot(page, t, `map_${lang.replace("zh-Hant", "zh").replace("pt-BR", "pt")}_player`);
      await page.close();
    }

    // The submit form, behind the login the fake GitHub answers.
    const page = await open(`${t.base}/auth/github/login`);
    await page.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 60000 }).catch(() => null);
    await sleep(2000);
    for (const lang of langsOf(t)) {
      const p = await open(`${t.base}${prefixOf(lang)}/submit`);
      await p.waitForSelector("form.contact input[name=title]", { timeout: 60000 });
      await sleep(800);
      await shoot(p, t, `submit_${lang.replace("zh-Hant", "zh").replace("pt-BR", "pt")}`);
      await p.close();
    }
    await page.close();

    // The study page the API published.
    for (const lang of langsOf(t)) {
      const p = await open(`${t.base}${prefixOf(lang)}/studies/${t.study}`);
      await p.waitForSelector("h2.study-title", { timeout: 60000 });
      await sleep(800);
      await shoot(p, t, `study_${lang.replace("zh-Hant", "zh").replace("pt-BR", "pt")}`);
      await p.close();
    }
    console.log(`${t.name}: captured`);
  }

  await browser.close();
  for (const s of servers) s.kill("SIGTERM");
  console.log("shots done");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
