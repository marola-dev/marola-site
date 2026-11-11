// The study API on the built server: no key is a 401, a dry run stores nothing, a real submission is read
// back and its hash is the one `sha256sum` printed. Usage: node server_smoke_studies.mjs <base> <key> <pdf> <sha256> <studies-dir>
import { readFileSync, existsSync, readdirSync } from "node:fs";

const [base, key, pdfPath, expectedSha, studiesDir] = process.argv.slice(2);
const pdf = readFileSync(pdfPath);
let failed = false;

function check(ok, what) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failed = true;
}

// `small` sends a stub file: a refusal that comes before the body is read (401, 429) would break a 2 MB upload
// mid-write, and that is the client's problem, not what this check is about.
function form(small = false) {
  const f = new FormData();
  f.set("title", "Smoke test of the study API");
  f.set("authors", "Ana Silva | 0000-0002-1825-0097");
  f.set("abstract", "A smoke test study. ".repeat(10));
  f.set("area", "rio");
  f.set("topic", "data");
  f.set("rights", "true");
  f.set("ai_contribution", "none");
  f.set("pdf", new Blob([small ? "x" : pdf], { type: "application/pdf" }), "smoke.pdf");
  return f;
}

const auth = { Authorization: `Bearer ${key}` };
const files = () => (existsSync(studiesDir) ? readdirSync(studiesDir).filter((n) => n.endsWith(".pdf")) : []);

const none = await fetch(`${base}/api/v1/studies`, { method: "POST", body: form(true) });
check(none.status === 401, "a POST without a key is a 401");

const dry = await fetch(`${base}/api/v1/studies?dry_run=1`, { method: "POST", headers: auth, body: form() });
const dryBody = await dry.json();
check(dry.status === 200 && dryBody.dry_run === true, "a dry run answers 200");
check(dryBody.sha256 === expectedSha, "the dry run hash equals sha256sum");
check(files().length === 0, "a dry run leaves no file");
const empty = await (await fetch(`${base}/api/v1/studies`)).json();
check(empty.studies.length === 0, "a dry run leaves no row");

const real = await fetch(`${base}/api/v1/studies`, { method: "POST", headers: auth, body: form() });
const receipt = await real.json();
check(real.status === 201, `a real submission answers 201 (${real.status}, a ${(pdf.length / 1e6).toFixed(1)} MB file)`);
check(receipt.sha256 === expectedSha, "the receipt hash equals sha256sum");
check(files().join() === `${expectedSha}.pdf`, "the file is stored as <sha256>.pdf");

const record = await (await fetch(`${base}/api/v1/studies/${receipt.id}`)).json();
check(record.id === receipt.id && record.review === "not reviewed", "the record reads back, labelled not reviewed");

const file = await fetch(`${base}${receipt.pdf_url}`);
const bytes = Buffer.from(await file.arrayBuffer());
check(file.status === 200 && Buffer.compare(bytes, pdf) === 0, "the PDF reads back byte for byte");
check(file.headers.get("content-type") === "application/pdf", "the PDF is application/pdf");
check(file.headers.get("content-security-policy") === "sandbox; default-src 'none'", "the PDF has the sandbox CSP");
check(file.headers.get("x-content-type-options") === "nosniff", "the PDF has nosniff");

const again = await fetch(`${base}/api/v1/studies`, { method: "POST", headers: auth, body: form(true) });
check(again.status === 429, "a second submission at once is a 429");

const skill = await fetch(`${base}/api/v1/skill.md`);
check(skill.status === 200 && (await skill.text()).includes("dry_run=1"), "skill.md is served");

process.exit(failed ? 1 : 0);
