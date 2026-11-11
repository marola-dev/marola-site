// What the board's commands did, seen from outside: a hidden study shows its tombstone and never serves its file;
// after a purge the file is gone from disk too. Usage: node server_smoke_board.mjs <base> <id> <sha256> <studies-dir> hidden|purged
import { existsSync } from "node:fs";

const [base, id, sha, studiesDir, mode] = process.argv.slice(2);
let failed = false;

function check(ok, what) {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failed = true;
}

const page = await fetch(`${base}/studies/${id}`);
const html = await page.text();
check(page.status === 200 && html.includes(sha), `[${mode}] the tombstone page shows the hash`);
check(html.includes("smoke: ") && !html.includes("Smoke test of the study API"), `[${mode}] the tombstone shows the board's reason and no study text`);
const pdf = await fetch(`${base}/studies/${id}.pdf`);
check(pdf.status === 404, `[${mode}] the file is not served`);
const api = await (await fetch(`${base}/api/v1/studies/${id}`)).json();
check(api.status === "hidden" && api.sha256 === sha && !("title" in api), `[${mode}] the API answers a tombstone with the hash and no text`);
const listed = await (await fetch(`${base}/api/v1/studies`)).json();
check(!listed.studies.some((s) => s.id === id), `[${mode}] the study left the list`);
const onDisk = existsSync(`${studiesDir}/${sha}.pdf`);
check(mode === "hidden" ? onDisk : !onDisk, mode === "hidden" ? "the hidden study's file is still on disk" : "the purge removed the file from disk");

process.exit(failed ? 1 : 0);
