/** Runs the built bundles in a stub DOM and a stub Mapbox GL: no browser, no network. */
import { buildSync } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
import { setImmediate as tick } from 'node:timers/promises';
import vm from 'node:vm';
import type { Board } from '../site/src/board.ts';

export const ROOT = path.resolve(import.meta.dirname, '..');
export const read = (rel: string): string => fs.readFileSync(path.join(ROOT, rel), 'utf8');
export const readJson = <T>(rel: string): T => JSON.parse(read(rel)) as T;
export const clone = <T>(x: T): T => structuredClone(x);

export const BOARD = readJson<Board>('site/fixtures/board.json');
// A board from before note_codes, frozen: deriving it from board.json would hide a schema change that breaks old boards.
export const BOARD_V1 = readJson<Board>('site/fixtures/board-schema1.json');
export const CATALOGS = { 'pt-BR': readJson<Record<string, string>>('site/i18n/pt-BR.json'), en: readJson<Record<string, string>>('site/i18n/en.json') };

export const PAGES = Object.fromEntries(
  fs
    .readdirSync(path.join(ROOT, 'site/static'))
    .filter((f) => f.endsWith('.html'))
    .map((f) => [f, read(`site/static/${f}`)]),
);
export const INDEX = PAGES['index.html'] ?? '';

const bundles = new Map<string, string>();
/** site/src/<entry>.ts as the page loads it, built in memory so a test never runs a stale site/static bundle. */
export function bundle(entry: string): string {
  let code = bundles.get(entry);
  if (code === undefined) {
    const out = buildSync({ entryPoints: [path.join(ROOT, 'site/src', `${entry}.ts`)], bundle: true, format: 'iife', target: 'es2020', write: false });
    code = out.outputFiles[0]?.text ?? '';
    bundles.set(entry, code);
  }
  return code;
}

// The bundles glue each number to its unit with a no-break space; needles are written as read, and each line icon
// is read as [name], so a needle names the icon it expects.
export const plain = (s: string): string => s.replace(/\u00a0/g, ' ').replace(/<svg class="ic ic-([a-z]+)"[\s\S]*?<\/svg>/g, '[$1]');

type Listener = (ev: Record<string, unknown>) => void;

export class El {
  innerHTML = '';
  textContent = '';
  hidden = false;
  disabled = false;
  value = '';
  max = '';
  title = '';
  className = '';
  dataset: Record<string, string> = {};
  attrs: Record<string, string> = {};
  children: El[] = [];
  listeners: Record<string, Listener[]> = {};
  style: Record<string, string> = {};
  found: Record<string, El[]> = {};
  private readonly cls = new Set<string>();
  readonly classList = {
    toggle: (c: string, on?: boolean): void => {
      if (on ?? !this.cls.has(c)) this.cls.add(c);
      else this.cls.delete(c);
    },
    add: (c: string): void => void this.cls.add(c),
    remove: (c: string): void => void this.cls.delete(c),
    contains: (c: string): boolean => this.cls.has(c),
  };
  readonly id: string;
  constructor(id: string) {
    this.id = id;
  }
  addEventListener(type: string, fn: Listener): void {
    (this.listeners[type] ??= []).push(fn);
  }
  fire(type: string, ev: Record<string, unknown> = {}): void {
    for (const fn of this.listeners[type] ?? []) fn({ stopPropagation() {}, preventDefault() {}, ...ev });
  }
  click(target: El = this): void {
    this.fire('click', { target });
  }
  setAttribute(k: string, v: unknown): void {
    this.attrs[k] = String(v);
  }
  getAttribute(k: string): string | null {
    return this.attrs[k] ?? null;
  }
  querySelector(): El {
    return new El('anon');
  }
  querySelectorAll(sel: string): El[] {
    return this.found[sel] ?? [];
  }
  closest(): this {
    return this;
  }
  appendChild(c: El): void {
    this.children.push(c);
  }
}

const IDS = ['area', 'days', 'near', 'sound', 'toggle-list', 'hourbar', 'hour', 'hour-label', 'list', 'card', 'footer', 'status', 'flow', 'flowkeys', 'map-note', 'map', 'lang'];
const LAYER_KEYS = ['wind', 'waves', 'water', 'clouds', 'sst', 'anomaly', 'elnino'];

// #flow's layer buttons, the toggles and their keys, as index.html has them.
function flowPanel(flow: El, keys: El): void {
  flow.found['button[data-layer]'] = LAYER_KEYS.map((k) => Object.assign(new El(`flow-${k}`), { dataset: { layer: k } }));
  flow.found['button[data-toggle]'] = ['beaches', 'trails'].map((k) => Object.assign(new El(`flow-${k}`), { dataset: { toggle: k } }));
  keys.found['[data-when]'] = ['clouds', 'sst', 'anomaly'].map((k) => Object.assign(new El(`when-${k}`), { dataset: { when: k } }));
  keys.found['[data-key]'] = LAYER_KEYS.map((k) => Object.assign(new El(`key-${k}`), { dataset: { key: k } }));
}

// --- stub Mapbox GL: a custom layer is added but never handed a WebGL context
export class Popup {
  readonly kind = 'popup';
  html = '';
  open = false;
  lngLat: unknown;
  readonly M: MapboxStub;
  readonly options: Record<string, unknown>;
  constructor(M: MapboxStub, options: Record<string, unknown> = {}) {
    this.M = M;
    this.options = options;
    M.created.push(this);
  }
  setLngLat(ll: unknown): this {
    this.lngLat = ll;
    return this;
  }
  setHTML(h: string): this {
    this.html = h;
    return this;
  }
  addTo(): this {
    this.open = true;
    this.M.lastShown = this;
    return this;
  }
  remove(): this {
    this.open = false;
    return this;
  }
}

export class Marker {
  readonly kind = 'marker';
  readonly element: El;
  added = false;
  lngLat: [number, number] = [0, 0];
  readonly M: MapboxStub;
  readonly options: { element: El; anchor?: string };
  constructor(M: MapboxStub, options: { element: El; anchor?: string }) {
    this.M = M;
    this.options = options;
    this.element = options.element;
    M.created.push(this);
  }
  setLngLat(ll: [number, number]): this {
    this.lngLat = ll;
    return this;
  }
  addTo(): this {
    this.added = true;
    return this;
  }
  remove(): this {
    this.added = false;
    return this;
  }
}

interface LayerEntry {
  layer: { id: string; type: string; layout?: Record<string, unknown>; [k: string]: unknown };
  before: string | undefined;
}

class MapStub {
  handlers: Record<string, ((e: Record<string, unknown>) => void)[]> = {};
  layers: LayerEntry[] = [];
  sources: Record<string, { src: Record<string, unknown>; data: unknown; setData(d: unknown): void }> = {};
  controls: unknown[] = [];
  touchZoomRotate = { disableRotation() {} };
  jumped: unknown;
  fitted: [[[number, number], [number, number]], unknown] | null = null;
  minZoom = 3;
  panned: unknown;
  readonly options: Record<string, unknown>;
  constructor(M: MapboxStub, options: Record<string, unknown>) {
    this.options = options;
    M.maps.push(this);
    void Promise.resolve().then(() => {
      const fire = (k: string, e: Record<string, unknown>): void => {
        for (const fn of this.handlers[k] ?? []) fn(e);
      };
      if (M.styleStatus) fire('error', { error: { status: M.styleStatus } });
      else fire('load', {});
    });
  }
  on(ev: string, a: unknown, b?: unknown): this {
    const k = b ? `${ev}:${String(a)}` : ev;
    (this.handlers[k] ??= []).push((b ?? a) as (e: Record<string, unknown>) => void);
    return this;
  }
  addControl(c: unknown): this {
    this.controls.push(c);
    return this;
  }
  jumpTo(o: unknown): this {
    this.jumped = o;
    return this;
  }
  fitBounds(b: [[number, number], [number, number]], o: unknown): this {
    this.fitted = [b, o];
    return this;
  }
  setMinZoom(z: number): this {
    this.minZoom = z;
    return this;
  }
  panTo(c: unknown): this {
    this.panned = c;
    return this;
  }
  resize(): this {
    return this;
  }
  getStyle(): { layers: { id: string; type: string }[] } {
    return { layers: [{ id: 'water', type: 'fill' }, { id: 'road', type: 'line' }, { id: 'place-label', type: 'symbol' }] };
  }
  addSource(id: string, src: Record<string, unknown>): void {
    this.sources[id] = {
      src,
      data: src.data,
      setData(d) {
        this.data = d;
      },
    };
  }
  getSource(id: string): MapStub['sources'][string] | undefined {
    return this.sources[id];
  }
  removeSource(id: string): void {
    // eslint-disable-next-line @typescript-eslint/no-dynamic-delete -- a stub of a keyed store
    delete this.sources[id];
  }
  addLayer(layer: LayerEntry['layer'], before?: string): void {
    this.layers.push({ layer, before });
  }
  getLayer(id: string): LayerEntry['layer'] | undefined {
    return this.layers.find((x) => x.layer.id === id)?.layer;
  }
  removeLayer(id: string): void {
    this.layers = this.layers.filter((x) => x.layer.id !== id);
  }
  setLayoutProperty(id: string, k: string, v: unknown): void {
    const l = this.getLayer(id);
    if (l) (l.layout ??= {})[k] = v;
  }
  getCanvas(): { style: Record<string, string>; clientWidth: number; clientHeight: number } {
    return { style: {}, clientWidth: 800, clientHeight: 600 };
  }
  getZoom(): number {
    return 10;
  }
  triggerRepaint(): void {
    /* no frames in a stub */
  }
}

export class MapboxStub {
  created: (Popup | Marker)[] = [];
  maps: MapStub[] = [];
  lastShown: Popup | null = null;
  styleStatus: number | null = null;
  readonly api: Record<string, unknown>;
  constructor() {
    const M = this as MapboxStub;
    this.api = {
      version: '3.32.0',
      accessToken: '',
      workerUrl: '',
      Map: class extends MapStub {
        constructor(o: Record<string, unknown>) {
          super(M, o);
        }
      },
      Marker: class extends Marker {
        constructor(o: { element: El; anchor?: string }) {
          super(M, o);
        }
      },
      Popup: class extends Popup {
        constructor(o?: Record<string, unknown>) {
          super(M, o);
        }
      },
      NavigationControl: class {
        readonly options: unknown;
        constructor(options: unknown) {
          this.options = options;
        }
      },
    };
  }
}

// --- an AudioContext that records its node graph, so a test can assert the sound was built
interface AudioNodeStub {
  kind: string;
  target?: unknown;
  started?: boolean;
  loop?: boolean;
  loopStart?: number;
  loopEnd?: number;
  gain?: { value: number; cancelScheduledValues(): void; setTargetAtTime(v: number): void };
  connect(target: unknown): AudioNodeStub;
  start?: () => void;
}
function audioStub(): { ctor: () => unknown; gains: AudioNodeStub[]; sources: AudioNodeStub[] } {
  const gains: AudioNodeStub[] = [];
  const sources: AudioNodeStub[] = [];
  const node = (kind: string): AudioNodeStub => {
    const n: AudioNodeStub = {
      kind,
      connect(target) {
        n.target = target;
        return n;
      },
    };
    if (kind === 'gain')
      n.gain = {
        value: 0,
        cancelScheduledValues() {},
        setTargetAtTime(v) {
          if (n.gain) n.gain.value = v;
        },
      };
    else
      n.start = () => {
        n.started = true;
      };
    return n;
  };
  // a function, not an arrow: the page calls `new AudioContext()`
  function ctor(): unknown {
    return {
    state: 'running',
    currentTime: 0,
    destination: {},
    createBufferSource: () => {
      const b = node('bufferSource');
      sources.push(b);
      return b;
    },
    decodeAudioData: (bytes: unknown, ok: (b: unknown) => void) => {
      ok({ duration: 118, bytes });
    },
    createGain: () => {
      const g = node('gain');
      gains.push(g);
      return g;
    },
    resume() {},
    close() {},
    };
  }
  return { ctor, gains, sources };
}

function stubStorage(sandbox: Record<string, unknown>, store: Record<string, string>, throws?: boolean): void {
  if (throws)
    Object.defineProperty(sandbox, 'localStorage', {
      get() {
        throw new Error('SecurityError');
      },
    });
  else
    sandbox.localStorage = {
      getItem: (k: string) => store[k] ?? null,
      setItem: (k: string, v: unknown) => {
        store[k] = String(v);
      },
    };
}

interface PageOpts {
  search?: string;
  languages?: string[];
  store?: Record<string, string>;
  storeThrows?: boolean;
  geolocation?: { getCurrentPosition(ok: (p: { coords: { latitude: number; longitude: number } }) => void, no: (e: unknown) => void): void };
  noBoard?: boolean;
  secondArea?: boolean;
  token?: string;
  styleStatus?: number;
  disabled?: string[];
}

const COLOURS: Readonly<Record<string, string>> = { '--c70': '#2a9d4b', '--c40': '#e0a800', '--c1': '#e07a00', '--c0': '#c0392b', '--cna': '#999999' };


/** The app bundle against a board, in a fresh vm context. */
export async function runPage(board: Board, opts: PageOpts = {}) {
  const els = Object.fromEntries(IDS.map((id) => [id, new El(id)])) as Record<string, El>;
  const el = (id: string): El => els[id] ?? new El(id);
  const files: Record<string, unknown> = {
    'data/areas.json': { areas: [{ id: 'fixture', name: 'Fixture Bay', lat: -27.6, lon: -48.5 }, ...(opts.secondArea ? [{ id: 'other', name: 'Other Bay', lat: -27.6, lon: -48.5 }] : [])] },
  };
  for (const a of ['fixture', 'other']) {
    files[`data/${a}/latest.json`] = { days: [{ day: board.day, file: `${board.day}.json` }] };
    if (!opts.noBoard) files[`data/${a}/${board.day}.json`] = board;
  }
  const M = new MapboxStub();
  if (opts.styleStatus) M.styleStatus = opts.styleStatus;
  flowPanel(el('flow'), el('flowkeys'));
  for (const k of opts.disabled ?? [])
    for (const b of [...el('flow').querySelectorAll('button[data-layer]'), ...el('flow').querySelectorAll('button[data-toggle]')])
      if (b.dataset.layer === k || b.dataset.toggle === k) b.disabled = true;
  const errors: string[] = [];
  const alerts: string[] = [];
  const fetched: string[] = [];
  const audio = audioStub();
  const search = opts.search ?? '';
  const documentElement: { lang?: string } = {};
  const location = { href: `https://example.test/${search}`, search };
  const sandbox: Record<string, unknown> = {
    console: { error: (...a: unknown[]) => errors.push(a.map(String).join(' ')), log() {} },
    document: {
      getElementById: (id: string) => els[id] ?? null,
      querySelectorAll: () => [],
      documentElement,
      createElement: (tag: string) => new El(tag),
      addEventListener() {},
      hidden: false,
    },
    getComputedStyle: () => ({ getPropertyValue: (n: string) => COLOURS[n] ?? '' }),
    matchMedia: () => ({ matches: false }),
    fetch: (p: string) => {
      fetched.push(p);
      if (p === 'vendor/sounds/waves.mp3') return Promise.resolve({ ok: true, status: 200, arrayBuffer: () => Promise.resolve(new ArrayBuffer(8)) });
      return Promise.resolve(
        p in files
          ? { ok: true, status: 200, json: () => Promise.resolve(clone(files[p])) }
          : { ok: false, status: 404, json: () => Promise.reject(new Error('404')) },
      );
    },
    location,
    history: {
      replaceState(_s: unknown, _t: unknown, u: unknown) {
        location.href = String(u);
        location.search = new URL(location.href).search;
      },
    },
    navigator: { languages: opts.languages ?? [], ...(opts.geolocation ? { geolocation: opts.geolocation } : {}) },
    alert: (m: unknown) => alerts.push(String(m)),
    AudioContext: audio.ctor,
    URL,
    URLSearchParams,
    mapboxgl: M.api,
    MAROLA_MAPBOX: { token: opts.token ?? 'pk.test', style: '' },
  };
  stubStorage(sandbox, opts.store ?? {}, opts.storeThrows);
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(bundle('app'), sandbox, { filename: 'app.js' });
  // fail() logs through console.error, so an error ends the wait as a rendered list does.
  for (let i = 0; i < 200 && !el('list').innerHTML && !errors.length; i++) await tick();
  for (let i = 0; i < 5; i++) await tick(); // the map's load event
  return { els, el, M, map: M.maps[0], errors, alerts, fetched, audio, documentElement, location };
}
export type Page = Awaited<ReturnType<typeof runPage>>;

export function pickLang(r: Page, lang: string): void {
  const btn = new El(`lang-${lang}`);
  btn.attrs['data-lang'] = lang;
  r.el('lang').click(btn);
}

// --- a page's markup as stub elements, one per start tag
interface Node {
  tag: string;
  attrs: Record<string, string>;
  textContent: string | null;
  listeners: Record<string, ((e: { target: Node | undefined }) => void)[]>;
  getAttribute(k: string): string | null;
  setAttribute(k: string, v: unknown): void;
  addEventListener(type: string, fn: (e: { target: Node | undefined }) => void): void;
  closest(sel: string): Node | null;
}

function pageDom(html: string) {
  const nodes: Node[] = [];
  for (const m of html.matchAll(/<([a-z][a-z0-9]*)\b([^>]*)>/g)) {
    const attrs: Record<string, string> = {};
    for (const a of (m[2] ?? '').matchAll(/([\w:-]+)="([^"]*)"/g)) attrs[a[1] ?? ''] = a[2] ?? '';
    const node: Node = {
      tag: m[1] ?? '',
      attrs,
      textContent: null,
      listeners: {},
      getAttribute: (k) => attrs[k] ?? null,
      setAttribute: (k, v) => {
        attrs[k] = String(v);
      },
      addEventListener: (type, fn) => {
        (node.listeners[type] ??= []).push(fn);
      },
      closest: (sel) => (sel === 'button[data-lang]' && 'data-lang' in attrs ? node : null),
    };
    nodes.push(node);
  }
  const documentElement = { lang: /<html lang="([^"]*)"/.exec(html)?.[1] };
  return {
    nodes,
    documentElement,
    getElementById: (id: string) => nodes.find((n) => n.attrs.id === id) ?? null,
    querySelectorAll(sel: string): Node[] {
      if (sel === '#lang button[data-lang]') return nodes.filter((n) => 'data-lang' in n.attrs);
      const attr = /^\[([\w-]+)\]$/.exec(sel)?.[1];
      if (!attr) throw new Error(`pageDom: unsupported selector ${sel}`);
      return nodes.filter((n) => attr in n.attrs);
    },
  };
}

/** The ui bundle (what about.html and support.html load) against a page's markup. */
export function runUi(html: string, opts: { search?: string; languages?: string[]; store?: Record<string, string>; storeThrows?: boolean } = {}) {
  const document = pageDom(html);
  const store = opts.store ?? {};
  const urls: string[] = [];
  const search = opts.search ?? '';
  const sandbox: Record<string, unknown> = {
    document,
    location: { href: `https://example.test/${search}`, search },
    history: {
      replaceState(_s: unknown, _t: unknown, u: unknown) {
        urls.push(String(u));
      },
    },
    navigator: { languages: opts.languages ?? [] },
    URL,
    URLSearchParams,
  };
  stubStorage(sandbox, store, opts.storeThrows);
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(bundle('ui'), sandbox, { filename: 'ui.js' });
  const langBtn = (code: string): Node | undefined => document.nodes.find((n) => n.attrs['data-lang'] === code);
  const click = (code: string): void => {
    for (const fn of document.getElementById('lang')?.listeners.click ?? []) fn({ target: langBtn(code) });
  };
  return { document, store, urls, langBtn, click, lang: () => document.documentElement.lang };
}

// --- the JSON-Schema subset the board contract uses (mirror of the app's BoardSpec.SchemaCheck)
interface Schema {
  $ref?: string;
  $defs?: Record<string, Schema>;
  type?: string | string[];
  enum?: unknown[];
  required?: string[];
  properties?: Record<string, Schema>;
  additionalProperties?: boolean;
  items?: Schema;
}
const typeName = (v: unknown): string =>
  v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v === 'number' ? (Number.isInteger(v) ? 'integer' : 'number') : typeof v;

export function validate(schema: Schema, value: unknown, p = '$', root: Schema = schema): string[] {
  if (schema.$ref) {
    const def = schema.$ref.startsWith('#/$defs/') ? root.$defs?.[schema.$ref.slice(8)] : undefined;
    return def ? validate(def, value, p, root) : [`${p}: unsupported $ref ${schema.$ref}`];
  }
  const errs: string[] = [];
  const actual = typeName(value);
  const types = schema.type === undefined ? [] : [schema.type].flat();
  if (types.length && !types.some((t) => t === actual || (t === 'number' && actual === 'integer'))) errs.push(`${p}: expected ${types.join('|')}, got ${actual}`);
  if (schema.enum && !schema.enum.some((e) => JSON.stringify(e) === JSON.stringify(value))) errs.push(`${p}: ${JSON.stringify(value)} not in enum`);
  if (actual === 'object') {
    const obj = value as Record<string, unknown>;
    for (const k of schema.required ?? []) if (!(k in obj)) errs.push(`${p}: missing ${k}`);
    for (const [k, v] of Object.entries(obj)) {
      const sub = schema.properties?.[k];
      if (sub) errs.push(...validate(sub, v, `${p}.${k}`, root));
      else if (schema.additionalProperties === false) errs.push(`${p}.${k}: not allowed`);
    }
  }
  if (actual === 'array' && schema.items) {
    const items = schema.items;
    (value as unknown[]).forEach((v, i) => errs.push(...validate(items, v, `${p}[${i}]`, root)));
  }
  return errs;
}
// The app image owns the schema (MIP-0070 §5.4): site/board.schema.json is the vendored copy, BOARD_SCHEMA the one
// site.yml extracts from the pinned image itself.
export const SCHEMA_PATH = process.env.BOARD_SCHEMA ?? path.join(ROOT, 'site/board.schema.json');
export const SCHEMA = JSON.parse(fs.readFileSync(SCHEMA_PATH, 'utf8')) as Schema;

// §5.8 gate 4: under ?lang=x-pseudo every message is accented and bracketed, so a plain a/e/i/o/u/y/c/n left on
// the page is text that skipped t(), unless it is board data.
export function leaks(text: string, data: string[], tokens: string[] = []): string[] {
  const ent: Readonly<Record<string, string>> = { amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" };
  let s = text.replace(/&(amp|lt|gt|quot|#39);/g, (_, e: string) => ent[e] ?? '').replace(/[⟦⟧·]/g, ' ');
  for (const d of [...data].sort((a, b) => b.length - a.length)) s = s.split(d).join(' ');
  return s
    .split(/[\s()[\]{}:,;.!?…"'—–\-/×+±=<>|&]+/)
    .filter((tok) => /[aeiouycnAEIOUYCN]/.test(tok) && tok.replace(/^\d+/, '') !== '°C' && !tokens.includes(tok));
}

