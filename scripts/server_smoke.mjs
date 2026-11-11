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

const module_ = await get("/app/Program.js");
ok(module_.status === 200 && /text\/javascript/.test(module_.headers["content-type"]), "GET /app/Program.js is JavaScript", String(module_.status));
checkHeaders("/app/Program.js", module_);

const packed = await get("/app/Program.js", { "Accept-Encoding": "br, gzip" });
ok(packed.headers["content-encoding"] === "br", "JavaScript goes out compressed (br)", String(packed.headers["content-encoding"]));

const data = await get("/data/floripa/latest.json");
ok(data.status === 200 && /application\/json/.test(data.headers["content-type"]), "GET /data/floripa/latest.json is JSON", String(data.status));
ok(data.body.toString().includes("smoke"), "/data/ is read from MAROLA_DATA first");
checkHeaders("/data/floripa/latest.json", data);

const missing = await get("/nope");
ok(missing.status === 404, "GET /nope is 404", String(missing.status));
ok(/text\/html/.test(missing.headers["content-type"]) && missing.body.toString().includes("<html lang=\"pt-BR\">"), "/nope is the pt-BR 404 page");
checkHeaders("/nope", missing);
const missingEn = await get("/en/nope");
ok(missingEn.status === 404 && missingEn.body.toString().includes("<html lang=\"en\">"), "/en/nope is the English 404 page", String(missingEn.status));

// The pages of app/Pages, in both languages (run app-build first).
for (const [path, lang] of [["/about.html", "pt-BR"], ["/en/about.html", "en"], ["/contact.html", "pt-BR"], ["/en/contact.html", "en"], ["/contact-sent.html", "pt-BR"], ["/en/support.html", "en"]]) {
  const page = await get(path);
  ok(page.status === 200 && /text\/html/.test(page.headers["content-type"]) && page.body.toString().includes(`<html lang="${lang}">`), `GET ${path} is the ${lang} page`, String(page.status));
  checkHeaders(path, page);
}
const clean = await get("/en/about");
ok(clean.status === 200 && clean.body.toString().includes("<html lang=\"en\">"), "/en/about finds en/about.html", String(clean.status));

const head = await request("HEAD", "/");
ok(head.status === 200 && head.body.length === 0, "HEAD / has no body");
checkHeaders("HEAD /", head);

for (const path of ["/..%2f..%2f..%2fetc/passwd", "/%2e%2e/%2e%2e/etc/passwd", "/..%5c..%5cetc/passwd", "//etc/passwd", "/app/../../etc/passwd", "/%00", "/.git/config", "/app/fable_modules/.gitignore", "/app/"]) {
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
