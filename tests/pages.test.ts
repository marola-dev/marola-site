/** Rules every page under site/static keeps, found on disk, so a new page is held to them without a test naming it. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import vm from 'node:vm';
import { CATALOGS, INDEX, leaks, PAGES, read, ROOT, runUi } from './harness.ts';

const REPO_URL = 'https://github.com/marola-dev/marola';
const BUILT = ['app.js', 'ui.js', 'chat.js']; // esbuild's outputs, absent from a fresh checkout
const nav = (html: string): string => /<nav class="sitenav"[\s\S]*?<\/nav>/.exec(html)?.[0] ?? '';
const head = (html: string): string => /<head>[\s\S]*?<\/head>/.exec(html)?.[0] ?? '';
const scripts = (html: string): string[] => [...html.matchAll(/<script src="([^"]+)"/g)].map((m) => m[1] ?? '');

// 404.html is served at whatever path was missing: no chrome, its own inline forwarder, root-absolute links.
const SITE_PAGES = Object.entries(PAGES).filter(([page]) => page !== '404.html');

for (const [page, html] of SITE_PAGES) {
  test(`${page}: Portuguese first paint, a CSP that keeps scripts same-origin, the favicon`, () => {
    assert.match(html, /<html lang="pt-BR">/);
    const csp = /http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html)?.[1] ?? '';
    assert.match(csp, /(^|; )default-src 'self'(;|$)/, csp);
    assert.doesNotMatch(csp, /script-src|unsafe/, csp);
    assert.ok(head(html).includes('<link rel="icon" href="favicon.svg" type="image/svg+xml">'));
  });

  test(`${page}: every script is ours or vendored, exists, and the language chrome is one of them`, () => {
    const srcs = scripts(html);
    assert.ok(srcs.includes('ui.js') !== srcs.includes('app.js'), 'ui.js or app.js (which carries it), not both');
    for (const src of srcs) {
      assert.doesNotMatch(src, /\/\//, src);
      assert.ok(BUILT.includes(src) || fs.existsSync(path.join(ROOT, 'site/static', src)), `${src} is missing`);
    }
    assert.doesNotMatch(html, /<script>/, 'no inline script: the CSP would block it');
    assert.doesNotMatch(html, /\sstyle="/, 'no inline style: the CSP would block it');
  });

  test(`${page}: the section nav links docs, about, donate and the repo, with the language toggle`, () => {
    const n = nav(html);
    assert.match(n, /<a href="https:\/\/docs\.marola\.dev\/" data-i18n="nav\.docs">docs<\/a>/);
    assert.match(n, /<a href="about\.html"[^>]*data-i18n="nav\.about"[^>]*>sobre<\/a>/);
    assert.match(n, /<a href="support\.html" data-i18n="nav\.donate"[^>]*>apoie<\/a>/);
    assert.doesNotMatch(n, /<a[^>]+href="#"/, 'a section with no page is a span, not a dead link');
    assert.match(n, new RegExp(`<a class="gh" href="${REPO_URL}"[^>]*aria-label="[^"]+"`), 'the repo link keeps a name when the phone layout hides its text');
    assert.match(n, /<div id="lang"[\s\S]*?<\/div>\s*<a class="gh"/);
    const buttons = /<div id="lang"[\s\S]*?<\/div>/.exec(n)?.[0].match(/<button [^>]*>/g) ?? [];
    assert.equal(buttons.length, 2);
    assert.ok(buttons.every((b) => b.includes('type="button"') && /aria-pressed="(true|false)"/.test(b)));
    assert.match(buttons[0] ?? '', /lang="pt-BR" aria-label="português \(Brasil\)"/);
    assert.match(buttons[1] ?? '', /lang="en" aria-label="English"/);
    assert.ok(!html.includes('h0ffmann/marola'), 'no pre-rename repo URL');
  });

  test(`${page}: every data-i18n key exists in pt-BR and en`, () => {
    const keys = [...html.matchAll(/data-i18n(?:-[a-z-]+)?="([^"]+)"/g)].map((m) => m[1] ?? '');
    assert.ok(keys.length > 5);
    assert.deepEqual(
      keys.filter((k) => !(k in CATALOGS['pt-BR']) || !(k in CATALOGS.en)),
      [],
    );
  });

  test(`${page}: the language toggle, ?lang= and a localStorage that throws`, () => {
    assert.equal(runUi(html).lang(), 'pt-BR');
    const en = runUi(html, { search: '?lang=en' });
    const title = en.document.nodes.find((n) => n.tag === 'title');
    assert.equal(en.lang(), 'en');
    assert.equal(title?.textContent, CATALOGS.en[title?.attrs['data-i18n'] ?? '']);
    assert.equal(en.langBtn('en')?.attrs['aria-pressed'], 'true');
    const gh = en.document.nodes.find((n) => n.attrs.class === 'gh');
    assert.equal(gh?.attrs['aria-label'], CATALOGS.en['gh.label'], 'attributes are translated too');
    const r = runUi(html);
    r.click('en');
    assert.equal(r.langBtn('en')?.attrs['aria-pressed'], 'true');
    assert.equal(r.langBtn('pt-BR')?.attrs['aria-pressed'], 'false');
    assert.equal(r.store['marola.lang'], 'en');
    assert.match(r.urls.at(-1) ?? '', /[?&]lang=en\b/);
    r.click('pt-BR');
    assert.equal(r.lang(), 'pt-BR');
    const locked = runUi(html, { storeThrows: true, languages: ['en-US'] });
    assert.equal(locked.lang(), 'en');
    locked.click('pt-BR');
    assert.equal(locked.lang(), 'pt-BR');
  });

  test(`${page}: x-pseudo finds no visible text outside t()`, () => {
    const run = runUi(html, { search: '?lang=x-pseudo' });
    const i18nNodes = run.document.nodes.filter((n) => 'data-i18n' in n.attrs);
    let k = 0;
    const body = html.replace(/(<([a-z][a-z0-9]*)\b[^>]*\sdata-i18n="[^"]*"[^>]*>)([^<]*)(<\/\2>)/g, (_, open: string, _t, _i, close: string) => {
      return `${open}${i18nNodes[k++]?.textContent ?? ''}${close}`;
    });
    assert.equal(k, i18nNodes.length, 'every data-i18n element is a leaf, so the chrome replaces all its text');
    const text = body
      .replace(/<!--[\s\S]*?-->|<script[\s\S]*?<\/script>|<noscript>[\s\S]*?<\/noscript>|<svg[\s\S]*?<\/svg>/g, ' ')
      .replace(/<article class="about-body" lang="[^"]*">[\s\S]*?<\/article>/g, ' ') // hand-translated per language
      .replace(/<[^>]*>/g, ' ');
    const attrs = run.document.nodes.flatMap((n) => ['title', 'aria-label', 'placeholder'].flatMap((a) => (a in n.attrs ? [n.attrs[a] ?? ''] : [])));
    assert.equal(run.lang(), 'x-pseudo');
    assert.deepEqual(leaks(`${text} ${attrs.join(' ')}`, ['marola-dev/', 'marola', 'português (Brasil)', 'English', 'PT-BR'], ['EN']), []);
  });
}

test('the map page: the nav comes first, outside the footer the app rewrites', () => {
  assert.ok(INDEX.indexOf('<nav class="sitenav"') < INDEX.indexOf('<header class="bar"'));
  assert.ok(INDEX.indexOf('<nav class="sitenav"') < INDEX.indexOf('<footer id="footer"'));
  assert.equal((nav(INDEX).match(/<span aria-disabled="true">/g) ?? []).length, 3, 'alerts, news, contact: spans until they have a page');
});

test("the map page's CSP lets Mapbox's worker run from vendor/, and its scripts load in order", () => {
  const csp = /http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(INDEX)?.[1] ?? '';
  assert.match(csp, /worker-src 'self'/);
  assert.deepEqual(scripts(INDEX).slice(0, 3), ['vendor/mapbox-gl-csp.js', 'mapbox-config.js', 'app.js']);
});

test('the rail ships with only praias and balneabilidade live; every other button is a disabled "em breve"', () => {
  const buttons = [...INDEX.matchAll(/<button type="button" data-(?:layer|toggle)="(\w+)"([^>]*)>/g)];
  assert.deepEqual(
    buttons.filter((m) => !/\bdisabled\b/.test(m[2] ?? '')).map((m) => m[1]),
    ['beaches', 'water'],
  );
  assert.ok(buttons.filter((m) => /\bdisabled\b/.test(m[2] ?? '')).every((m) => (m[2] ?? '').includes('class="soon"') && (m[2] ?? '').includes('_soon"')));
});

test('the Mapbox token: committed empty, written only at deploy, never pk./sk. in the page', () => {
  assert.match(read('site/static/mapbox-config.js'), /window\.MAROLA_MAPBOX = \{ token: "", style: "" \};/);
  const leaked = fs
    .readdirSync(path.join(ROOT, 'site/static'))
    .filter((f) => /\.(js|html|css)$/.test(f) && !BUILT.includes(f))
    .concat(fs.readdirSync(path.join(ROOT, 'site/src')).map((f) => `../src/${f}`))
    .filter((f) => /\b[ps]k\.eyJ/.test(read(`site/static/${f}`)));
  assert.deepEqual(leaked, []);
  const site = read('.github/workflows/site.yml');
  assert.match(site, /MAPBOX_PUBLIC_TOKEN: \$\{\{ secrets\.MAPBOX_PUBLIC_TOKEN \|\| vars\.MAPBOX_PUBLIC_TOKEN \}\}/);
  assert.match(site, /run: scripts\/mapbox_config\.sh site\/dist/);
});

test("site.yml publishes every page and every script the pages load, and builds the bundles first", () => {
  const site = read('.github/workflows/site.yml');
  assert.ok(site.includes("! -name '*.html'"), 'every page is published, so a new one needs no edit here');
  const files = new Set([...Object.values(PAGES).flatMap((h) => scripts(h).filter((s) => !s.startsWith('vendor/'))), 'favicon.svg', 'style.css']);
  for (const f of files) assert.match(site, new RegExp(`! -name ${f.replace('.', '\\.')}\\b`), `${f} is not on the publish allowlist`);
  assert.ok(site.indexOf('npm run build') > 0 && site.indexOf('npm run build') < site.indexOf('cp -r site/static/. site/dist/'));
});

test('the support page: Patreon from FUNDING.yml, Buy Me a Coffee "soon", a checksummed address if any', () => {
  const support = PAGES['support.html'] ?? '';
  const funding = read('.github/FUNDING.yml');
  const patreon = /^patreon:\s*(\S+)/m.exec(funding)?.[1];
  assert.ok(patreon);
  assert.ok((support.match(/href="https:\/\/www\.patreon\.com\/[^"]*"/g) ?? []).every((h) => h === `href="https://www.patreon.com/${patreon}"`));
  assert.equal((support.match(/<span aria-disabled="true">Buy Me a Coffee <i>[^<]+<\/i><\/span>/g) ?? []).length, 2);
  assert.ok(!support.includes('buymeacoffee.com') && !/^buy_me_a_coffee:/m.test(funding));
  assert.equal(eip55('0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed'), '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed', "the EIP's own example");
  const addrs = [...new Set(support.match(/0x[0-9a-fA-F]{40}/g) ?? [])];
  assert.ok(addrs.length <= 1);
  const [addr] = addrs;
  if (addr) {
    assert.ok(support.includes(`href="https://etherscan.io/address/${addr}"`));
    assert.equal(eip55(addr), addr, 'a mistyped address loses donations');
  } else assert.match(support, /<code class="addr"><\/code>/, 'no address yet: its field is on the page, empty (#2)');
});

test('the not-found page forwards /docs/* to docs.marola.dev, path kept, and nothing else', () => {
  const page = PAGES['404.html'] ?? '';
  const inline = [...page.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1] ?? '');
  assert.equal(inline.length, 1);
  const visit = (url: string): string | null => {
    const u = new URL(url);
    let to: string | null = null;
    const location = { pathname: u.pathname, search: u.search, hash: u.hash, replace: (x: string) => (to = x) };
    vm.runInNewContext(inline.join('\n'), { window: { location } });
    return to;
  };
  const cases: [string, string | null][] = [
    ['https://marola.dev/docs/1-Using-marola/RUN-LOCALLY/', 'https://docs.marola.dev/1-Using-marola/RUN-LOCALLY/'],
    ['https://marola.dev/docs/', 'https://docs.marola.dev/'],
    ['https://marola.dev/docs', 'https://docs.marola.dev/'],
    ['https://marola.dev/docs/api/scala/index.html?x=1#top', 'https://docs.marola.dev/api/scala/index.html?x=1#top'],
    ['https://marola.dev/nope.html', null],
    ['https://marola.dev/docsearch', null],
    ['https://marola.dev/data/floripa/latest.json', null],
  ];
  for (const [from, want] of cases) assert.equal(visit(from), want, from);
  assert.match(page, /<a href="\/">/);
  assert.ok(head(page).includes('<link rel="icon" href="/favicon.svg" type="image/svg+xml">'), 'root-absolute, since it is served at any path');
});

test('lowercase house style, with the exemptions for names marola did not choose', () => {
  const css = read('site/static/style.css');
  assert.match(css, /body\s*\{\s*text-transform:\s*lowercase/);
  const exempt = /\.src,[\s\S]*?\{\s*text-transform:\s*none;?\s*\}/.exec(css)?.[0] ?? '';
  for (const sel of ['.src', '.water', '.list li', '.card h2', '.mapboxgl-popup .head', '.about-body code']) assert.ok(exempt.includes(sel), sel);
  assert.match(css, /\.bar h1\s*\{\s*text-transform:\s*lowercase/);
  assert.ok(fs.existsSync(path.join(ROOT, '.github/FUNDING.yml')));
  assert.match(read('site/static/favicon.svg'), /^<svg[\s>]/);
});

// EIP-55: an address's letter case is a checksum over keccak-256 of its lowercase hex. node's crypto has SHA3-256,
// which pads differently, so keccak-f[1600] is spelled out here.
const KECCAK_RC = ['1', '8082', '800000000000808a', '8000000080008000', '808b', '80000001', '8000000080008081', '8000000000008009', '8a', '88', '80008009', '8000000a', '8000808b', '800000000000008b', '8000000000008089', '8000000000008003', '8000000000008002', '8000000000000080', '800a', '800000008000000a', '8000000080008081', '8000000000008080', '80000001', '8000000080008008'].map((h) => BigInt(`0x${h}`));
const KECCAK_ROT = [0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14];
function keccak256Hex(ascii: string): string {
  // one block: inputs under 136 bytes, which a 40-digit address is
  const M = (1n << 64n) - 1n;
  const rot = (v: bigint, n: number): bigint => (n ? ((v << BigInt(n)) | (v >> BigInt(64 - n))) & M : v);
  const block = Buffer.alloc(136);
  block.write(ascii, 'ascii');
  block.writeUInt8(block.readUInt8(ascii.length) ^ 0x01, ascii.length);
  block.writeUInt8(block.readUInt8(135) ^ 0x80, 135);
  const A = Array.from({ length: 25 }, (_, i) => (i < 17 ? block.readBigUInt64LE(8 * i) : 0n));
  const a = (i: number): bigint => A[i] ?? 0n;
  for (const rc of KECCAK_RC) {
    const C = [0, 1, 2, 3, 4].map((x) => a(x) ^ a(x + 5) ^ a(x + 10) ^ a(x + 15) ^ a(x + 20));
    const c = (i: number): bigint => C[i] ?? 0n;
    for (let x = 0; x < 5; x++) {
      const D = c((x + 4) % 5) ^ rot(c((x + 1) % 5), 1);
      for (let y = 0; y < 25; y += 5) A[x + y] = a(x + y) ^ D;
    }
    const B: bigint[] = new Array<bigint>(25).fill(0n);
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) B[y + 5 * ((2 * x + 3 * y) % 5)] = rot(a(x + 5 * y), KECCAK_ROT[x + 5 * y] ?? 0);
    const b = (i: number): bigint => B[i] ?? 0n;
    for (let i = 0; i < 25; i++) A[i] = b(i) ^ (~b(((i % 5) + 1) % 5 + i - (i % 5)) & M & b(((i % 5) + 2) % 5 + i - (i % 5)));
    A[0] = a(0) ^ rc;
  }
  const out = Buffer.alloc(32);
  for (let i = 0; i < 4; i++) out.writeBigUInt64LE(a(i), 8 * i);
  return out.toString('hex');
}
function eip55(addr: string): string {
  const hex = addr.slice(2).toLowerCase();
  const h = keccak256Hex(hex);
  return `0x${hex.replace(/[a-f]/g, (ch: string, i: number) => (parseInt(h[i] ?? '0', 16) >= 8 ? ch.toUpperCase() : ch))}`;
}
