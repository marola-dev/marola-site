#!/usr/bin/env node
// Fails when DESIGN.md and app/Client/public/style.css drift apart. No packages.
//
// Rules:
//   1. Every custom property defined in `:root` has a row in a DESIGN.md token table.
//   2. Every token row in DESIGN.md is defined in `:root`, with the same value.
//   3. style.css holds no hex colour outside `:root`, except the ALLOW list below.
//
// A token row is a row of a table whose header starts with "Token". Its first cell is one backticked
// `--name` and its second cell is the backticked value, exactly as `:root` writes it (whitespace
// collapsed):
//   | Token | Value | Job |
//   | `--accent` | `#1b5fc1` | links, primary fill |
// Other tables (the contrast table) may name a token in their first cell and are not read.
//
// `--self-test` runs the three rules on bad fixtures and checks that each one fails.

"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");

// Hex colours that may stay outside `:root`. Each one is a debt: a token would be better, but the
// rule would change how the page looks. The check also fails when an entry no longer occurs, so
// this list can only shrink.
const ALLOW = {
  "#fff": "text on a filled accent, on a score colour and on a pressed layer button; white by definition, not the page background",
  "#b4bec9": "hover border of a control, one step darker than --line-strong; no token yet",
  "#137a5c": "the 'proper' water status in the beach card; --c70 is too light for text; no token yet",
};

function stripComments(css) {
  return css.replace(/\/\*[\s\S]*?\*\//g, "");
}

function norm(value) {
  return value.replace(/\s+/g, " ").trim();
}

// The `:root` block: [text of the block, css without the block].
function splitRoot(css) {
  const start = css.search(/:root\s*\{/);
  if (start < 0) return [null, css];
  const open = css.indexOf("{", start);
  const close = css.indexOf("}", open);
  return [css.slice(open + 1, close), css.slice(0, start) + css.slice(close + 1)];
}

function rootTokens(css) {
  const [block] = splitRoot(stripComments(css));
  const tokens = new Map();
  if (block === null) return tokens;
  for (const decl of block.split(";")) {
    const m = /^\s*(--[A-Za-z0-9-]+)\s*:([\s\S]*)$/.exec(decl);
    if (m) tokens.set(m[1], norm(m[2]));
  }
  return tokens;
}

// Rows of the DESIGN.md tables whose header starts with "Token". A row with a token and no
// backticked value is returned with value null, so the check can name it.
function docTokens(md) {
  const rows = [];
  let inTokenTable = false;
  let previousWasRow = false;
  for (const line of md.split("\n")) {
    if (!line.startsWith("|")) {
      previousWasRow = false;
      inTokenTable = false;
      continue;
    }
    const cells = line.split("|").slice(1, -1).map((c) => c.trim());
    if (!previousWasRow) inTokenTable = cells[0] === "Token";
    previousWasRow = true;
    if (!inTokenTable) continue;
    const name = /^`(--[A-Za-z0-9-]+)`$/.exec(cells[0] || "");
    if (!name) continue;
    const value = /^`(.+)`$/.exec(cells[1] || "");
    rows.push({ name: name[1], value: value ? norm(value[1]) : null });
  }
  return rows;
}

function hexOutsideRoot(css) {
  const [, rest] = splitRoot(stripComments(css));
  const found = new Map();
  // A colour follows a colon, a space, a comma or a bracket; a selector like `#app` has no hex-only name.
  for (const m of rest.matchAll(/(?<=[:\s,(])(#[0-9a-fA-F]{3,8})(?![\w-])/g)) {
    const hex = m[1].toLowerCase();
    found.set(hex, (found.get(hex) || 0) + 1);
  }
  return found;
}

function check(md, css, allow) {
  const failures = [];
  const root = rootTokens(css);
  const rows = docTokens(md);
  const documented = new Set(rows.map((r) => r.name));

  for (const name of root.keys()) {
    if (!documented.has(name)) failures.push(`undocumented token: ${name} is in :root, not in a DESIGN.md table`);
  }
  const seen = new Set();
  for (const row of rows) {
    if (seen.has(row.name)) failures.push(`duplicate row: ${row.name} appears twice in DESIGN.md`);
    seen.add(row.name);
    if (!root.has(row.name)) {
      failures.push(`unknown token: ${row.name} is in DESIGN.md, not in :root`);
    } else if (row.value === null) {
      failures.push(`no value: the DESIGN.md row of ${row.name} has no backticked value`);
    } else if (row.value !== root.get(row.name)) {
      failures.push(`value differs: ${row.name} is \`${row.value}\` in DESIGN.md and \`${root.get(row.name)}\` in :root`);
    }
  }

  const hex = hexOutsideRoot(css);
  for (const [colour, count] of hex) {
    if (!(colour in allow)) failures.push(`hex outside :root: ${colour} (${count}x) in style.css; use a token or add it to ALLOW with a reason`);
  }
  for (const colour of Object.keys(allow)) {
    if (!hex.has(colour)) failures.push(`unused allowlist entry: ${colour} no longer occurs in style.css; remove it`);
  }
  return failures;
}

function selfTest() {
  const css = ":root { --ink: #111820; --bg: #fff; /* c */ --sh: 0 1px 2px rgb(0 0 0 / .1), 0 2px 4px red; }\n#app { color: var(--ink); }\n";
  const md = [
    "| Token | Value | Job |",
    "|---|---|---|",
    "| `--ink` | `#111820` | text |",
    "| `--bg` | `#fff` | page |",
    "| `--sh` | `0 1px 2px rgb(0 0 0 / .1), 0 2px 4px red` | shadow |",
  ].join("\n");
  const cases = [
    ["a good pair passes", md, css, {}, null],
    ["a table that is not headed Token is not read", md + "\n\n| Text | On |\n|---|---|\n| `--ink` | `--bg` |\n", css, {}, null],
    ["rule 1: a token missing from DESIGN.md", md.replace(/\n\| `--bg`.*/, ""), css, {}, "undocumented token: --bg"],
    ["rule 2: a token missing from :root", md + "\n| `--gone` | `1px` | x |", css, {}, "unknown token: --gone"],
    ["rule 2: a different value", md.replace("#111820", "#111821"), css, {}, "value differs: --ink"],
    ["rule 2: a row with no value", md.replace("`#111820`", "#111820"), css, {}, "no value: the DESIGN.md row of --ink"],
    ["rule 3: a hex outside :root", md, css + ".a { color: #abc; }\n", {}, "hex outside :root: #abc"],
    ["rule 3: a hex in a media query", md, css + "@media (max-width: 1px) { .a { background: #A1B2C3; } }\n", {}, "hex outside :root: #a1b2c3"],
    ["rule 3: an allowed hex passes", md, css + ".a { color: #abc; }\n", { "#abc": "test" }, null],
    ["rule 3: an unused allowlist entry", md, css, { "#abc": "test" }, "unused allowlist entry: #abc"],
  ];
  let bad = 0;
  for (const [label, m, c, allow, expect] of cases) {
    const out = check(m, c, allow);
    const ok = expect === null ? out.length === 0 : out.some((f) => f.includes(expect));
    if (!ok) {
      bad++;
      console.log(`design_check self-test: ${label}: expected ${expect === null ? "no failure" : expect}, got ${JSON.stringify(out)}`);
    }
  }
  if (bad) process.exit(1);
  console.log(`design_check self-test: ok (${cases.length} cases)`);
}

function main() {
  if (process.argv.includes("--self-test")) return selfTest();
  const md = fs.readFileSync(path.join(ROOT, "DESIGN.md"), "utf8");
  const css = fs.readFileSync(path.join(ROOT, "app/Client/public/style.css"), "utf8");
  const failures = check(md, css, ALLOW);
  for (const f of failures) console.log(`design_check: ${f}`);
  if (failures.length) process.exit(1);
  console.log("design_check: ok");
}

main();
