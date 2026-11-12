// The checks of scripts/server_smoke.sh, against a running marola-server.
// Usage: node scripts/server_smoke.mjs <base-url> <inbox-command...>
// The inbox command is run (with the server's MAROLA_DB in its environment) to read what POST /contact stored.
import http from "node:http";
import { execFileSync } from "node:child_process";

const [base, ...inbox] = process.argv.slice(2);
const url = new URL(base);
let failures = 0;
const ok = (cond, label, detail = "") => {
  console.log(`  ${cond ? "ok  " : "FAIL"} ${label}${!cond && detail ? ": " + detail : ""}`);
  if (!cond) failures++;
};

// http.request, not fetch: fetch normalises "..", and we want to send the bytes a hostile client sends.
const request = (method, path, { headers = {}, body } = {}) =>
  new Promise((resolve, reject) => {
    const req = http.request(
      { host: url.hostname, port: url.port, method, path, headers: { Host: url.host, ...headers } },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
      },
    );
    req.on("error", reject);
    req.end(body);
  });

const expected = {
  "content-security-policy": (v) => v.includes("script-src 'self'") && v.includes("form-action 'self'"),
  "strict-transport-security": (v) => v === "max-age=63072000; includeSubDomains",
  "x-content-type-options": (v) => v === "nosniff",
  "referrer-policy": (v) => v === "strict-origin-when-cross-origin",
  "permissions-policy": (v) => v.startsWith("geolocation=(self)"),
  "cross-origin-opener-policy": (v) => v === "same-origin",
  "cross-origin-resource-policy": (v) => v === "same-origin",
};
const checkHeaders = (what, res) => {
  for (const [name, test] of Object.entries(expected)) ok(res.headers[name] !== undefined && test(res.headers[name]), `${what}: ${name}`, res.headers[name]);
  ok(res.headers["server"] === undefined && res.headers["x-powered-by"] === undefined, `${what}: no Server or X-Powered-By`);
};

const get = (path, headers) => request("GET", path, { headers });
const form = (pairs) => new URLSearchParams(pairs).toString();
const formHeaders = (body, extra = {}) => ({ "Content-Type": "application/x-www-form-urlencoded", "Content-Length": Buffer.byteLength(body), ...extra });

const page = await get("/");
ok(page.status === 200 && /text\/html/.test(page.headers["content-type"]), "GET / is the page", String(page.status));
ok(page.headers["cache-control"] === "no-cache", "the page is no-cache");
checkHeaders("/", page);

// The Elm bundle's name carries Vite's content hash: read it from the page.
const script = (/<script type="module"[^>]*src="\.(\/assets\/index-[\w-]+\.js)"/.exec(page.body.toString()) || [])[1] || "/assets/index.js";
const module_ = await get(script);
ok(module_.status === 200 && /text\/javascript/.test(module_.headers["content-type"]), `GET ${script} is JavaScript`, String(module_.status));
checkHeaders(script, module_);

const packed = await get(script, { "Accept-Encoding": "br, gzip" });
ok(packed.headers["content-encoding"] === "br", "JavaScript goes out compressed (br)", String(packed.headers["content-encoding"]));

const data = await get("/data/floripa/latest.json");
ok(data.status === 200 && /application\/json/.test(data.headers["content-type"]), "GET /data/floripa/latest.json is JSON", String(data.status));
ok(data.body.toString().includes("smoke"), "/data/ is read from MAROLA_DATA first");
checkHeaders("/data/floripa/latest.json", data);

// The base map: the mapStyle and a glyph range as plain files, and the one file that answers byte ranges.
const mapStyle = await get("/map/style.json", { "Accept-Encoding": "br" });
ok(mapStyle.status === 200 && /application\/json/.test(mapStyle.headers["content-type"]) && mapStyle.headers["content-encoding"] === "br", "GET /map/style.json is JSON, compressed", String(mapStyle.status));
const mapGlyphs = await get("/map/fonts/noto-sans-regular/0-255.pbf", { "Accept-Encoding": "br" });
ok(mapGlyphs.status === 200 && mapGlyphs.headers["content-type"] === "application/x-protobuf" && mapGlyphs.headers["content-encoding"] === "br", "a glyph range is protobuf, compressed", `${mapGlyphs.status} ${mapGlyphs.headers["content-type"]}`);
ok(mapGlyphs.headers["cache-control"] === "public, max-age=86400", "a glyph range is cached for a day");
const tilesPath = "/tiles/marola.pmtiles";
const tileHead = await get(tilesPath, { Range: "bytes=0-16383", "Accept-Encoding": "br, gzip" });
const tilesSize = Number((/\/(\d+)$/.exec(tileHead.headers["content-range"] ?? "") || [])[1]);
ok(tileHead.status === 206 && tileHead.body.length === 16384 && tileHead.headers["content-length"] === "16384", "a range of the tiles file is a 206 with exactly its bytes", `${tileHead.status} ${tileHead.body.length}`);
ok(tileHead.headers["content-range"] === `bytes 0-16383/${tilesSize}` && tilesSize > 16384 && tileHead.headers["accept-ranges"] === "bytes", "with Content-Range and Accept-Ranges", String(tileHead.headers["content-range"]));
ok(tileHead.body.subarray(0, 7).toString() === "PMTiles" && tileHead.body[7] === 3, "and they are the header of a PMTiles v3 archive");
ok(tileHead.headers["content-encoding"] === undefined && tileHead.headers["content-type"] === "application/octet-stream", "the tiles file is never compressed");
ok(/^public, max-age=\d+$/.test(tileHead.headers["cache-control"] ?? "") && /^"[0-9a-f]+-[0-9a-f]+"$/.test(tileHead.headers["etag"] ?? ""), "it is cached, under an ETag of size and mtime", `${tileHead.headers["cache-control"]} ${tileHead.headers["etag"]}`);
checkHeaders(tilesPath, tileHead);
const tileTail = await get(tilesPath, { Range: `bytes=${tilesSize - 10}-` });
ok(tileTail.status === 206 && tileTail.body.length === 10 && tileTail.headers["content-range"] === `bytes ${tilesSize - 10}-${tilesSize - 1}/${tilesSize}`, "an open range ends at the last byte", String(tileTail.headers["content-range"]));
const tileBeyond = await get(tilesPath, { Range: `bytes=${tilesSize}-` });
ok(tileBeyond.status === 416 && tileBeyond.headers["content-range"] === `bytes */${tilesSize}`, "a range past the end is a 416 that names the size", String(tileBeyond.status));
checkHeaders("416", tileBeyond);
const tileSame = await get(tilesPath, { "If-None-Match": tileHead.headers["etag"] });
ok(tileSame.status === 304 && tileSame.body.length === 0, "the same ETag gets a 304", String(tileSame.status));
const hostTiles = await get("/tiles/smoke.pmtiles", { Range: "bytes=0-4" });
ok(hostTiles.status === 206 && hostTiles.body.toString() === "smoke", "/tiles/ is read from MAROLA_TILES first", String(hostTiles.status));
for (const path of ["/tiles/../index.html", "/tiles/%2e%2e/index.html", "/tiles/..%2fmarola.db", "/tiles/smoke.pmtiles/", "/tiles/SMOKE.pmtiles", "/tiles/x/smoke.pmtiles", "/tiles/", "/tiles/nope.pmtiles"]) {
  const res = await get(path, { Range: "bytes=0-4" });
  ok(res.status === 404 && res.headers["accept-ranges"] === undefined, `GET ${path} is a 404`, String(res.status));
}
const pageRange = await get(script, { Range: "bytes=0-9" });
ok(pageRange.status === 200 && pageRange.headers["accept-ranges"] === undefined && pageRange.headers["content-range"] === undefined, "no other file answers a range", String(pageRange.status));
ok(!/openfreemap|mapbox|maptiler/i.test(page.headers["content-security-policy"]), "the CSP names no map host");

const missing = await get("/nope");
ok(missing.status === 404, "GET /nope is 404", String(missing.status));
ok(/text\/html/.test(missing.headers["content-type"]) && missing.body.toString().includes("<html lang=\"pt-BR\">"), "/nope is the pt-BR 404 page");
checkHeaders("/nope", missing);
const missingEn = await get("/en/nope");
ok(missingEn.status === 404 && missingEn.body.toString().includes("<html lang=\"en\">"), "/en/nope is the English 404 page", String(missingEn.status));

// The pages of back/pages, in both languages (run scripts/site_build.sh first).
for (const [path, lang] of [["/about.html", "pt-BR"], ["/en/about.html", "en"], ["/contact.html", "pt-BR"], ["/en/contact.html", "en"], ["/contact-sent.html", "pt-BR"], ["/en/support.html", "en"]]) {
  const page = await get(path);
  ok(page.status === 200 && /text\/html/.test(page.headers["content-type"]) && page.body.toString().includes(`<html lang="${lang}">`), `GET ${path} is the ${lang} page`, String(page.status));
  checkHeaders(path, page);
}
const clean = await get("/en/about");
ok(clean.status === 200 && clean.body.toString().includes("<html lang=\"en\">"), "/en/about finds en/about.html", String(clean.status));

// Every page of both languages, and the files that are not pages: status, content type, language, and
// that each site link on a page (the nav above all) answers 200. A page that moves or goes missing fails here.
const slugs = ["about", "news", "contact", "members", "support", "contact-sent"];
const html = /^text\/html; charset=utf-8$/;
const localLinks = new Set();
for (const [prefix, lang] of [["", "pt-BR"], ["/en", "en"]]) {
  for (const slug of slugs) {
    const path = `${prefix}/${slug}.html`;
    const res = await get(path);
    const text = res.body.toString();
    ok(res.status === 200 && html.test(res.headers["content-type"] ?? "") && text.includes(`<html lang="${lang}">`), `GET ${path} is a ${lang} html page`, `${res.status} ${res.headers["content-type"]}`);
    for (const [, href] of text.matchAll(/<a [^>]*href="([^"]*)"/g)) {
      const target = href.replaceAll("&amp;", "&");
      if (target.startsWith("/") && !target.startsWith("//")) localLinks.add(target.split("#")[0].split("?")[0]);
    }
  }
}
for (const target of [...localLinks].sort()) {
  const res = await get(target);
  ok(res.status === 200, `the page link ${target} answers 200`, String(res.status));
}
for (const [path, type] of [
  ["/robots.txt", /^text\/plain/],
  ["/sitemap.xml", /^application\/xml/],
  ["/llms.txt", /^text\/plain/],
  ["/humans.txt", /^text\/plain/],
  ["/.well-known/security.txt", /^text\/plain/],
  ["/favicon.svg", /^image\/svg\+xml/],
  ["/board.schema.json", /^application\/json/],
]) {
  const res = await get(path);
  ok(res.status === 200 && type.test(res.headers["content-type"] ?? ""), `GET ${path} answers 200 as ${type}`, `${res.status} ${res.headers["content-type"]}`);
}
const security = (await get("/.well-known/security.txt")).body.toString();
ok(/^Contact: https:\/\//m.test(security) && /^Expires: \d{4}-\d{2}-\d{2}T00:00:00Z$/m.test(security), "security.txt has Contact and Expires");
const sitemap = (await get("/sitemap.xml")).body.toString();
const locs = [...sitemap.matchAll(/<loc>([^<]*)<\/loc>/g)].map((m) => m[1].replace("https://marola.dev", ""));
for (const loc of locs) {
  const res = await get(loc.split("?")[0]);
  ok(res.status === 200, `the sitemap page ${loc} answers 200`, String(res.status));
}
ok(!locs.some((l) => /contact/.test(l)), "no contact page in the sitemap");
for (const path of ["/.well-known/.hidden", "/.env", "/sub/.well-known/security.txt"]) {
  ok((await get(path)).status === 404, `${path} is 404`);
}

const head = await request("HEAD", "/");
ok(head.status === 200 && head.body.length === 0, "HEAD / has no body");
checkHeaders("HEAD /", head);

for (const path of ["/..%2f..%2f..%2fetc/passwd", "/%2e%2e/%2e%2e/etc/passwd", "/..%5c..%5cetc/passwd", "//etc/passwd", "/assets/../../etc/passwd", "/%00", "/.git/config", "/vendor/.gitignore", "/assets/"]) {
  const res = await get(path);
  ok(res.status === 404 || res.status === 400, `hostile path ${path} is refused (${res.status})`, String(res.status));
  ok(!res.body.toString().includes("root:"), `hostile path ${path} leaks nothing`);
}

const origin = `http://${url.host}`;
const good = form({ email: "smoke@example.org", message: "A smoke test message, ten characters or more.", website: "" });
const sent = await request("POST", "/contact", { headers: formHeaders(good, { Origin: origin }), body: good });
ok(sent.status === 303 && sent.headers["location"] === "/contact-sent.html", "POST /contact with the site's Origin: 303 to /contact-sent.html", String(sent.status));
checkHeaders("POST /contact", sent);

const noOrigin = await request("POST", "/contact", { headers: formHeaders(good), body: good });
ok(noOrigin.status === 403, "POST /contact without an Origin: 403", String(noOrigin.status));
const evil = await request("POST", "/contact", { headers: formHeaders(good, { Origin: "https://evil.example" }), body: good });
ok(evil.status === 403, "POST /contact from another site: 403", String(evil.status));
const bot = form({ email: "bot@example.org", message: "buy my pills, please buy", website: "http://spam.example" });
const botRes = await request("POST", "/contact", { headers: formHeaders(bot, { Origin: origin }), body: bot });
ok(botRes.status === 200, "the honeypot gets 200", String(botRes.status));

const listing = execFileSync(inbox[0], inbox.slice(1), { encoding: "utf8" });
ok(listing.includes("smoke@example.org") && listing.includes("A smoke test message"), "marola-server inbox shows the stored message");
ok(!listing.includes("bot@example.org") && listing.split("smoke@example.org").length === 2, "the honeypot post and the refused posts are not stored");

if (failures > 0) {
  console.error(`server_smoke: ${failures} check(s) failed`);
  process.exit(1);
}
console.log("server_smoke: all checks passed");
