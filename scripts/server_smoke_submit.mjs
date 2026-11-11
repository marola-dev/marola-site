// The human side on the built server (MAROLA_DEV=1, a fake GitHub): log in through the real redirects with a cookie
// jar, make a key, submit a PDF through the FORM with its CSRF token, read the study page and compare its hash with
// `sha256sum`, report it, withdraw it and see the tombstone. Usage: node server_smoke_submit.mjs <base> <pdf> <sha256>
import { readFileSync } from "node:fs";

const [base, pdfPath, expectedSha] = process.argv.slice(2);
const pdf = readFileSync(pdfPath);
const origin = base;
const jar = new Map();
let failed = false;

function check(ok, what) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failed = true;
}

async function go(url, init = {}) {
  const headers = { ...(init.headers ?? {}) };
  if (jar.size) headers.cookie = [...jar].map(([k, v]) => `${k}=${v}`).join("; ");
  const res = await fetch(url, { ...init, headers, redirect: "manual" });
  for (const line of res.headers.getSetCookie()) {
    const [pair] = line.split(";");
    const i = pair.indexOf("=");
    if (/max-age=0|expires=Thu, 01 Jan 1970/i.test(line)) jar.delete(pair.slice(0, i));
    else jar.set(pair.slice(0, i), pair.slice(i + 1));
  }
  return res;
}
const post = (path, fields) => go(base + path, { method: "POST", headers: { origin, "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(fields) });
const csrfOf = (html) => /name="csrf" value="([0-9a-f]{64})"/.exec(html)?.[1];

// 1. Login through the redirects: the site, the fake GitHub, the callback.
const login = await go(`${base}/auth/github/login`);
check(login.status === 302 && login.headers.get("location").includes("/login/oauth/authorize?"), "login redirects to GitHub");
check(!login.headers.get("location").includes("scope="), "login asks for no scope");
const github = await go(login.headers.get("location"));
const callback = await go(github.headers.get("location"));
check(callback.status === 303 && callback.headers.get("location") === "/account", "the callback starts a session and goes to /account");
check(jar.has("msess"), "the session cookie is set");

const account = await go(`${base}/account`);
const accountHtml = await account.text();
const csrf = csrfOf(accountHtml);
check(account.status === 200 && accountHtml.includes("smoke-sci") && !!csrf, "/account shows the login and a CSRF token");
check(account.headers.get("cache-control") === "no-store", "/account is no-store");

// 2. A key is shown once.
const made = await post("/account/keys", { csrf });
const madeHtml = await made.text();
const key = /msk_[a-z2-7]{52}/.exec(madeHtml)?.[0];
check(made.status === 200 && !!key && made.headers.get("cache-control") === "no-store", "a key is shown on the answer, with no-store");
check(!(await (await go(`${base}/account`)).text()).includes(key), "the key is not shown again");

// 3. No token, or another site: 403.
const noToken = await post("/account/keys", {});
check(noToken.status === 403, "a POST without the token is 403");
const evil = await go(`${base}/account/keys`, { method: "POST", headers: { origin: "https://evil.example", "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ csrf }) });
check(evil.status === 403, "a POST from another origin is 403");

// 4. Submit through the form. The token comes first: a post without it never writes the file.
function form(withToken) {
  const f = new FormData();
  if (withToken) f.set("csrf", csrf);
  f.set("title", "Smoke test of the study form");
  f.set("authors", "Ana Silva | 0000-0002-1825-0097");
  f.set("abstract", "A smoke test study sent through the form. ".repeat(5));
  f.set("area", "rio");
  f.set("topic", "data");
  f.set("rights", "true");
  f.set("ai_contribution", "none");
  f.set("pdf", new Blob([pdf], { type: "application/pdf" }), "smoke.pdf");
  return f;
}
const denied = await go(`${base}/submit`, { method: "POST", headers: { origin }, body: form(false) });
check(denied.status === 403, "the form without a token is 403");
const sent = await go(`${base}/submit`, { method: "POST", headers: { origin }, body: form(true) });
const where = sent.headers.get("location") ?? "";
check(sent.status === 303 && /^\/studies\/[a-z2-7]{10}$/.test(where), `the form publishes and redirects to the study page (${sent.status} ${where})`);

const page = await go(base + where);
const html = await page.text();
check(page.status === 200 && html.includes(expectedSha), "the study page shows the SHA-256 that sha256sum printed");
const file = await go(`${base}${where}.pdf`);
check(file.status === 200 && Buffer.from(await file.arrayBuffer()).equals(pdf), "the PDF link serves the same bytes");
const id = where.split("/").pop();

// 5. Report it (no login needed: a new client without the jar), then withdraw it.
const reported = await fetch(`${base}/report/${id}`, { method: "POST", headers: { origin, "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ reason: "wrong", details: "smoke", website: "" }) });
check(reported.status === 200, "a report is accepted with no login");
const withdrawn = await post(`/account/withdraw/${id}`, { csrf });
check(withdrawn.status === 303, "withdraw redirects");
const tomb = await (await go(base + where)).text();
check(tomb.includes("withdrawn by the author") && tomb.includes(expectedSha) && !tomb.includes("Smoke test of the study form"), "the tombstone has the hash and the reason, no text");
check((await go(`${base}${where}.pdf`)).status === 404, "the withdrawn file is not served");

const out = await post("/logout", { csrf });
check(out.status === 303 && (await go(`${base}/account`)).status === 303, "logout ends the session");

process.exit(failed ? 1 : 0);
