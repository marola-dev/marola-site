#!/usr/bin/env node
/** front_check: smoke test of the BUILT Elm page in dist (run `scripts/site_build.sh --fixtures` first).
 * No browser, no network, no dependencies: a DOM that has only the members Elm's virtual-dom, ports.js and the two FFI
 * files touch, a MapLibre stub that records every call, and an XMLHttpRequest (elm/http's) that serves dist. Each scenario runs in a child
 * node process because the bundle keeps state.
 *
 * Not checked here:
 *  - the board JSON-Schema validator and the frozen schema-1 board (the Elm decoder tests and board-schema.sh own that)
 *  - the wind/wave flow layer (flow.js) and its particles: the compiled client ships them disabled, WebGL has no stub here
 *  - Spotify's player inside its iframe (the playlist scenario covers the iframe's url, the toggle and the CSP's frame-src)
 *  - the aspect-by-aspect tooltip numbers (MIP-0009 section 3), note codes, sea lore and score-note folds, SOS numbers
 *  - data-i18n attributes, the pseudo-locale gate, the lowercase house style
 *  - Mapbox token handling and the composite coastline layer (the client draws the site's own tiles, no token)
 *  - the static pages: section nav, donations, members, contact, favicon, page heads/JSON-LD
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { pathToFileURL } = require('url');

const ROOT = path.resolve(__dirname, '..');
// FRONT_CHECK_DIST points the test at another build, e.g. a patched copy.
const DIST = process.env.FRONT_CHECK_DIST || path.join(ROOT, 'dist');
const distJson = (rel) => JSON.parse(fs.readFileSync(path.join(DIST, rel), 'utf8'));
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const NOT_CHECKED = ['board schema validation', 'flow layer (wind/waves/particles)', 'Spotify player', 'tooltip aspect numbers, note codes, folds, SOS',
  'data-i18n attributes and the pseudo-locale', 'Mapbox token and composite coastline', 'static pages (nav, donate, members, contact, heads)'];

let fails = 0, total = 0;
function ok(cond, label, detail) {
  total++;
  if (cond) console.log('  ok   ' + label);
  else { console.log('  FAIL ' + label + (detail ? ' (' + detail + ')' : '')); fails++; }
}

// ---- static checks: index.html, csp.txt, FFI sources, compiled output --------------------------------------
function walk(dir, skip, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (skip(p) || e.isSymbolicLink()) continue;
    if (e.isDirectory()) walk(p, skip, out); else out.push(p);
  }
  return out;
}
const bundle = () => fs.readdirSync(path.join(DIST, 'assets')).filter((f) => /^index-[\w-]+\.js$/.test(f)).map((f) => path.join(DIST, 'assets', f));
function staticChecks() {
  const html = fs.readFileSync(path.join(DIST, 'index.html'), 'utf8');
  const scripts = [...html.matchAll(/<script\b([^>]*)>/g)].map((m) => m[1]);
  ok(scripts.length === 2, 'index.html has the ld+json block and the boot script', scripts.length);
  ok(scripts.every((a) => /\bsrc=/.test(a) || /type="application\/ld\+json"/.test(a)), 'every <script> is src= or ld+json (no inline code)');
  ok(/<script type="module" crossorigin src="\.\/assets\/index-[\w-]+\.js"><\/script>/.test(html) && bundle().length === 1, 'the page boots through one <script type=module src=./assets/index-*.js>');
  ok(!/\sstyle\s*=/i.test(html) && !/<style\b/i.test(html), 'index.html has no style= attribute and no <style>');
  ok(!/\son[a-z]+\s*=\s*["']/i.test(html), 'index.html has no inline event handler');
  const meta = /http-equiv="Content-Security-Policy" content="([^"]*)"/.exec(html);
  const csp = meta ? meta[1] : '';
  ok(/(^|; )script-src 'self'(;|$)/.test(csp) && /(^|; )default-src 'self'(;|$)/.test(csp), "the CSP meta has default-src and script-src 'self'", csp);
  // csp.txt is the server's header (marola-server csp); a <meta> cannot carry frame-ancestors.
  const header = fs.readFileSync(path.join(DIST, 'csp.txt'), 'utf8').trim();
  ok(csp === header.replace("; frame-ancestors 'none'", ''), 'the CSP meta equals csp.txt minus frame-ancestors', header);
  ok(!/unsafe-inline|unsafe-eval/.test(csp), "the CSP has no 'unsafe-inline' or 'unsafe-eval'");
  const tokens = csp.split(/[\s;]+/);
  ok(!tokens.includes('https:') && !tokens.includes('*'), 'the CSP has no bare https: or *');
  const directive = (name) => (csp.split('; ').find((d) => d.startsWith(name + ' ')) || '').slice(name.length + 1);
  ok(directive('connect-src') === "'self' https://gibs.earthdata.nasa.gov", 'connect-src is the origin and NASA GIBS, no map host', directive('connect-src'));
  ok(directive('img-src') === "'self' data: blob: https://gibs.earthdata.nasa.gov", 'img-src is the origin, data:, blob: and NASA GIBS', directive('img-src'));
  const origins = [...new Set(csp.match(/https:\/\/[^\s;]+/g) || [])].sort();
  ok(origins.join() === 'https://gibs.earthdata.nasa.gov,https://open.spotify.com', 'the CSP names two origins: NASA GIBS and the Spotify player', origins.join());

  // The base map is the site's own: one style, its glyphs and one PMTiles file, all under the origin.
  const styleText = fs.readFileSync(path.join(DIST, 'map/style.json'), 'utf8');
  const style = JSON.parse(styleText);
  ok(!/https?:/.test(styleText), 'the map style names no host');
  ok(Object.keys(style.sources).length === 1 && style.sources.basemap.url === 'pmtiles:///tiles/marola.pmtiles', 'its one source is the PMTiles file under /tiles/', JSON.stringify(style.sources));
  ok(style.glyphs === '/map/fonts/{fontstack}/{range}.pbf' && !('sprite' in style) && !styleText.includes('icon-image'), 'its glyphs are local and it needs no sprite');
  const stacks = new Set();
  JSON.stringify(style.layers, (k, v) => { if (typeof v === 'string' && /^noto-/.test(v)) stacks.add(v); return v; });
  ok(stacks.size >= 2 && [...stacks].every((f) => ['0-255', '256-511'].every((r) => fs.existsSync(path.join(DIST, 'map/fonts', f, r + '.pbf')))), 'every font stack the style names has its Latin glyphs in dist', [...stacks].join());
  ok(style.layers.every((l) => l.type === 'background' || l.source === 'basemap'), 'every layer reads that source');
  ok(style.layers.some((l) => l.type === 'symbol') && style.layers.findIndex((l) => l.type === 'symbol') > style.layers.findIndex((l) => l.id === 'water'), 'the labels come after the fills, where the satellite layer is inserted');
  ok(style.layers.some((l) => l.id === 'landuse_beach') && style.layers.some((l) => l.id === 'pois_beach'), 'the style draws the sand and names the beaches');
  ok(fs.existsSync(path.join(DIST, 'vendor/pmtiles/pmtiles.mjs')) && fs.existsSync(path.join(DIST, 'vendor/pmtiles/LICENSE.pmtiles')), 'the PMTiles library is vendored with its licence');

  const words = [['innerHTML', /innerHTML/], ['outerHTML', /outerHTML/], ['setHTML', /setHTML/], ['insertAdjacentHTML', /insertAdjacentHTML/],
    ['document.write', /document\.write/], ['eval(', /\beval\(/], ['new Function', /new Function/]];
  for (const f of ['maplibre_ffi.mjs', 'flow_layer_ffi.mjs']) {
    const src = read('front/js/' + f);
    ok(src.split('\n').length - 1 < 250, f + ' is under 250 lines', src.split('\n').length - 1);
    for (const [w, re] of words) ok(!re.test(src), f + ' never uses ' + w);
  }
  const tree = walk(path.join(ROOT, 'front/src'), () => false).concat(walk(path.join(ROOT, 'front/js'), () => false), path.join(ROOT, 'front/ports.js'));
  const text = tree.map((p) => fs.readFileSync(p, 'utf8')).join('\n');
  ok(tree.length > 40, 'the source scan saw the Elm sources', tree.length);
  for (const [w, re] of words) ok(!re.test(text), 'front/ never uses ' + w);
  // Elm's runtime names innerHTML only to refuse it (virtual-dom turns an innerHTML property into a no-op).
  const compiled = bundle().map((p) => fs.readFileSync(p, 'utf8')).join('\n');
  for (const [w, re] of words.filter(([w]) => w !== 'innerHTML' && w !== 'outerHTML')) ok(!re.test(compiled), 'the bundle never uses ' + w);
  const all = compiled + html;
  ok(!/pk\.eyJ[\w-]+/.test(all), 'no Mapbox public token in the built output');
  ok(!/api\.mapbox\.com|access_token/i.test(all), 'no Mapbox API host or access_token in the built output');
}

// ---- the DOM stub: only what Elm's virtual-dom, ports.js and the FFI touch ----------------------------------------------
class Node_ {
  constructor(nodeType) { this.nodeType = nodeType; this.parentNode = null; this.childNodes = []; this.listeners = {}; }
  get firstChild() { return this.childNodes[0] || null; }
  get nextSibling() { const p = this.parentNode; return p ? p.childNodes[p.childNodes.indexOf(this) + 1] || null : null; }
  get textContent() { return this.nodeType === 1 || this.nodeType === 11 ? this.childNodes.map((c) => c.textContent).join('') : this.data; }
  // Strict like a browser: a reference that is not a child throws, so a reconciler bug cannot pass quietly.
  insertBefore(n, ref) {
    if (n.nodeType === 11) { for (const c of [...n.childNodes]) this.insertBefore(c, ref); return n; }
    if (n.parentNode) n.parentNode.removeChild(n);
    const i = ref ? this.childNodes.indexOf(ref) : this.childNodes.length;
    if (i < 0) throw new Error('insertBefore: reference is not a child');
    this.childNodes.splice(i, 0, n); n.parentNode = this; return n;
  }
  appendChild(n) { return this.insertBefore(n, null); }
  removeChild(n) {
    const i = this.childNodes.indexOf(n);
    if (i < 0) throw new Error('removeChild: not a child');
    this.childNodes.splice(i, 1); n.parentNode = null; return n;
  }
  replaceChild(n, old) { this.insertBefore(n, old); this.removeChild(old); return old; }
  addEventListener(t, f) { (this.listeners[t] ||= []).push(f); }
  removeEventListener(t, f) { this.listeners[t] = (this.listeners[t] || []).filter((x) => x !== f); }
  dispatchEvent(ev) {
    Object.defineProperty(ev, 'target', { value: this, configurable: true });
    for (let n = this; n; n = n.parentNode) {
      Object.defineProperty(ev, 'currentTarget', { value: n, configurable: true });
      for (const f of [...(n.listeners[ev.type] || [])]) f.call(n, ev);
      if (!ev.bubbles || ev.cancelBubble) break;
    }
    return !ev.defaultPrevented;
  }
}
class Text_ extends Node_ {
  constructor(data, type = 3) { super(type); this.data = data; }
  get length() { return this.data.length; }
  replaceData(offset, count, text) { this.data = this.data.slice(0, offset) + text + this.data.slice(offset + count); }
}
class Fragment_ extends Node_ { constructor() { super(11); } }
class HTMLElement_ extends Node_ {
  constructor(ns, tag) { super(1); this.namespaceURI = ns; this.localName = tag; this.attrs = new Map(); }
  get tagName() { return this.localName.toUpperCase(); }
  // Elm reads the start node's attributes once, to diff its first view against them.
  get attributes() { return [...this.attrs].map(([name, value]) => ({ name, value })); }
  getAttribute(n) { return this.attrs.has(n) ? this.attrs.get(n) : null; }
  setAttribute(n, v) { this.attrs.set(n, String(v)); }
  removeAttribute(n) { this.attrs.delete(n); }
  hasAttribute(n) { return this.attrs.has(n); }
  // `disabled` is a reflected property in a browser: Elm sets the property, the page reads the attribute.
  get disabled() { return this.attrs.has('disabled'); }
  set disabled(on) { if (on) this.attrs.set('disabled', ''); else this.attrs.delete('disabled'); }
  focus() { document.activeElement = this; }
}
const HTML_NS = 'http://www.w3.org/1999/xhtml';
const body = new HTMLElement_(HTML_NS, 'body');
const app = new HTMLElement_(HTML_NS, 'div');
app.setAttribute('id', 'app');
body.appendChild(app);

// A selector subset: tag, #id, .class, [attr], [attr=value], descendant spaces. Enough for the view's markup.
function matches(el, compound) {
  const m = /^([\w-]*)((?:[#.][\w-]+|\[[^\]]+\])*)$/.exec(compound);
  if (!m) throw new Error('selector not supported: ' + compound);
  if (m[1] && el.localName !== m[1]) return false;
  for (const part of m[2].match(/[#.][\w-]+|\[[^\]]+\]/g) || []) {
    if (part[0] === '#') { if (el.getAttribute('id') !== part.slice(1)) return false; }
    else if (part[0] === '.') { if (!cls(el).includes(part.slice(1))) return false; }
    else {
      const eq = part.indexOf('='), k = part.slice(1, eq < 0 ? -1 : eq), a = el.getAttribute(k);
      if (a === null || (eq >= 0 && a !== part.slice(eq + 1, -1))) return false;
    }
  }
  return true;
}
function query(root, sel) {
  const chain = sel.trim().split(/\s+(?![^[]*\])/), out = [];
  const hit = (el) => {
    if (!matches(el, chain[chain.length - 1])) return false;
    let i = chain.length - 2;
    for (let a = el.parentNode; a && i >= 0; a = a.parentNode) if (a.nodeType === 1 && matches(a, chain[i])) i--;
    return i < 0;
  };
  (function visit(n) { for (const c of n.childNodes) if (c.nodeType === 1) { if (hit(c)) out.push(c); visit(c); } })(root);
  return out;
}
const cls = (el) => (el.getAttribute('class') || '').split(/\s+/);
const $ = (sel, root = app) => query(root, sel)[0] || null;
const $$ = (sel, root = app) => query(root, sel);
const shown = (el) => !!el && !el.hasAttribute('hidden');

const document = {
  body, documentElement: { lang: 'pt-BR' }, title: '', activeElement: null,
  createElement: (t) => new HTMLElement_(HTML_NS, t), createElementNS: (ns, t) => new HTMLElement_(ns, t),
  createTextNode: (d) => new Text_(d), createComment: (d) => new Text_(d, 8), createDocumentFragment: () => new Fragment_(),
  querySelector: (s) => query(body, s)[0] || null, getElementById: (id) => query(body, '#' + id)[0] || null,
};
// Real Event objects, so Elm's decoders see what a browser sends; fire() routes them through the stub's bubbling.
function fire(el, type, props = {}) {
  const ev = Object.assign(new Event(type, { bubbles: type !== 'pointerenter' && type !== 'pointerleave', cancelable: true }), props);
  el.dispatchEvent(ev);
  return ev;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(pred, label) {
  for (let i = 0; i < 600; i++) { if (pred()) return; await sleep(5); }
  throw new Error('timed out waiting for ' + label);
}
const click = async (el) => { fire(el, 'click'); await sleep(40); };

// ---- the MapLibre stub: every call recorded; the data: module below re-exports it ------------------------------
const ml = { maps: [], markers: [], popups: [], controls: [], workerUrl: null, mode: 'load', protocols: {}, protocolOpts: null };
class Emitter {
  constructor() { this.handlers = []; }
  on(ev, a, b) { this.handlers.push({ ev, layer: b ? a : null, fn: b || a }); return this; }
  once(ev, fn) { return this.on(ev, fn); }
  off(ev, fn) { this.handlers = this.handlers.filter((h) => h.fn !== fn); return this; }
  emit(ev, payload) { for (const h of [...this.handlers]) if (h.ev === ev) h.fn(payload); }
}
class MapStub extends Emitter {
  constructor(opts) {
    super();
    Object.assign(this, { opts, calls: [], sources: {}, layers: [], loaded: false, hits: [] });
    ml.maps.push(this);
    // The FFI wires its handlers right after the constructor, so events go out on the next tick, as MapLibre's do.
    // A tile the sparse file does not hold is an error MapLibre reports and the page must ignore, before load too.
    // 'error' is the tiles file missing: MapLibre reports the source and then fires load all the same.
    setTimeout(() => {
      this.emit('error', { error: new Error('Tile not found.'), tile: {}, sourceId: 'basemap' });
      if (ml.mode === 'error') this.emit('error', { error: new Error('Bad response code: 404'), sourceId: 'basemap' });
      this.loaded = true; this.emit('load');
    }, 0);
  }
  rec(name, ...args) { this.calls.push({ name, args }); }
  addControl(c) { this.rec('addControl', c); }
  addSource(id, spec) { this.rec('addSource', id, spec); this.sources[id] = { spec, data: spec.data, setData: (d) => { this.rec('setData', id, d); this.sources[id].data = d; } }; }
  addLayer(l, before) { this.rec('addLayer', l, before); this.layers.push(l); }
  getSource(id) { return this.sources[id]; }
  getLayer(id) { return this.layers.find((l) => l.id === id); }
  removeLayer(id) { this.rec('removeLayer', id); this.layers = this.layers.filter((l) => l.id !== id); }
  removeSource(id) { this.rec('removeSource', id); delete this.sources[id]; }
  getStyle() { return { layers: [{ id: 'labels', type: 'symbol' }] }; }
  getCanvas() { return { style: {} }; }
  queryRenderedFeatures(point, opts) { this.rec('queryRenderedFeatures', point, opts); return this.hits; }
  setLayoutProperty(...a) { this.rec('setLayoutProperty', ...a); }
  setPaintProperty(...a) { this.rec('setPaintProperty', ...a); }
  setFilter(...a) { this.rec('setFilter', ...a); }
  jumpTo(...a) { this.rec('jumpTo', ...a); }
  panTo(...a) { this.rec('panTo', ...a); }
  fitBounds(...a) { this.rec('fitBounds', ...a); }
  setMinZoom(...a) { this.rec('setMinZoom', ...a); }
  triggerRepaint() { this.rec('triggerRepaint'); }
  remove() { this.rec('remove'); }
}
class MarkerStub {
  constructor(opts) { this.opts = opts; this.el = opts.element; this.removed = false; ml.markers.push(this); }
  setLngLat(ll) { this.lngLat = ll; return this; }
  addTo(map) { this.map = map; return this; }
  remove() { this.removed = true; return this; }
}
class PopupStub {
  constructor(opts) { this.opts = opts; this.open = false; ml.popups.push(this); }
  setLngLat(ll) { this.lngLat = ll; return this; }
  setDOMContent(node) { this.content = node; return this; }
  addTo() { this.open = true; return this; }
  remove() { this.open = false; return this; }
}
globalThis.__ml = { Map: MapStub, Marker: MarkerStub, Popup: PopupStub,
  AttributionControl: class { constructor(o) { this.kind = 'attribution'; this.opts = o; ml.controls.push(this); } },
  NavigationControl: class { constructor(o) { this.kind = 'navigation'; this.opts = o; ml.controls.push(this); } },
  setWorkerUrl: (u) => { ml.workerUrl = u; }, addProtocol: (name, fn) => { ml.protocols[name] = fn; },
  Protocol: class { constructor(o) { ml.protocolOpts = o; this.tile = () => {}; } } };
// The loader hook runs on its own thread, so the module it serves only re-exports what this thread built.
const STUB_MODULE = 'const m = globalThis.__ml; export const { Map, Marker, Popup, AttributionControl, NavigationControl, setWorkerUrl, addProtocol } = m;';
const PMTILES_MODULE = 'export const Protocol = globalThis.__ml.Protocol;';
const stubUrl = (code) => JSON.stringify('data:text/javascript,' + encodeURIComponent(code));
const HOOK = `export async function resolve(s, c, next) { if (s === '/vendor/maplibre/maplibre-gl.mjs') return { url: ${stubUrl(STUB_MODULE)}, shortCircuit: true }; if (s === '/vendor/pmtiles/pmtiles.mjs') return { url: ${stubUrl(PMTILES_MODULE)}, shortCircuit: true }; return next(s, c); }`;

// ---- browser globals per scenario ----------------------------------------------------------------------------
const BASE = 'http://127.0.0.1:8000/';
const fetched = [], raw = [], urls = [], store = new Map();
function installGlobals(search, overrides) {
  const def = (k, value) => Object.defineProperty(globalThis, k, { value, configurable: true, writable: true });
  def('document', document); def('HTMLElement', HTMLElement_);
  def('window', { requestAnimationFrame: (f) => setTimeout(f, 0), alert: (t) => { ml.alerts = (ml.alerts || []).concat(t); },
    addEventListener: () => {}, removeEventListener: () => {} });
  def('requestAnimationFrame', (f) => setTimeout(f, 0));
  def('navigator', { languages: ['pt-BR'] });
  def('location', { href: BASE + search, pathname: '/', search });
  def('history', { replaceState: (_s, _t, url) => urls.push(url) });
  def('localStorage', { getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)) });
  def('matchMedia', () => ({ matches: false }));
  // elm/http's transport: open, send, then one "load" with the status, the headers and the text.
  const serve = (target) => {
    raw.push(target);
    const url = new URL(target, BASE);
    fetched.push(url);
    const rel = decodeURIComponent(url.pathname.slice(1));
    const hit = overrides[rel];
    const file = path.join(DIST, rel);
    if (hit === 404 || (hit === undefined && !(file.startsWith(DIST) && fs.existsSync(file) && fs.statSync(file).isFile()))) return { url, status: 404, body: '' };
    return { url, status: 200, body: hit === undefined ? fs.readFileSync(file, 'utf8') : JSON.stringify(hit) };
  };
  def('XMLHttpRequest', class {
    constructor() { this.on = {}; this.status = 0; this.statusText = ''; this.response = null; this.head = ''; }
    addEventListener(kind, fn) { this.on[kind] = fn; }
    open(_method, url) { this.target = url; }
    setRequestHeader() {}
    getAllResponseHeaders() { return this.head; }
    send() {
      setTimeout(() => {
        const r = serve(this.target);
        Object.assign(this, { status: r.status, response: r.body, responseText: r.body, responseURL: String(r.url) });
        this.head = r.status === 200 ? 'content-type: application/json\r\n' : '';
        if (this.on.load) this.on.load();
      }, 0);
    }
  });
}
const lastUrl = () => new URL(urls[urls.length - 1], BASE);
const live = () => ml.markers.filter((m) => !m.removed);
const beachMarkers = () => live().filter((m) => cls(m.el).includes('wave'));
const markerOf = (name) => live().find((m) => m.el.getAttribute('aria-label') === name);
const rows = () => $$('li[data-name]').map((li) => li.getAttribute('data-name'));
const latestFilter = (map, id) => map.calls.filter((c) => c.name === 'setFilter' && c.args[0] === id).pop();
const trailFile = (area) => distJson(`data/trails/${area}.json`);
const routesOf = (t) => t.bairros.flatMap((b) => b.trails);
const trailCollection = (map) => map.sources.trails && map.sources.trails.data;
const dayFile = (area) => 'data/' + area + '/' + distJson(`data/${area}/latest.json`).days[0].file;
const bandOf = (b) => (b.water.unfit || b.best.score <= 0 ? 'c0' : b.best.score >= 70 ? 'c70' : b.best.score >= 40 ? 'c40' : 'c1');

async function openTrailPanel() { await click($('button[data-panel=trails]')); }

// ---- scenarios ---------------------------------------------------------------------------------------------------
async function floripa() {
  const board = distJson(dayFile('floripa')), map = ml.maps[0];
  const byScore = [...board.beaches].sort((a, b) => b.best.score - a.best.score);
  ok(ml.maps.length === 1 && map.opts.style === '/map/style.json', "the map starts on the site's own style", map.opts.style);
  ok(typeof ml.protocols.pmtiles === 'function' && ml.protocolOpts && ml.protocolOpts.errorOnMissingTile === true, 'pmtiles:// is registered, and a missing tile is an error (so its ancestor is drawn)');
  const attribution = ml.controls.find((c) => c.kind === 'attribution');
  const credits = attribution ? attribution.opts.customAttribution : [];
  ok(credits.some((a) => a.includes('© OpenStreetMap') && a.includes('https://www.openstreetmap.org/copyright')), 'the attribution credits OpenStreetMap with its copyright link');
  ok(credits.some((a) => a.includes('Protomaps') && a.includes('https://protomaps.com')), 'and Protomaps', credits.join());
  ok(credits.some((a) => a.includes('MapLibre') && a.includes('https://maplibre.org')) && credits.length === 3, 'and MapLibre, and nobody else', credits.join());
  ok(ml.controls.some((c) => c.kind === 'navigation') && map.opts.attributionControl === false, 'navigation control added, default attribution off');
  // Closing the emergency panel gives focus back to its button (Browser.Dom.focus, after the next frame).
  await click($('#sos'));
  await click($('#sos-close'));
  await sleep(40);
  ok(document.activeElement && document.activeElement.getAttribute('id') === 'sos', 'closing the emergency panel focuses its button again', document.activeElement && document.activeElement.getAttribute('id'));
  ok(ml.workerUrl === '/vendor/maplibre/maplibre-gl-worker.mjs', 'the worker is the vendored one', ml.workerUrl);
  ok(map.calls.some((c) => c.name === 'fitBounds'), 'the first board fits the map to the beaches');
  ok(document.documentElement.lang === 'pt-BR' && $('a[href=news.html]').textContent === 'notícias', 'default language is pt-BR');
  ok(beachMarkers().length === 2 && live().length === 2, 'one marker per beach, no water points yet', live().length);
  ok(live().every((m) => cls(m.el).includes('wave')), 'beach marker nodes carry class wave');
  const best = markerOf(byScore[0].name);
  ok(best && $('circle.dot', best.el).getAttribute('class') === 'dot f-' + bandOf(byScore[0]), 'the best beach dot has its band class', byScore[0].best.score);
  ok(markerOf(byScore[1].name) && $('circle.dot', markerOf(byScore[1].name).el).getAttribute('class') === 'dot f-' + bandOf(byScore[1]), 'the unfit beach dot is f-c0');
  fire(best.el, 'pointerenter');
  const tip = ml.popups[ml.popups.length - 1];
  ok(tip && tip.open && tip.opts.className === 'aspects', 'hovering a marker opens a popup with the aspects class');
  ok($('.head', tip.content) && $('.head', tip.content).textContent.startsWith(byScore[0].name), 'the tooltip .head starts with the beach name');
  ok($('.grid', tip.content), 'the tooltip has a .grid of readings');
  fire(best.el, 'pointerleave');
  ok(!tip.open, 'leaving the marker closes the popup');

  ok(!shown($('aside#list')) && $('#toggle-list').getAttribute('aria-expanded') === 'false', 'the list starts hidden');
  await click($('#toggle-list'));
  ok(shown($('aside#list')) && $('#toggle-list').getAttribute('aria-expanded') === 'true', 'the list button shows aside#list');
  ok(JSON.stringify(rows()) === JSON.stringify(byScore.map((b) => b.name)), 'list rows are in score order, best first', rows().join('|'));
  ok(!shown($('#card')), 'no card before a pick');
  await click($$('li[data-name]')[0]);
  ok(shown($('#card')) && $('#card h2').textContent === byScore[0].name, 'a list row opens the card of that beach');
  ok(lastUrl().searchParams.get('beach') === byScore[0].name, 'the URL carries beach=', lastUrl().search);
  ok(cls(markerOf(byScore[0].name).el).includes('selected'), 'the picked beach marker is drawn selected');
  ok(map.calls.some((c) => c.name === 'panTo'), 'picking from the list pans the map');
  await click($('#card .close'));
  ok(!shown($('#card')) && !lastUrl().searchParams.has('beach'), 'the close button hides the card and drops beach= from the URL');
  fire(markerOf(byScore[1].name).el, 'click');
  await sleep(40);
  ok(shown($('#card')) && $('#card h2').textContent === byScore[1].name, 'a marker click picks the beach', 'card h2 ' + ($('#card h2') && $('#card h2').textContent) + ', url ' + lastUrl().search);
  map.emit('click', { point: { x: 1, y: 1 } });
  await sleep(40);
  ok(!shown($('#card')), 'a click on the empty map closes the card');

  const layers = $$('button[data-layer]');
  ok(layers.length === 7, 'seven layer buttons', layers.length);
  const enabled = layers.filter((b) => !b.hasAttribute('disabled'));
  ok(enabled.length === 1 && enabled[0].getAttribute('data-layer') === 'water', 'only the water layer is enabled');
  ok(layers.every((b) => b.getAttribute('aria-pressed') === 'false'), 'no layer starts pressed');
  const before = live().length;
  await click(enabled[0]);
  ok($('button[data-layer=water]').getAttribute('aria-pressed') === 'true', 'pressing water sets aria-pressed');
  ok(lastUrl().searchParams.get('layer') === 'water', 'the URL carries layer=water');
  ok(cls($('main')).includes('layer-water'), 'main gets class layer-water');
  ok(before === 2 && live().length === 4 && live().filter((m) => cls(m.el).includes('wpoint')).length === 2, 'the water layer adds the sampling points', live().length);

  const feats = trailCollection(map).features, file = trailFile('floripa');
  ok(feats.length === routesOf(file).filter((r) => r.lines.some((l) => l.length > 1)).length && feats.length > 0, 'floripa trails reach the map as features', feats.length);
  await openTrailPanel();
  ok($$('[data-trail]').length === routesOf(file).length && $('.trail-foot').textContent.includes(String(file.ibge_municipality)), 'floripa panel lists its routes and the IBGE code');

  const hosts = new Set(fetched.map((u) => u.host));
  ok([...hosts].every((h) => h === '127.0.0.1:8000' || h === 'gibs.earthdata.nasa.gov'), 'every request stays on the origin or NASA GIBS', [...hosts].join());
  const paths = fetched.map((u) => u.pathname);
  ok(['/data/areas.json', '/i18n/en.json', '/i18n/pt-BR.json', '/data/floripa/latest.json', '/data/trails/floripa.json'].every((p) => paths.includes(p)), 'the page fetched catalogs, areas, latest and trails');
  ok(!JSON.stringify({ ...map.opts, container: null }).includes('pk.'), 'no token in the map options');
}

async function english() {
  ok(document.documentElement.lang === 'en', '?lang=en starts in English');
  ok($('a[href=news.html]').textContent === 'news' && $('button[lang=en]').getAttribute('aria-pressed') === 'true', 'English nav text and EN pressed');
  await click($('button[lang=pt-BR]'));
  ok($('a[href=news.html]').textContent === 'notícias', 'pressing PT-BR flips the nav to notícias');
  ok(store.get('marola.lang') === 'pt-BR', 'the choice is stored in localStorage marola.lang', store.get('marola.lang'));
  ok(lastUrl().searchParams.get('lang') === 'pt-BR' && document.documentElement.lang === 'pt-BR', 'the URL and <html lang> follow');
}

async function layerWater() {
  ok($('button[data-layer=water]').getAttribute('aria-pressed') === 'true', '?layer=water starts pressed');
  ok(cls($('main')).includes('layer-water') && live().length === 4, '?layer=water draws the sampling points from the start', live().length);
}

async function layerWind() {
  ok($$('button[data-layer]').every((b) => b.getAttribute('aria-pressed') === 'false'), '?layer=wind is ignored: nothing pressed');
  ok(!cls($('main')).includes('layer-water') && live().length === 2, '?layer=wind leaves the plain map', live().length);
}

async function rio() {
  const map = ml.maps[0], file = trailFile('rio'), routes = routesOf(file);
  const feats = trailCollection(map).features;
  ok(map.sources.trails.spec.promoteId === 'id' && trailCollection(map).type === 'FeatureCollection', 'trails go in as a FeatureCollection with promoteId');
  ok(feats.length === 113 && routes.filter((r) => r.lines.some((l) => l.length > 1)).length === 113, 'rio: 113 features', feats.length);
  ok(feats.every((f) => JSON.stringify(Object.keys(f.properties).sort()) === '["color","id","tip"]'), 'each feature has properties id, color, tip');
  ok(feats.every((f) => /^#[0-9a-f]{6}$/.test(f.properties.color) && typeof f.properties.id === 'number' && JSON.parse(f.properties.tip)), 'ids are numbers, colours hex, tips parse');
  ok(!shown($('#trails-panel')), 'the trails panel starts hidden');
  await openTrailPanel();
  ok(shown($('#trails-panel')) && !shown($('aside#list')), 'the panel button shows #trails-panel');
  ok($$('[data-trail]').length === 113 && $$('.trail-group').length === 17, 'rio panel: 113 buttons in 17 groups');
  ok($('.trail-foot').textContent.includes('3304557'), 'the panel footer names IBGE 3304557');
  const k = routes.findIndex((r) => r.osm_ways.length > 1);
  await click($(`button[data-trail=${k}]`));
  const card = $('#card');
  ok(shown(card) && card.getAttribute('class').includes('trail-card') && $('h2', card).textContent === routes[k].name, 'a trail button opens its card');
  const links = $$('a', card).filter((a) => a.getAttribute('href').startsWith('https://www.openstreetmap.org/way/'));
  ok(links.map((a) => a.getAttribute('href')).join() === routes[k].osm_ways.map((w) => 'https://www.openstreetmap.org/way/' + w).join(), 'the card links each OSM way');
  ok(links.every((a) => a.getAttribute('rel') === 'noopener' && a.getAttribute('target') === '_blank'), 'way links are rel=noopener');
  ok(JSON.stringify(latestFilter(map, 'trails-selected').args[1]) === JSON.stringify(['==', ['get', 'id'], k]), 'the map is told the selected trail', k);
  ok(map.calls.some((c) => c.name === 'fitBounds' && c.args[1].maxZoom === 15), 'picking a trail fits the map to it');
  const j = routes.findIndex((r, i) => i !== k && r.lines.some((l) => l.length > 1));
  map.hits = [{ properties: { id: j } }];
  map.emit('click', { point: { x: 3, y: 4 } });
  await sleep(40);
  ok($('#card h2').textContent === routes[j].name && latestFilter(map, 'trails-selected').args[1][2] === j, 'a map trail event selects that trail');
  await click($('#card .close'));
  ok(!shown($('#card')), 'closing the trail card hides it');
}

async function salvador() {
  const file = trailFile('salvador'), map = ml.maps[0];
  ok(trailCollection(map).features.length === 0, 'salvador: zero trail features');
  await openTrailPanel();
  ok(shown($('#trails-panel')) && $$('[data-trail]').length === 0, 'salvador panel lists no trail');
  ok($('.trail-note') && $('.trail-note').textContent === file.note, 'the panel shows the note of data/trails/salvador.json');
}

function fallbackBoard() {
  const board = distJson(dayFile('floripa'));
  // A hostile name must stay text everywhere the client puts it.
  board.beaches[1].name = '<img src=x onerror=alert(1)><script>boom()</script>';
  board.trails = [{ name: 'Trilha de teste', length_km: 1.2, difficulty: 'hiking', surface: null, near_beach: null, near_lake: null,
    geometry: [[-27.6, -48.5], [-27.61, -48.51], [-27.62, -48.52]] }];
  return board;
}
async function boardTrails() {
  const map = ml.maps[0], feats = trailCollection(map).features, bad = fallbackBoard().beaches[1].name;
  ok(fetched.some((u) => u.pathname === '/data/trails/floripa.json'), 'the trails file was asked for (and answered 404)');
  ok(feats.length === 1 && feats[0].properties.id === 0 && feats[0].geometry.coordinates[0].length === 3, 'a 404 falls back to the board trails', feats.length);
  await openTrailPanel();
  ok($$('[data-trail]').length === 1 && $$('.trail-group').length === 1, 'the fallback panel lists the board trail');
  const tree = [app, ...live().map((m) => m.el), ...ml.popups.map((p) => p.content).filter(Boolean)];
  const inject = () => tree.some((r) => $$('script', r).length + $$('img', r).length > 0);
  ok(!inject(), 'no <script> or <img> element exists in the page or the markers');
  ok(rows().includes(bad) && $$('li[data-name]').some((li) => li.textContent.includes(bad)), 'the hostile name is listed as literal text');
  ok(markerOf(bad) && markerOf(bad).el.getAttribute('aria-label') === bad, 'the hostile name is a marker label');
  fire(markerOf(bad).el, 'pointerenter');
  const tip = ml.popups[ml.popups.length - 1];
  ok($$('script', tip.content).length + $$('img', tip.content).length === 0 && $('.head', tip.content).textContent.startsWith(bad), 'its tooltip holds the name as text');
  await click($$('li[data-name]').find((li) => li.getAttribute('data-name') === bad));
  const h2 = $('#card h2');
  ok(h2.textContent === bad && h2.childNodes.every((n) => n.nodeType === 3), 'its card title is a single text node');
  ok(!inject() && $$('script').length === 0, 'still no injected element after the card');
}

async function styleFail() {
  await sleep(60);
  ok(shown($('#map-note')) && $('#map-note').textContent === distJson('i18n/pt-BR.json')['map.failed'], 'a missing tiles file shows #map-note with the pt-BR map.failed text, and the load that follows does not undo it');
  ok(!$('#flow') && $$('button[data-layer]').length === 0, 'the layer rail is not rendered');
  ok(shown($('aside#list')) && rows().length === 2, 'the beach list opens by itself');
  ok(ml.markers.length === 0 && !ml.maps[0].calls.some((c) => c.name === 'addSource'), 'nothing is drawn on the failed map');
}

// The slider is a range input whose value is a property, not an attribute: Elm sets it and the page reads it back.
async function slider() {
  const hour = $('#hour'), label = () => $('#hour-label').textContent, best = label();
  hour.value = '0'; fire(hour, 'input'); await sleep(40);
  ok(label() !== best, 'moving the slider to an hour changes its label', label());
  hour.value = '-1'; fire(hour, 'input'); await sleep(40);
  ok(label() === best, 'the slider back at -1 reads as it did before', label());
}

async function storageThrows() {
  ok(document.documentElement.lang === 'en', 'a storage that throws does not stop the page: ?lang=en starts in English');
  await click($('button[lang=pt-BR]'));
  ok($('a[href=news.html]').textContent === 'notícias' && document.documentElement.lang === 'pt-BR', 'picking PT-BR works when the storage throws');
}

async function nearDenied() {
  await click($('#near'));
  const text = distJson('i18n/pt-BR.json')['near.denied'];
  ok(ml.alerts && ml.alerts.length === 1 && ml.alerts[0] === text, 'a location that cannot be read is told with one alert', JSON.stringify(ml.alerts));
  ok($('#near').getAttribute('aria-pressed') === 'false', 'the near button stays off');
}

async function playlist() {
  const embed = 'https://open.spotify.com/embed/playlist/2hsuqvhCouatM8DtmKKl7U?theme=0';
  ok(!$('#player iframe') && $('#playlist').getAttribute('aria-pressed') === 'false', 'no Spotify iframe before the playlist button is pressed');
  await click($('#playlist'));
  const frame = $('#player iframe');
  ok(frame && frame.getAttribute('src') === embed, 'the playlist button opens the GREAT RESET embed', frame && frame.getAttribute('src'));
  ok($('#playlist').getAttribute('aria-pressed') === 'true', 'the playlist button reads as pressed while the player is open');
  const csp = /http-equiv="Content-Security-Policy" content="([^"]*)"/.exec(fs.readFileSync(path.join(DIST, 'index.html'), 'utf8'))[1];
  ok(/(^|; )frame-src https:\/\/open\.spotify\.com(;|$)/.test(csp), 'the CSP lets the page frame open.spotify.com and nothing else', csp);
  await click($('#playlist'));
  ok(!$('#player iframe'), 'pressing it again removes the iframe');
  const eye = $('a.piabrota');
  ok(eye && eye.getAttribute('href') === 'https://piabrota.art' && $('a.piabrota svg'), 'the piabrota eye is an inline svg linking to piabrota.art');
}

const SCENARIOS = {
  floripa: { search: '?area=floripa', run: floripa },
  english: { search: '?lang=en', run: english },
  'layer-water': { search: '?layer=water', run: layerWater },
  'layer-wind': { search: '?layer=wind', run: layerWind },
  rio: { search: '?area=rio', run: rio },
  salvador: { search: '?area=salvador', run: salvador },
  'board-trails': { search: '?area=floripa', run: boardTrails, overrides: () => ({ 'data/trails/floripa.json': 404, [dayFile('floripa')]: fallbackBoard() }) },
  'style-fail': { search: '', run: styleFail, mode: 'error' },
  slider: { search: '?area=floripa', run: slider },
  'storage-throws': { search: '?lang=en', run: storageThrows, setup: () => {
    const boom = () => { throw new Error('storage is off'); };
    Object.defineProperty(globalThis, 'localStorage', { value: { getItem: boom, setItem: boom }, configurable: true, writable: true });
  } },
  'near-denied': { search: '?area=floripa', run: nearDenied },
  playlist: { search: '?area=floripa', run: playlist },
};

async function child(name) {
  const sc = SCENARIOS[name];
  console.log('# ' + name);
  try {
    ml.mode = sc.mode || 'load';
    installGlobals(sc.search, sc.overrides ? sc.overrides() : {});
    if (sc.setup) sc.setup();
    require('node:module').register('data:text/javascript,' + encodeURIComponent(HOOK));
    await import(pathToFileURL(bundle()[0]).href);
    await sleep(100);
    // Every request starts with "./", so the page works from any path; the stub resolves it against the page.
    ok(fetched.length > 0 && raw.every((u) => u.startsWith('./')), 'the page makes its requests, and every URL starts with ./', raw.join());
    if (ml.mode === 'error') await until(() => shown($('#map-note')), '#map-note');
    else await until(() => ml.maps[0] && ml.maps[0].loaded && $('li[data-name]'), 'the board and the map');
    await sleep(60);
    await sc.run();
  } catch (e) { ok(false, name + ' ran to the end', e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e); }
  process.exit(0);
}

function parent() {
  console.log('# static');
  staticChecks();
  for (const name of Object.keys(SCENARIOS)) {
    const r = spawnSync(process.execPath, [__filename, '--scenario', name], { encoding: 'utf8', timeout: 60000 });
    process.stdout.write(r.stdout || '');
    const lines = (r.stdout || '').split('\n');
    total += lines.filter((l) => /^ {2}(ok {3}|FAIL )/.test(l)).length;
    fails += lines.filter((l) => l.startsWith('  FAIL ')).length;
    if (r.status !== 0) { ok(false, name + ' child exited cleanly', (r.stderr || 'status ' + r.status).trim().split('\n').slice(-3).join(' | ')); }
  }
  console.log(`front_check: ${total} assertions, ${fails} failed`);
  console.log('not checked: ' + NOT_CHECKED.join('; '));
  process.exit(fails ? 1 : 0);
}

if (process.argv[2] === '--scenario') child(process.argv[3]); else parent();
