#!/usr/bin/env node
// A ratchet on the effectful constructs of the F# code. No packages.
//
// For every F# project under app/ (a folder with an .fsproj) it counts, in the `*.fs` files and outside
// comments and string literals: lines of code (non-blank, after the comments and strings are blanked) and
// `mutable`, `null`, `raise`/`failwith`, `.Result`, `.Wait(`, `Async.RunSynchronously`, `unbox`, `downcast`
// and `:?>`, and ref cells (`ref` and `:=`). It prints a table and compares it with docs/fp-baseline.json.
//
// A count that goes UP fails: the architecture rule is that `Shared`, `Client/Core` and `Pages` are pure and
// the effects sit in `Server` and `Client/App` (docs/7-quality.md), so a new effect must be a visible decision.
// A count that goes DOWN also fails, until the baseline is lowered with `--update`, so the ceiling cannot
// stay loose after a cleanup. `--update` refuses to raise a count: raise it by hand in the JSON, in a diff
// a person reads. A project with no baseline fails until `--update` records it. The baseline holds the effect counts only; lines of code are informational.
//
// What the counts do not see: the text inside an interpolated hole (`$"{x}"` is blanked whole), `null` tests
// written as `isNull`, and a `.Result` that goes through another name. They are a ratchet, not a proof.
//
// `--self-test` runs the counter and the comparison on bad fixtures and checks that each one fails.

"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const APP = path.join(ROOT, "app");
const BASELINE = path.join(ROOT, "docs", "fp-baseline.json");
const SKIP_DIRS = new Set(["bin", "obj", "out", "dist", "node_modules", "fable_modules", ".git"]);

// name, regex over the blanked code. Every regex is global.
const METRICS = [
  ["mutable", /\bmutable\b/g],
  ["null", /\bnull\b/g],
  ["raise", /\b(?:raise|failwith|failwithf)\b/g],
  [".Result", /\.Result\b/g],
  [".Wait(", /\.Wait\s*\(/g],
  ["RunSync", /\bAsync\.RunSynchronously\b/g],
  ["unbox", /\bunbox\b/g],
  ["downcast", /\bdowncast\b|:\?>/g],
  // `ref'` is an identifier in this code base, not a cell.
  ["ref", /(?<![\w.'])ref\b(?!')|:=/g],
];
const COLUMNS = ["loc", ...METRICS.map(([name]) => name)];

// Replaces comments and string and char literals with spaces, keeping newlines, so the regexes and the line
// count see code only.
function blank(src) {
  let out = "";
  let i = 0;
  const n = src.length;
  const pad = (text) => text.replace(/[^\n]/g, " ");
  while (i < n) {
    const c = src[i];
    const rest = src.slice(i, i + 4);
    if (c === "/" && src[i + 1] === "/") {
      let j = src.indexOf("\n", i);
      if (j < 0) j = n;
      out += pad(src.slice(i, j));
      i = j;
    } else if (c === "(" && src[i + 1] === "*" && src[i + 2] !== ")") {
      // Block comments nest in F#.
      let depth = 1;
      let j = i + 2;
      while (j < n && depth > 0) {
        if (src[j] === "(" && src[j + 1] === "*") { depth++; j += 2; }
        else if (src[j] === "*" && src[j + 1] === ")") { depth--; j += 2; }
        else j++;
      }
      out += pad(src.slice(i, j));
      i = j;
    } else if (/^(?:\$|@|\$@|@\$)?"""/.test(rest) || (c === '"' && src.startsWith('"""', i))) {
      const open = src.indexOf('"""', i);
      let j = src.indexOf('"""', open + 3);
      j = j < 0 ? n : j + 3;
      out += pad(src.slice(i, j));
      i = j;
    } else if (/^(?:\$@|@\$|@)"/.test(rest)) {
      // Verbatim: a doubled quote is a quote.
      let j = src.indexOf('"', i) + 1;
      while (j < n) {
        if (src[j] === '"' && src[j + 1] === '"') j += 2;
        else if (src[j] === '"') { j++; break; }
        else j++;
      }
      out += pad(src.slice(i, j));
      i = j;
    } else if (c === '"' || (c === "$" && src[i + 1] === '"')) {
      let j = src.indexOf('"', i) + 1;
      while (j < n && src[j] !== '"') j += src[j] === "\\" ? 2 : 1;
      j = Math.min(j + 1, n);
      out += pad(src.slice(i, j));
      i = j;
    } else if (c === "'") {
      const m = /^'(?:\\[^'\n]*|[^\\'\n])'/.exec(src.slice(i, i + 12));
      if (m) {
        out += " ".repeat(m[0].length);
        i += m[0].length;
      } else {
        out += c;
        i++;
      }
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

function count(src) {
  const code = blank(src);
  const row = { loc: code.split("\n").filter((l) => l.trim() !== "").length };
  for (const [name, re] of METRICS) row[name] = (code.match(re) || []).length;
  return row;
}

function add(a, b) {
  const out = {};
  for (const k of COLUMNS) out[k] = (a[k] || 0) + (b[k] || 0);
  return out;
}

function walk(dir, visit) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) walk(path.join(dir, entry.name), visit);
    } else visit(path.join(dir, entry.name));
  }
}

// project dir (relative to the repo, with `/`) -> counts of its files.
function measure() {
  const projects = [];
  walk(APP, (file) => {
    if (file.endsWith(".fsproj")) projects.push(path.dirname(file));
  });
  const result = {};
  for (const dir of projects.sort()) {
    let total = add({}, {});
    walk(dir, (file) => {
      if (file.endsWith(".fs")) total = add(total, count(fs.readFileSync(file, "utf8")));
    });
    result[path.relative(ROOT, dir).split(path.sep).join("/")] = total;
  }
  return result;
}

const isTest = (name) => /Tests(\.Fable)?$/.test(name);

function table(current, baseline) {
  const lines = [];
  const header = ["project", ...COLUMNS];
  const body = [];
  for (const [kind, pick] of [["source", (n) => !isTest(n)], ["tests", isTest]]) {
    for (const name of Object.keys(current).filter(pick)) {
      const cells = COLUMNS.map((k) => {
        const was = baseline && baseline[name] ? baseline[name][k] : undefined;
        const now = current[name][k];
        return was === undefined || was === now ? String(now) : `${now} (was ${was})`;
      });
      body.push([`${name}${kind === "tests" ? " [tests]" : ""}`, ...cells]);
    }
  }
  const widths = header.map((h, i) => Math.max(h.length, ...body.map((r) => r[i].length)));
  const fmt = (r) => r.map((c, i) => (i === 0 ? c.padEnd(widths[i]) : c.padStart(widths[i]))).join("  ");
  lines.push(fmt(header), widths.map((w) => "-".repeat(w)).join("  "));
  for (const r of body) lines.push(fmt(r));
  return lines.join("\n");
}

// Returns { up: [...], down: [...], missing: [...] } as human lines. Only `loc` is not ratcheted: code may grow.
function compare(current, baseline) {
  const up = [];
  const down = [];
  const missing = [];
  for (const name of Object.keys(current)) {
    if (!baseline[name]) {
      missing.push(`${name}: no baseline (record it with --update)`);
      continue;
    }
    for (const [k] of METRICS) {
      const now = current[name][k];
      const was = baseline[name][k];
      if (was === undefined) missing.push(`${name}: no baseline for ${k}`);
      else if (now > was) up.push(`${name}: ${k} went up, ${was} -> ${now}`);
      else if (now < was) down.push(`${name}: ${k} went down, ${was} -> ${now}`);
    }
  }
  for (const name of Object.keys(baseline)) {
    if (!current[name]) missing.push(`${name}: in the baseline, not found under app/ (lower it with --update)`);
  }
  return { up, down, missing };
}

function verdict(result) {
  const lines = [];
  for (const l of result.up) lines.push(`FAIL ${l}`);
  for (const l of result.missing) lines.push(`FAIL ${l}`);
  for (const l of result.down) lines.push(`FAIL ${l}: lower the baseline with \`just fp-audit --update\``);
  return lines;
}

function selfTest() {
  const bad = [
    "module M",
    "let mutable a = 0",
    "let b : string = null",
    "let c = raise (System.Exception())",
    "let d = failwith \"x\"",
    "let e = t.Result",
    "t.Wait()",
    "Async.RunSynchronously x",
    "let f = unbox<int> o",
    "let g = o :?> string",
    "let h = downcast o",
    "let r = ref 0",
    "r := 1",
  ].join("\n");
  // Everything in here is a comment, a string or an identifier, and must count as nothing.
  const decoys = [
    "// mutable null raise unbox .Result",
    "/// failwith in a doc comment",
    "(* nested (* mutable *) null *)",
    'let s = "mutable null raise failwith"',
    'let v = @"unbox ""null"" .Result"',
    'let t = """downcast :?> ref 0"""',
    "let u = $\"{x} mutable\"",
    "let q = '\"'",
    "let ref' = 1",
    "let op = (*)",
    "let isNullOrEmpty = String.IsNullOrEmpty x",
    "let Result = 1",
  ].join("\n");

  const want = { mutable: 1, null: 1, raise: 2, ".Result": 1, ".Wait(": 1, RunSync: 1, unbox: 1, downcast: 2, ref: 2 };
  const cases = [];
  const got = count(bad);
  for (const [k, v] of Object.entries(want)) cases.push([`counts ${k}`, got[k] === v ? null : `${k} = ${got[k]}, wanted ${v}`]);
  const decoyRow = count(decoys);
  for (const [k] of METRICS) cases.push([`decoys do not count ${k}`, decoyRow[k] === 0 ? null : `${k} = ${decoyRow[k]}`]);
  cases.push(["blank lines and comments are not code", count("// a\n\n  \nlet x = 1\n").loc === 1 ? null : "loc"]);

  const base = { p: { ...Object.fromEntries(METRICS.map(([k]) => [k, 2])), loc: 10 } };
  const same = JSON.parse(JSON.stringify(base));
  const up = JSON.parse(JSON.stringify(base));
  up.p.mutable = 3;
  const down = JSON.parse(JSON.stringify(base));
  down.p.null = 1;
  const extra = { ...same, q: same.p };
  cases.push(["equal counts pass", verdict(compare(same, base)).length === 0 ? null : "failed"]);
  cases.push(["a count that goes up fails", verdict(compare(up, base)).some((l) => /mutable went up/.test(l)) ? null : "passed"]);
  cases.push(["a count that goes down fails and names --update", verdict(compare(down, base)).some((l) => /null went down.*--update/.test(l)) ? null : "passed"]);
  cases.push(["a project with no baseline fails", verdict(compare(extra, base)).some((l) => /q: no baseline/.test(l)) ? null : "passed"]);
  cases.push(["a project that vanished fails", verdict(compare({}, base)).some((l) => /p: in the baseline/.test(l)) ? null : "passed"]);
  cases.push(["loc may grow", verdict(compare({ p: { ...same.p, loc: 999 } }, base)).length === 0 ? null : "failed"]);

  let failed = 0;
  for (const [label, problem] of cases) {
    if (problem !== null) {
      failed++;
      console.log(`fp_audit self-test: ${label}: ${problem}`);
    }
  }
  if (failed > 0) process.exit(1);
  console.log(`fp_audit self-test: ok (${cases.length} cases)`);
}

function main() {
  if (process.argv.includes("--self-test")) return selfTest();
  const current = measure();
  const baseline = fs.existsSync(BASELINE) ? JSON.parse(fs.readFileSync(BASELINE, "utf8")) : null;
  console.log(table(current, baseline));

  if (process.argv.includes("--update")) {
    const raised = baseline ? compare(current, baseline).up : [];
    if (raised.length > 0) {
      for (const l of raised) console.error(`FAIL ${l}`);
      console.error("fp_audit: --update only lowers. To accept a higher count, edit docs/fp-baseline.json by hand and say why in the PR.");
      process.exit(1);
    }
    // `loc` is not stored: it changes with every commit and is never compared.
    const counts = {};
    for (const [name, row] of Object.entries(current)) counts[name] = Object.fromEntries(METRICS.map(([k]) => [k, row[k]]));
    fs.writeFileSync(BASELINE, JSON.stringify(counts, null, 2) + "\n");
    console.log(`fp_audit: wrote ${path.relative(ROOT, BASELINE)}`);
    return;
  }
  if (!baseline) {
    console.error("FAIL docs/fp-baseline.json is missing: record the first one with `just fp-audit --update`");
    process.exit(1);
  }
  const lines = verdict(compare(current, baseline));
  if (lines.length > 0) {
    for (const l of lines) console.error(l);
    process.exit(1);
  }
  console.log("fp_audit: ok, no count above the baseline");
}

main();
