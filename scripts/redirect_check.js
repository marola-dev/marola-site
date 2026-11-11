#!/usr/bin/env node
// redirect_check — runs site/static/404.html's script against a stub location: /docs/* goes to
// docs.marola.dev with the path kept, anything else stays on the not-found page (MIP-0070 §5.8).
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const PAGE = fs.readFileSync(path.resolve(__dirname, '..', 'site/static/404.html'), 'utf8');
const scripts = [...PAGE.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);

let fails = 0;
function ok(cond, label, detail) {
  if (cond) console.log('  ok   ' + label);
  else { console.log('  FAIL ' + label + (detail ? ' — ' + detail : '')); fails++; }
}

function visit(url) {
  const u = new URL(url);
  let to = null;
  const location = { pathname: u.pathname, search: u.search, hash: u.hash, replace: x => { to = x; } };
  vm.runInNewContext(scripts.join('\n'), { window: { location } });
  return to;
}

console.log('redirect_check:');
ok(scripts.length === 1, '404.html has exactly one inline script');
[
  ['https://marola.dev/docs/1-Using-marola/RUN-LOCALLY/', 'https://docs.marola.dev/1-Using-marola/RUN-LOCALLY/'],
  ['https://marola.dev/docs/', 'https://docs.marola.dev/'],
  ['https://marola.dev/docs', 'https://docs.marola.dev/'],
  ['https://marola.dev/docs/api/scala/index.html?x=1#top', 'https://docs.marola.dev/api/scala/index.html?x=1#top'],
  ['https://marola.dev/nope.html', null],
  ['https://marola.dev/docsearch', null],
  ['https://marola.dev/data/floripa/latest.json', null]
].forEach(([from, want]) => {
  const got = visit(from);
  ok(got === want, from + ' → ' + (want || 'stays on the 404'), 'got ' + got);
});
ok(/<a href="\/">/.test(PAGE), 'the not-found page links back to the map');

if (fails === 0) { console.log('redirect_check: ok'); process.exit(0); }
console.error('redirect_check: ' + fails + ' failure(s)'); process.exit(1);
