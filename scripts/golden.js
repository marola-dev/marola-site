#!/usr/bin/env node
/** golden: runs the pure functions of the OLD page code (site/static/ui.js, app.js, flow.js) over a
 * table of inputs and writes what they return to front/tests/golden.json. The Elm tests in
 * front/tests (GoldenTests.elm) read that file and must give the same answers (the parity contract of the port).
 *
 * The old files keep their functions inside an IIFE, so each function is cut out of the source text
 * and evaluated in a vm sandbox next to the real i18n runtime. No browser, no network, no dependency.
 *
 *   node scripts/golden.js          write the file
 *   node scripts/golden.js --check  fail if the committed file is stale (just golden --check)
 */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'front/tests/golden.json');
const read = p => fs.readFileSync(path.join(ROOT, p), 'utf8');
const UI = read('site/static/ui.js');
const APP = read('site/static/app.js');
const FLOW = read('site/static/flow.js');
const I18N_JS = read('site/static/i18n.js');
const BOARD = JSON.parse(read('site/fixtures/board.json'));
const LANGS = ['pt-BR', 'en'];

// --- cutting a function or a var out of an IIFE ----------------------------------------------
// A small scanner: it knows strings, comments and regex literals, so a quote inside /[&<>"']/ does
// not end the function early.
function scan(src, from, mode) {
  let depth = 0, prev = '';
  for (let i = from; i < src.length; i++) {
    const c = src[i], n = src[i + 1];
    if (c === "'" || c === '"' || c === '`') {
      for (i++; src[i] !== c; i++) if (src[i] === '\\') i++;
      prev = c; continue;
    }
    if (c === '/' && n === '/') { i = src.indexOf('\n', i); continue; }
    if (c === '/' && n === '*') { i = src.indexOf('*/', i) + 1; continue; }
    if (c === '/' && /[(,=:[!&|?{};]/.test(prev)) {
      let inClass = false;
      for (i++; inClass || src[i] !== '/'; i++) {
        if (src[i] === '\\') i++;
        else if (src[i] === '[') inClass = true;
        else if (src[i] === ']') inClass = false;
      }
      prev = '/'; continue;
    }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) { depth--; if (mode === 'function' && depth === 0 && c === '}') return i + 1; }
    else if (mode === 'var' && c === ';' && depth === 0) return i + 1;
    if (!/\s/.test(c)) prev = c;
  }
  throw new Error('golden: no end found');
}
function cut(src, name, kind) {
  const re = new RegExp('^  ' + kind + ' ' + name + (kind === 'function' ? '\\(' : ' ='), 'm');
  const m = re.exec(src);
  if (!m) throw new Error('golden: ' + kind + ' ' + name + ' not found');
  return src.slice(m.index, scan(src, m.index, kind));
}
const fns = (src, names) => names.map(n => cut(src, n, 'function')).join('\n');
const vars = (src, names) => names.map(n => cut(src, n, 'var')).join('\n');

// --- the sandboxes ---------------------------------------------------------------------------
function context(catalog) {
  const sandbox = {
    document: { getElementById: () => null, querySelectorAll: () => [], documentElement: {}, addEventListener() {} },
    location: { href: 'https://example.test/', search: '' },
    history: { replaceState() {} },
    navigator: { languages: [] },
    localStorage: { getItem: () => null, setItem() {} },
    URL, URLSearchParams
  };
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  if (catalog) sandbox.MAROLA_I18N = catalog;
  else vm.runInContext(I18N_JS, sandbox, { filename: 'site/static/i18n.js' });
  vm.runInContext(UI, sandbox, { filename: 'site/static/ui.js' });
  return sandbox;
}
const setLang = (ctx, lang) => ctx.marolaI18n.setLang(lang);

function uiFns(ctx) {
  const code = '(function () { var SOURCE = "pt-BR", PSEUDO = "x-pseudo", CATALOG = window.MAROLA_I18N || {};\n' +
    fns(UI, ['intlLang', 'number', 'match', 'resolveLang', 'parse', 'format', 'lookup']) +
    '\nreturn { parse: parse, format: format, lookup: lookup, resolveLang: resolveLang, match: match }; })()';
  return vm.runInContext(code, ctx, { filename: 'ui.js (cut)' });
}
function appFns(ctx) {
  const names = ['esc', 'num', 'fmt', 'word', 'band', 'haversineKm', 'shown', 'isPast', 'hourEntry', 'waterSummary',
    'waterDotClass', 'wavesText', 'aspectsHtml', 'ranked', 'condLabel', 'compass'];
  const code = '(function () { var I = window.marolaI18n, t = I.t; var state = { board: null, hours: [], hourIndex: -1, here: null };\n' +
    vars(APP, ['formats', 'ICONS', 'COMPASS']) + '\n' +
    // These call tx, noWaterData, facilitiesHtml and icon; they are cut too, but not returned.
    fns(APP, ['tx', 'noWaterData', 'facilitiesHtml', 'icon']) + '\n' + fns(APP, names) +
    '\nreturn { state: state, ' + names.map(n => n + ': ' + n).join(', ') + ' }; })()';
  return vm.runInContext(code, ctx, { filename: 'app.js (cut)' });
}
function flowFns() {
  const ctx = context();
  vm.runInContext(FLOW, ctx, { filename: 'site/static/flow.js' });
  const extra = vm.runInContext('(function () {\n' + fns(FLOW, ['lonOf', 'latOf', 'hexRgb']) +
    '\nreturn { lonOf: lonOf, latOf: latOf, hexRgb: hexRgb }; })()', ctx, { filename: 'flow.js (cut)' });
  return Object.assign({}, ctx.marolaFlow, extra);
}

// --- inputs ----------------------------------------------------------------------------------
const clone = o => JSON.parse(JSON.stringify(o));
function beachVariants() {
  const [joaquina, brava] = clone(BOARD.beaches);
  const v = { joaquina, brava };
  const noband = clone(brava); noband.name = 'Sem faixa';
  noband.hours.forEach(h => { delete h.wind_level; delete h.note_codes; });
  noband.whales.peak = null; v.noband = noband;
  const unfit = clone(joaquina); unfit.name = 'Imprópria <&"\'>';
  unfit.water.unfit = true; unfit.water.summary = '0/5 IMPRÓPRIA'; v.unfit = unfit;
  const nodata = clone(brava); nodata.name = 'Sem dados'; nodata.water.summary = 'no data'; v.nodata = nodata;
  const full = clone(joaquina); full.name = 'Completa';
  full.facilities = { parking: 2, toilets: 0, shower: 1, lifeguard: 3 }; v.full = full;
  const partial = clone(brava); partial.name = 'Parcial'; partial.facilities = { parking: 1200, toilets: 0 }; v.partial = partial;
  const nulls = clone(joaquina); nulls.name = 'Nulos';
  Object.keys(nulls.sea).forEach(k => { nulls.sea[k] = null; });
  nulls.hours.forEach(h => { h.sea_temp_c = null; h.wave_m = null; h.wind_kmh = null; }); v.nulls = nulls;
  const peak = clone(joaquina); peak.name = 'Pico'; peak.whales.peak = '10:00'; v.peak = peak;
  const peak2 = clone(brava); peak2.name = 'Outro pico'; peak2.whales.peak = '13:00'; v.peak2 = peak2;
  const odd = clone(joaquina); odd.name = 'Valores novos';
  odd.jellyfish = 'Extreme'; odd.hours.forEach(h => { h.wind_level = 'gale'; h.whales = 'Extreme'; }); v.odd = odd;
  const tie = clone(brava); tie.name = 'Brava 2'; tie.hours = tie.hours.filter(h => h.h !== '13:00'); v.tie = tie;
  const rio = clone(joaquina); rio.name = 'Copacabana'; rio.lat = -22.9711; rio.lon = -43.1822; v.rio = rio;
  return v;
}

// --- the cases -------------------------------------------------------------------------------
function build() {
  const out = {};
  const ui = {}, app = {}, flow = flowFns();
  const ctxs = {};
  LANGS.forEach(lang => {
    const ctx = context(); setLang(ctx, lang);
    ctxs[lang] = ctx; ui[lang] = uiFns(ctx); app[lang] = appFns(ctx);
  });
  const catalogs = vm.runInContext('window.MAROLA_I18N', ctxs['pt-BR']);
  const variants = beachVariants();
  out.variants = variants; // the beaches the cases below name

  [textCases, beachCases, flowCases, icuCases, catalogCases].forEach(group => group(out, { ui, app, flow, ctxs, catalogs, variants }));
  return out;
}

// Numbers, words, water and escaping.
function textCases(out, env) {
  const { app } = env;
  // band: every branch, with and without the veto
  out.band = [];
  [null, 0, -5, 1, 39, 40, 41, 69, 70, 71, 100].forEach(score => [false, true].forEach(unfit => {
    out.band.push({ score, unfit, out: app['pt-BR'].band(score, unfit) });
  }));

  // numbers: Intl itself, the thing NumFmt.fs stands in for
  out.number = [];
  const values = [0, 1, 0.5, 1.005, 1.5, 2.5, 0.05, 0.0004, 0.0005, 0.045, 1234.5, 1234567.891, 999.9995, 99.95, -1.25, -0.04,
    12.345678, 0.1 + 0.2, 1e21, 1e-7, 123456789012, 1000, 999.5, 6.5, 27.4999, 7.45, 0.995, 19.2, 100];
  LANGS.forEach(lang => values.forEach(n => [[0, 3], [0, 0], [1, 1], [2, 2], [1, 2]].forEach(([min, max]) => {
    out.number.push({ lang, n, min, max, out: new Intl.NumberFormat(lang, { minimumFractionDigits: min, maximumFractionDigits: max }).format(n) });
  })));

  // fmt: the app's own number-and-unit writer, with the no-break space and "n/a"
  out.fmt = [];
  LANGS.forEach(lang => [[19.2, ' °C', null], [12, ' km/h', 0], [6, ' s', 0], [1.25, ' m', null], [null, ' m', null], [0, '', 0],
    [1234.5, ' km', 1], [27, '°C', null], [5, ' a b', 1], [0.05, ' m', null]].forEach(([n, unit, digits]) => {
    out.fmt.push({ lang, n, unit, digits, out: app[lang].fmt(n, unit, digits === null ? undefined : digits) });
  }));

  out.waves_text = [];
  LANGS.forEach(lang => [[1.3, 8], [1.3, null], [null, 7], [null, null], [0, 0], [2.25, 10.4]].forEach(([m, s]) => {
    out.waves_text.push({ lang, wave_m: m, period_s: s, out: app[lang].wavesText(m, s) });
  }));

  // escaping
  out.esc = ['', 'plain', 'a & b', '<script>alert("x")</script>', "it's", '"quoted"', '&amp; already', 'ação · 日本 😀', '<>&"\'', '5 > 3 && 2 < 4']
    .map(s => ({ in: s, out: app['pt-BR'].esc(s) }));
  out.word = [];
  LANGS.forEach(lang => [['lvl.', 'High'], ['lvl.', 'low'], ['lvl.', 'Extreme'], ['wind.', 'calm'], ['wind.', 'STRONG'], ['wind.', 'gale'],
    ['dir.', 'n'], ['dir.', 'SW'], ['dir.', 'x'], ['lvl.', '']].forEach(([prefix, value]) => {
    out.word.push({ lang, prefix, value, out: app[lang].word(prefix, value) });
  }));

  out.compass = [];
  LANGS.forEach(lang => [0, 22, 23, 44.9, 45, 90, 135, 180, 225, 270, 315, 337, 338, 359.9, 360, 405].forEach(deg => {
    out.compass.push({ lang, deg, out: app[lang].compass(deg) });
  }));

  out.cond_label = [];
  LANGS.forEach(lang => ['proper', 'improper', 'unknown', 'weird'].forEach(c => {
    out.cond_label.push({ lang, condition: c, out: app[lang].condLabel(c) });
  }));

  out.water = [];
  const waters = [
    { summary: 'no data', unfit: false }, { summary: 'no data', unfit: true },
    { summary: '4/5 PRÓPRIA — avoid Ponto 73 (25 Aug)', unfit: false }, { summary: '0/5 IMPRÓPRIA', unfit: true }
  ];
  LANGS.forEach(lang => waters.forEach(w => {
    const water = Object.assign({ note: null, source: null, points: [] }, w);
    out.water.push({ lang, water, summary: app[lang].waterSummary({ water }), dot: app[lang].waterDotClass({ water }) });
  }));
}

// Beaches: the shown hour, the aspect cells, the list order.
function beachCases(out, env) {
  const { app, variants } = env;
  out.haversine = [];
  const pts = [[-27.6296, -48.4487, -27.4, -48.4], [-27.6, -48.48, -22.9878, -43.1913], [-22.9878, -43.1913, -12.9777, -38.5016],
    [0, 0, 0, 0], [0, 0, 0, 180], [10, 179, 10, -179], [-33.9, 18.4, 51.5, -0.1], [89, 0, 89, 180], [0, 0, 0.001, 0.001], [-27.6, -48.5, -27.6, -48.5]];
  pts.forEach(([la, lo, lb, lob]) => {
    out.haversine.push({ a: { lat: la, lon: lo }, b: { lat: lb, lon: lob }, km: app['pt-BR'].haversineKm({ lat: la, lon: lo }, { lat: lb, lon: lob }) });
  });

  // hour entry and the shown shape
  out.shown = [];
  Object.entries(variants).forEach(([name, beach]) => {
    const hours = beach.hours.map(h => h.h);
    [null, hours[0], hours[hours.length - 1], '23:00'].forEach(selection => {
      const a = app['pt-BR'];
      a.state.hours = selection === null ? [] : [selection]; a.state.hourIndex = selection === null ? -1 : 0;
      const s = a.shown(beach), e = a.hourEntry(beach, s);
      out.shown.push({ variant: name, selection, shown: s, entry_h: e ? e.h : null });
    });
  });

  // the aspect cells, in text, from the HTML the old code built
  out.aspects = [];
  const entities = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'" };
  const plain = h => h.replace(/<svg[\s\S]*?<\/svg>/g, '').replace(/<[^>]+>/g, '')
    .replace(/&(amp|lt|gt|quot|#39);/g, m => entities[m]).replace(/[ \t\n]+/g, ' ').trim();
  LANGS.forEach(lang => Object.entries(variants).forEach(([name, beach]) => {
    const hours = beach.hours.map(h => h.h);
    [null, hours[0], hours[hours.length - 1], '23:00'].forEach(selection => {
      const a = app[lang];
      a.state.hours = selection === null ? [] : [selection]; a.state.hourIndex = selection === null ? -1 : 0;
      const html = a.aspectsHtml(beach, a.shown(beach));
      const head = /^<div class="head">([\s\S]*?)<\/div>/.exec(html)[1];
      const cells = [], marks = [];
      html.replace(/<span( class="([^"]*)")?>([\s\S]*?)<\/span>/g, (_, _a, cls, body) => {
        cells.push(plain(body));
        marks.push(cls ? { cls, dot: (/<i class="([^"]*)">/.exec(body) || [])[1] || null } : null);
      });
      out.aspects.push({ lang, variant: name, selection, head: plain(head), cells, marks });
    });
  }));

  // is_past
  out.is_past = [];
  [['2026-09-06', '2026-09-06'], ['2026-09-07', '2026-09-06']].forEach(([day, today]) => ['05:00', '06:00', '06:01', '12:00'].forEach(h => {
    const a = app['pt-BR']; a.state.board = { day, today, generated_at: '2026-09-06T06:00:00-03:00' };
    out.is_past.push({ day, today, generated_at: '2026-09-06T06:00:00-03:00', h, out: a.isPast(h) });
  }));
  app['pt-BR'].state.board = null;

  // ranked: by score at an hour, and by distance (the old code wrote _km into the beach)
  out.ranked = [];
  const rankVariants = ['joaquina', 'brava', 'unfit', 'nulls', 'tie', 'rio', 'noband'];
  const board = { beaches: rankVariants.map(k => variants[k]) };
  const rankHours = ['07:00', '10:00', '13:00'];
  const a0 = app['pt-BR'];
  [null, 0, 1, 2].forEach(index => [null, { lat: -27.6, lon: -48.48 }, { lat: -22.98, lon: -43.19 }].forEach(here => {
    const beaches = clone(board.beaches);
    a0.state.board = { beaches }; a0.state.hours = rankHours; a0.state.hourIndex = index === null ? -1 : index; a0.state.here = here;
    const list = a0.ranked();
    out.ranked.push({ variants: rankVariants, hours: rankHours, index, here, names: list.map(b => b.name), km: here ? list.map(b => b._km) : null });
  }));
  a0.state.board = null; a0.state.here = null;
}

// The flow layer's maths.
function flowCases(out, env) {
  const { flow } = env;
  // mercator
  out.mercator = [];
  [-180, -48.4487, -43.19, 0, 90, 180].forEach(lon => out.mercator.push({ fn: 'x', in: lon, out: flow.mercX(lon) }));
  [-85, -60, -27.6296, -22.9, 0, 12.9777, 45, 85].forEach(lat => out.mercator.push({ fn: 'y', in: lat, out: flow.mercY(lat) }));
  [0, 0.25, 0.5, 0.75, 1].forEach(x => out.mercator.push({ fn: 'lon_of', in: x, out: flow.lonOf(x) }));
  [0, 0.2, 0.4, 0.5, 0.6, 0.8, 1].forEach(y => out.mercator.push({ fn: 'lat_of', in: y, out: flow.latOf(y) }));

  // the flow field: a few cells and samples are enough to pin the maths
  out.field = [];
  const fieldCases = [
    { max: 40, points: [{ lon: -48.4487, lat: -27.6296, mag: 12, dir: 90 }, { lon: -48.4, lat: -27.4, mag: 27, dir: 200 }, { lon: -48.55, lat: -27.8, mag: 5, dir: 10 }] },
    { max: 40, points: [{ lon: -48.4487, lat: -27.6296, mag: 12, dir: 90 }, { lon: -48.4, lat: -27.4, mag: null, dir: 200 }, { lon: -48.55, lat: -27.8, mag: 5, dir: null }, { lon: -48.5, lat: -27.5, mag: 30, dir: 355 }] },
    { max: 3, points: [{ lon: -43.18, lat: -22.97, mag: 1.3, dir: 135 }] },
    { max: 3, points: [{ lon: -43.18, lat: -22.97, mag: 1.3, dir: 135 }, { lon: -43.5, lat: -23.0, mag: 2.6, dir: 180 }, { lon: -43.1, lat: -22.9, mag: 0.4, dir: 45 }, { lon: -43.3, lat: -23.03, mag: 5, dir: 270 }] },
    { max: 40, points: [{ lon: -38.5, lat: -12.97, mag: 0, dir: 0 }, { lon: -38.4, lat: -13.0, mag: 40, dir: 90 }] },
    { max: 40, points: [{ lon: -38.5, lat: -12.97, mag: null, dir: null }] },
    { max: 40, points: [] }
  ];
  const cellIndex = [0, 47, 48, 95, 96 * 47 + 48, 96 * 95, 96 * 95 + 95, 96 * 10 + 20, 96 * 70 + 5, 9215];
  const fractions = [-0.1, 0, 0.0013, 0.25, 0.5, 0.77, 0.999, 1, 1.05];
  fieldCases.forEach(c => {
    const f = flow.buildField(c.points, c.max);
    if (!f) { out.field.push({ max: c.max, points: c.points, field: null }); return; }
    const cells = cellIndex.map(n => ({ n, u: f.u[n], v: f.v[n], m: f.m[n], a: f.a[n] }));
    const samples = [];
    fractions.forEach(fx => [-0.2, 0.1, 0.5, 0.97, 1.0, 1.2].forEach(fy => {
      const x = f.x0 + (f.x1 - f.x0) * fx, y = f.y0 + (f.y1 - f.y0) * fy, s = flow.sample(f, x, y);
      samples.push({ x, y, out: s });
    }));
    out.field.push({ max: c.max, points: c.points, field: { x0: f.x0, x1: f.x1, y0: f.y0, y1: f.y1, cells, samples } });
  });

  // the colour ramp
  out.hex_rgb = ['#ff8800', 'FF8800', ' #00ff00 ', 'zzz', '#abc', '', '#12345g', 'ff00ffaa', '#000000', '#FfFfFf', '##112233']
    .map(hex => ({ in: hex, out: flow.hexRgb(hex) }));
  out.ramp = [['#000000', '#ffffff'], ['#0b1d51', '#2a9d8f', '#e9c46a', '#e76f51'], ['#ff0000', 'bad', '#0000ff'], ['#102030', '#fefefe', '#808080']]
    .map(stops => ({ stops, out: Array.from(flow.rampPixels(stops)) }));
}

// The ICU subset of ui.js.
function icuCases(out, env) {
  const { ui } = env;
  // the ICU subset
  out.icu_parse = [];
  const sources = ['', 'plain text', '{a}', 'x {a} y {b}', '{ a }', '{n, plural, one {# item} other {# items}}',
    '{n, plural, =0 {none} one {one} other {# many}}', '{x, select, yes {Y} other {N}}', '{x,select,yes{Y}other{N}}',
    '{x, select, yes { (best {peak})} other {}}', '{n, plural, one {{x, select, a {#!} other {?}}} other {#}}',
    '# outside plural', 'a } b', '{a', '{a,', '{a, plural', '{a, plural, one {x', '{, plural, other {x}}', '{a b}',
    '{a, plural, one {x} other {y}', '{n, plural,\u00a0one\u00a0{x}\u00a0other\u00a0{y}}', 'ação {n} · 日本', '{a}{b}{c}', '{n, plural, one {x} } z'];
  sources.forEach(src => {
    let res;
    try { res = { ok: ui['pt-BR'].parse(src) }; } catch (e) { res = { error: e.message }; }
    out.icu_parse.push({ src, out: res });
  });
  out.icu_format = [];
  const formats = [
    ['plain', {}], ['x {a} y', { a: 'one' }], ['x {a} y', { a: 1234.5 }], ['x {a} y', {}], ['{a}', { a: 0 }],
    ['{n, plural, one {# item} other {# items}}', { n: 1 }], ['{n, plural, one {# item} other {# items}}', { n: 0 }],
    ['{n, plural, one {# item} other {# items}}', { n: 1.5 }], ['{n, plural, one {# item} other {# items}}', { n: 2 }],
    ['{n, plural, one {# item} other {# items}}', { n: 1234567.5 }], ['{n, plural, one {# item} other {# items}}', { n: 1000000 }],
    ['{n, plural, one {# item} other {# items}}', { n: -1 }], ['{n, plural, one {# item} other {# items}}', {}],
    ['{n, plural, one {# item} other {# items}}', { n: '5' }], ['{n, plural, one {# item} other {# items}}', { n: 'many' }],
    ['{n, plural, =0 {none} one {one} other {# many}}', { n: 0 }], ['{n, plural, =0 {none} one {one} other {# many}}', { n: 1 }],
    ['{n, plural, =0 {none} one {one} other {# many}}', { n: 3 }],
    ['{x, select, yes {Y} other {N}}', { x: 'yes' }], ['{x, select, yes {Y} other {N}}', { x: 'no' }], ['{x, select, yes {Y} other {N}}', {}],
    ['{x, select, yes {Y} other {N}}', { x: 1 }],
    ['{n, plural, one {{x, select, a {#!} other {?}}} other {#}}', { n: 1, x: 'a' }],
    ['{n, plural, one {{x, select, a {#!} other {?}}} other {#}}', { n: 5, x: 'a' }],
    ['{n, plural, one {{x, select, a {#!} other {?}}} other {#}}', { n: 1, x: 'b' }]
  ];
  LANGS.forEach(lang => formats.forEach(([src, args]) => {
    out.icu_format.push({ lang, src, args, out: ui[lang].format(ui[lang].parse(src), args, lang) });
  }));
}

// t() over the catalogs, lookup and the language choice.
function catalogCases(out, env) {
  const { ui, ctxs, catalogs } = env;
  // t(): the real catalogs, the whole of them with no arguments, and a few with arguments
  out.t_all = [];
  LANGS.forEach(lang => Object.keys(catalogs[lang]).forEach(key => out.t_all.push({ lang, key, out: ctxs[lang].marolaI18n.t(key) })));
  out.t = [];
  const calls = [
    ['card.at_best', { h: '10:00', best: '07:00', score: 55 }], ['cell.waves', { m: '1.3\u00a0m', every: 'yes', s: '8\u00a0s' }],
    ['cell.waves', { m: '1.3\u00a0m', every: 'no', s: 'n/a' }], ['cell.whales', { level: 'low', best: 'yes', peak: '10:00' }],
    ['card.whales_now', { level: 'high', best: 'yes', peak: '09:00', season: 'yes' }], ['card.whales_now', { level: 'low', best: 'no', peak: '', season: 'no' }],
    ['footer.generated', { when: '2026-09-06 06:00', area: 'Florianópolis', day: '2026-09-06', n: 1, sources: 'a · b' }],
    ['footer.generated', { when: 'w', area: 'a', day: 'd', n: 0, sources: 's' }], ['footer.generated', { when: 'w', area: 'a', day: 'd', n: 1234, sources: 's' }],
    ['tip.at', { score: 55, h: '10:00' }], ['tip.dark', undefined], ['card.enterococci', { n: 1234567 }], ['hour.at', { h: '10:00', past: 'yes' }],
    ['hour.at', { h: '10:00', past: 'no' }], ['common.na', undefined], ['no.such.key', undefined], ['constructor', undefined], ['__proto__', undefined],
    ['toString', undefined], ['water.no_data', undefined], ['fail.load', { error: '404 data/x.json', hint: 'yes' }]
  ];
  LANGS.forEach(lang => calls.forEach(([key, args]) => out.t.push({ lang, key, args: args || {}, out: ctxs[lang].marolaI18n.t(key, args) })));

  // a catalog where one language lacks a key: t() falls back to pt-BR, formatted as pt-BR
  out.fallback_catalog = {
    'pt-BR': { only_pt: 'só pt: {n, plural, one {# item} other {# itens}}', both: 'pt {n}', 'plain': 'texto' },
    en: { both: 'en {n}', plain: 'text' }
  };
  const fb = context(out.fallback_catalog);
  out.fallback = [];
  LANGS.forEach(lang => ['only_pt', 'both', 'plain', 'missing', 'constructor'].forEach(key => [{ n: 1 }, { n: 1234.5 }].forEach(args => {
    setLang(fb, lang);
    out.fallback.push({ lang, key, args, out: fb.marolaI18n.t(key, args) });
  })));

  out.lookup = [];
  LANGS.forEach(lang => ['common.na', 'water.no_data', 'nope', 'constructor', '__proto__', 'toString', 'hasOwnProperty', ''].forEach(key => {
    const v = ui[lang].lookup(key, lang);
    out.lookup.push({ lang, key, out: v === undefined ? null : v });
  }));

  // language choice
  out.resolve_lang = [];
  const supported = ['pt-BR', 'en'];
  const resolves = [
    { param: 'en' }, { param: 'EN-us' }, { param: 'pt' }, { param: 'PT-br' }, { param: 'fr', stored: 'en' }, { param: null, stored: 'fr', languages: ['de', 'pt'] },
    { languages: ['en-GB', 'pt'] }, { languages: [] }, { param: '', stored: '', languages: [''] }, { param: 'xx', stored: 'yy', languages: ['zz'] },
    { stored: 'pt-PT' }, { languages: ['es', 'en-US', 'pt-BR'] }, { param: 'english' }, { param: 'e' }, { stored: 'EN' }, { languages: ['ptx'] }
  ];
  resolves.forEach(o => out.resolve_lang.push({ param: o.param === undefined ? null : o.param, stored: o.stored === undefined ? null : o.stored,
    languages: o.languages || [], out: ui['pt-BR'].resolveLang(Object.assign({ supported }, o)) }));
}

// One entry per line keeps a stale-file diff readable.
function serialise(data) {
  const body = Object.entries(data).map(([k, v]) =>
    Array.isArray(v) ? '  ' + JSON.stringify(k) + ': [\n' + v.map(e => '    ' + JSON.stringify(e)).join(',\n') + '\n  ]'
      : '  ' + JSON.stringify(k) + ': ' + JSON.stringify(v));
  return '{\n' + body.join(',\n') + '\n}\n';
}

const text = serialise(build());
if (process.argv.includes('--check')) {
  const have = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
  if (have !== text) {
    console.error('golden: front/tests/golden.json is stale; run `just golden` and commit it');
    process.exit(1);
  }
  console.log('golden: front/tests/golden.json is current');
} else {
  fs.writeFileSync(OUT, text);
  console.log('golden: wrote ' + path.relative(ROOT, OUT) + ' (' + text.length + ' bytes)');
}
