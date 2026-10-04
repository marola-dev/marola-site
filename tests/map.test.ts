/** The map page against the fixture board. */
import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Board, Trail } from '../site/src/board.ts';
import { type FlowLayer, KINDS, mercX, mercY, sample } from '../site/src/flow.ts';
import { BOARD, BOARD_V1, clone, type El, INDEX, leaks, type Marker, type Page, pickLang, plain, type Popup, runPage } from './harness.ts';

// A marker's tooltip is the popup its element opens on hover; a click is the element's.
function tipOf(m: Marker | undefined): string {
  if (!m) return '';
  m.M.lastShown = null;
  m.element.fire('mouseenter');
  const html = m.M.lastShown && (m.M.lastShown as Popup).open ? (m.M.lastShown as Popup).html : '';
  m.element.fire('mouseleave');
  return html;
}
const markers = (r: Page, cls: string): Marker[] =>
  r.M.created.filter((l): l is Marker => l.kind === 'marker' && l.added && new RegExp(`\\b${cls}\\b`).test(l.element.className));
const waves = (r: Page): Marker[] => markers(r, 'wave');
const points = (r: Page): Marker[] => markers(r, 'wpoint');
const waveOf = (r: Page, name: string): Marker | undefined => waves(r).find((m) => tipOf(m).includes(name));
const openCard = (r: Page, name: string): string => {
  waveOf(r, name)?.element.fire('click');
  return plain(r.el('card').innerHTML);
};
const slide = (r: Page, i: number): void => {
  r.el('hour').value = String(i);
  r.el('hour').fire('input');
};
const flowOf = (r: Page): FlowLayer => r.map?.getLayer('marola-flow') as unknown as FlowLayer;
const rail = (r: Page, key: string): El => {
  const b = [...r.el('flow').querySelectorAll('button[data-layer]'), ...r.el('flow').querySelectorAll('button[data-toggle]')].find(
    (x) => x.dataset.layer === key || x.dataset.toggle === key,
  );
  assert.ok(b, key);
  return b;
};
const press = (r: Page, key: string): void => {
  r.el('flow').click(rail(r, key));
};
const keyShown = (r: Page, key: string): boolean => r.el('flowkeys').querySelectorAll('[data-key]').find((k) => k.dataset.key === key)?.hidden === false;
// Arrays made inside the page's context fail deepStrictEqual's prototype check, so these compare as JSON.
const same = (actual: unknown, expected: unknown, msg?: string): void => {
  assert.equal(JSON.stringify(actual), JSON.stringify(expected), msg);
};
const deny = { getCurrentPosition: (_ok: unknown, no: (e: unknown) => void) => no({ code: 1 }) };

const trails: Trail[] = [
  {
    name: 'Trilha da Lagoinha do Leste',
    length_km: 2.1,
    difficulty: null,
    geometry: [
      [-27.79, -48.49],
      [-27.792, -48.487],
      [-27.793, -48.485],
    ],
  },
  {
    name: 'Trilha Praia do Maço-Guarda',
    length_km: 1.4,
    difficulty: 'mountain_hiking',
    geometry: [
      [-27.4, -48.42],
      [-27.401, -48.415],
    ],
  },
];

const en = await runPage(BOARD, { search: '?lang=en' });
const joaqTip = plain(tipOf(waveOf(en, 'Praia da Joaquina')));

test('the page loads the board onto a Mapbox map without errors', () => {
  assert.deepEqual(en.errors, []);
  const o = en.map?.options;
  assert.equal(o?.container, 'map');
  assert.equal(o?.style, 'mapbox://styles/mapbox/outdoors-v12');
  assert.equal(o?.projection, 'mercator', 'flow draws in mercator');
  assert.equal(o?.collectResourceTiming, false);
  assert.equal(en.M.api.accessToken, 'pk.test', 'the token comes from mapbox-config.js');
  assert.equal(en.M.api.workerUrl, 'vendor/mapbox-gl-csp-worker.js?v=3.32.0', 'the CSP build: a same-origin worker, versioned');
});

test('one dot per beach, centred on it, named for screen readers, coloured by score', () => {
  assert.equal(waves(en).length, BOARD.beaches.length);
  assert.equal(points(en).length, 0, 'no sampling point before a card opens');
  const joaq = waveOf(en, 'Praia da Joaquina');
  assert.ok(joaq);
  assert.equal(joaq.options.anchor, 'center');
  same(joaq.lngLat, [-48.4487, -27.6296]);
  assert.equal(joaq.element.attrs['aria-label'], 'Praia da Joaquina');
  assert.equal(joaq.element.attrs.role, 'button');
  assert.equal(joaq.element.attrs.tabindex, '0');
  assert.equal(joaq.element.attrs.title, undefined, 'no native tooltip over the popup');
  assert.match(joaq.element.innerHTML, /fill="#e0a800" stroke="#fff"/, 'the 40-69 colour');
  assert.match(waveOf(en, 'Praia Brava')?.element.innerHTML ?? '', /#c0392b/, 'the unfit beach is red');
  same(en.map?.fitted?.[0], [
    [-48.4487, -27.6296],
    [-48.4157, -27.4021],
  ]);
});

test("index.html's legend key draws the same dot as a marker", () => {
  const shape = (html: string): string[] => (html.match(/<circle [^>]*>/g) ?? []).map((c) => c.replace(/ fill="(?!#1d2733)[^"]*"/, ''));
  const key = shape(/<span class="wave-key">[\s\S]*?<\/svg>/.exec(INDEX)?.[0] ?? '');
  assert.equal(key.length, 2);
  assert.deepEqual(key, shape(waveOf(en, 'Praia da Joaquina')?.element.innerHTML ?? ''));
});

test('the tooltip: six aspects from the board, each icon followed by its word, then facilities', () => {
  assert.match(joaqTip, /55\/100 at 10:00/);
  for (const needle of [
    '[wind] breezy, 27 km/h <abbr class="dir">S</abbr>',
    '[thermometer] water 19.0 °C',
    '[waves] waves 1.3 m every 6 s',
    '[jellyfish] jellyfish low',
    '[fish] whales low (best 07:00)',
    '<i class="wdot c70"></i> 1/1 PRÓPRIA (25 Aug)',
    '[parking] parking 3 · [toilets] toilets 1',
  ])
    assert.ok(joaqTip.includes(needle), needle);
  assert.doesNotMatch(joaqTip, /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]|\u{FE0F}/u, 'line icons, no emoji');
  assert.equal((joaqTip.match(/class="wide /g) ?? []).length, 2, 'the water and facilities cells span both columns');
  const brava = tipOf(waveOf(en, 'Praia Brava'));
  assert.match(brava, /class="wide unfit"><i class="wdot c0"><\/i> 0\/1 IMPRÓPRIA/);
  assert.ok(!brava.includes('facilities'), 'no facilities on the board: no cell, never a zero');
});

test('the tooltip opens on hover and on keyboard focus', () => {
  const joaq = waveOf(en, 'Praia da Joaquina');
  assert.ok(joaq);
  assert.equal(en.M.lastShown?.options.className, 'aspects');
  joaq.element.fire('focus');
  assert.ok(en.M.lastShown?.open && en.M.lastShown.html.includes('Praia da Joaquina'));
  joaq.element.fire('blur');
});

test('the list, best score first, with band classes and no inline style (the CSP blocks style=)', () => {
  const list = en.el('list').innerHTML;
  assert.equal((list.match(/<li /g) ?? []).length, 2);
  assert.ok(list.indexOf('Joaquina') < list.indexOf('Brava'));
  assert.match(list, /<span class="score c40">55<\/span>/);
  assert.match(list, /<span class="score c0">0<\/span>/);
  assert.doesNotMatch(list, /style=/);
  assert.match(en.el('area').innerHTML, /<option value="fixture" title="Fixture Bay" aria-label="Fixture Bay">FI<\/option>/);
  assert.equal(en.el('hour-label').textContent, 'best hour per beach');
});

test('the wave sound: fetched once, looped past the MP3 padding, on and off', async () => {
  const sound = en.el('sound');
  assert.notEqual(sound.attrs['aria-pressed'], 'true');
  sound.click();
  assert.equal(sound.attrs['aria-pressed'], 'true');
  for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r));
  const [out] = en.audio.gains;
  const [src] = en.audio.sources;
  assert.ok(src?.loop && src.started && src.target === out, 'the loop plays into the output gain');
  assert.ok((src.loopStart ?? 0) > 0 && (src.loopEnd ?? 0) > (src.loopStart ?? 0));
  assert.ok((out?.gain?.value ?? 0) > 0.01, 'audible after the first click');
  sound.click();
  assert.equal(sound.attrs['aria-pressed'], 'false');
  assert.ok((out?.gain?.value ?? 1) < 0.001, 'silent after the second');
  assert.equal(en.fetched.filter((f) => f === 'vendor/sounds/waves.mp3').length, 1);
});

test('a click on a beach opens its card, plots its sampling points, and a map click closes it', () => {
  const card = openCard(en, 'Praia da Joaquina');
  assert.equal(en.el('card').hidden, false);
  assert.match(card, /<span class="score c40">55\/100<\/span>/);
  assert.doesNotMatch(card, /style=/);
  const row = card.indexOf(`<div class="aspects">${joaqTip}</div>`);
  assert.ok(row > card.indexOf('</h2>') && row < card.indexOf('<dl>'), 'the card opens with the tooltip row (touch has no hover)');
  assert.ok(card.includes('<dt>why</dt><dd><ul><li>breezy (27km/h)</li><li>cold water (19.0°C)</li></ul></dd>'));
  const sel = waveOf(en, 'Praia da Joaquina');
  assert.match(sel?.element.className ?? '', /\bselected\b/);
  assert.match(sel?.element.innerHTML ?? '', /width="32"[\s\S]*<text [^>]*>55<\/text>/, 'the picked dot grows and carries its score');
  assert.equal(waves(en).length, BOARD.beaches.length, 'a re-render replaces the markers');
  const pts = points(en);
  assert.equal(pts.length, 1);
  same(pts[0]?.lngLat, [-48.4479, -27.6301]);
  assert.match(tipOf(pts[0]), /PRÓPRIA/);
  assert.match(pts[0]?.element.className ?? '', /\bc70\b/);

  openCard(en, 'Praia Brava');
  assert.equal(points(en).length, 1, "the other beach's points replace them");
  assert.match(points(en)[0]?.element.className ?? '', /\bc0\b/);

  const mapClick = en.map?.handlers.click?.[0];
  assert.ok(mapClick);
  mapClick({ originalEvent: { target: { closest: () => ({}) } } });
  assert.equal(en.el('card').hidden, false, 'a marker click, which reaches the map too, keeps the card');
  mapClick({ originalEvent: { target: { closest: () => null } } });
  assert.equal(en.el('card').hidden, true);
  assert.equal(points(en).length, 0);
});

test('an older board without wind_level keeps the number and drops the band word', async () => {
  const stripped = clone(BOARD);
  for (const b of stripped.beaches) for (const h of b.hours) delete h.wind_level;
  const r = await runPage(stripped, { search: '?lang=en' });
  const tip = plain(tipOf(waveOf(r, 'Praia da Joaquina')));
  assert.deepEqual(r.errors, []);
  assert.ok(tip.includes('[wind] wind 27 km/h') && !/breezy|calm|strong/.test(tip), tip);
});

test('trails: none on a board without them, one coloured line per trail when present', async () => {
  assert.ok(!('trails' in BOARD));
  assert.ok(en.map?.getLayer('trails'));
  const trailed: Board = clone(BOARD);
  trailed.trails = trails;
  const r = await runPage(trailed, { search: '?lang=en' });
  interface Feature { properties: { tip: string; color: string }; geometry: { coordinates: number[][] } }
  const features = (r.map?.sources.trails?.data as { features: Feature[] }).features;
  assert.deepEqual(r.errors, []);
  assert.equal(features.length, 2);
  const lagoinha = features.find((f) => f.properties.tip.includes('Lagoinha'));
  assert.match(lagoinha?.properties.tip ?? '', /2\.1\s*km/);
  same(lagoinha?.geometry.coordinates[0], [-48.49, -27.79], '[lat, lon] flipped to [lon, lat]');
  assert.equal(lagoinha?.properties.color, '#999999', 'no difficulty: grey');
  assert.equal(features.find((f) => f.properties.tip.includes('Maço'))?.properties.color, '#e0a800');
  r.map?.handlers['mousemove:trails']?.[0]?.({ lngLat: [-48.49, -27.79], features: [lagoinha] });
  assert.equal(r.M.lastShown?.html, lagoinha?.properties.tip, 'hovering a trail shows its tooltip');
});

test('the layer rail: off by default, one layer at a time, pressed again turns it off', () => {
  const r = en;
  const flow = flowOf(r);
  const entry = r.map?.layers.find((l) => l.layer.id === 'marola-flow');
  assert.equal(entry?.layer.type, 'custom');
  assert.equal(entry?.before, 'place-label', 'under the labels');
  assert.equal(flow.kind(), 'off');

  press(r, 'wind');
  assert.equal(flow.kind(), 'wind');
  assert.equal(rail(r, 'wind').attrs['aria-pressed'], 'true');
  const f = flow.field();
  assert.ok(f);
  const atJoaq = sample(f, mercX(-48.4487), mercY(-27.6296));
  assert.ok(atJoaq && atJoaq[1] > 0 && Math.abs(atJoaq[0]) < atJoaq[1] && atJoaq[3] > 0.9, 'from 180°: blows north');

  rail(r, 'waves').disabled = true;
  press(r, 'waves');
  assert.equal(flow.kind(), 'wind', 'a disabled ("em breve") button does nothing');
  rail(r, 'waves').disabled = false;
  press(r, 'waves');
  assert.equal(flow.kind(), 'waves');
  assert.ok(keyShown(r, 'waves') && rail(r, 'wind').attrs['aria-pressed'] === 'false');
  const wf = flow.field();
  const waveAt = wf && sample(wf, mercX(-48.4487), mercY(-27.6296));
  assert.ok(waveAt && Math.abs(waveAt[2] - 1.3 / KINDS.waves.max) < 0.02, "Joaquina's 1.3 m is the field's value there");

  const all = BOARD.beaches.reduce((n, b) => n + b.water.points.length, 0);
  press(r, 'water');
  assert.equal(flow.kind(), 'off');
  assert.equal(points(r).length, all, "the water layer draws every beach's points");
  assert.ok(keyShown(r, 'water') && r.el('map').classList.contains('layer-water'));
  press(r, 'wind');
  assert.equal(points(r).length, 0);

  const before = sample(flow.field() ?? f, mercX(-48.4487), mercY(-27.6296))?.[2] ?? 0;
  slide(r, 0);
  const after = sample(flow.field() ?? f, mercX(-48.4487), mercY(-27.6296))?.[2] ?? 0;
  assert.ok(Math.abs(before - 27 / 40) < 0.02 && Math.abs(after - 12 / 40) < 0.02, 'the slider moves the field (27 km/h best, 12 at 07:00)');
});

test('the NASA GIBS layers: one raster at a time, dated from the board, El Niño zooms out', () => {
  const r = en;
  const map = r.map;
  assert.ok(map);
  const tiles = (): string => String((map.sources['marola-raster']?.src.tiles as string[] | undefined)?.[0]);
  press(r, 'sst');
  assert.match(tiles(), /GHRSST_L4_MUR_Sea_Surface_Temperature\/default\/2026-09-04\//);
  assert.equal(map.getLayer('marola-raster')?.type, 'raster');
  assert.equal(r.el('flowkeys').querySelectorAll('[data-when]').find((w) => w.dataset.when === 'sst')?.textContent, '2026-09-04');
  press(r, 'clouds');
  assert.match(tiles(), /VIIRS_SNPP_CorrectedReflectance_TrueColor\/default\/2026-09-05\/.*\.jpg$/);
  assert.equal(map.layers.filter((l) => l.layer.id === 'marola-raster').length, 1);
  press(r, 'elnino');
  assert.match(tiles(), /Anomalies\/default\/2026-09-04\//);
  assert.equal(map.getLayer('nino34')?.layout?.visibility, 'visible');
  assert.equal(map.fitted?.[0][0][0], -180);
  assert.equal(map.minZoom, 0, 'below the area minZoom, for the Pacific');
  press(r, 'wind');
  assert.ok(!map.sources['marola-raster'] && !map.getLayer('marola-raster'));
  assert.equal(map.getLayer('nino34')?.layout?.visibility, 'none');
  assert.ok((map.fitted?.[0][0][0] ?? 0) > -49, 'back to the beaches');
  assert.equal(map.minZoom, 3);
});

test('the beaches and trails toggles are independent', () => {
  const r = en;
  press(r, 'beaches');
  assert.ok(r.el('map').classList.contains('no-beaches') && rail(r, 'beaches').attrs['aria-pressed'] === 'false');
  press(r, 'beaches');
  assert.ok(!r.el('map').classList.contains('no-beaches'));
  press(r, 'trails');
  assert.equal(r.map?.getLayer('trails')?.layout?.visibility, 'none');
  assert.equal(rail(r, 'beaches').attrs['aria-pressed'], 'true');
  press(r, 'trails');
  assert.equal(r.map?.getLayer('trails')?.layout?.visibility, 'visible');
});

test('?layer= opens on a layer, unless its button is still "em breve"', async () => {
  assert.equal(flowOf(await runPage(BOARD, { search: '?layer=waves' })).kind(), 'waves');
  const watered = await runPage(BOARD, { search: '?layer=water' });
  assert.ok(points(watered).length > 1);
  press(watered, 'water');
  assert.ok(rail(watered, 'water').attrs['aria-pressed'] === 'false' && !watered.el('map').classList.contains('layer-water'));
  const soon = await runPage(BOARD, { search: '?layer=wind', disabled: ['wind', 'trails'] });
  assert.equal(flowOf(soon).kind(), 'off');
  assert.equal(soon.map?.getLayer('trails')?.layout?.visibility, 'none');
  assert.ok(!en.map?.getLayer('marola-coast'), 'no coastline when the style has no composite source');
});

test('no token, a refused token, or a forecast day ahead never leave a blank or broken map', async () => {
  const refused = await runPage(BOARD, { styleStatus: 401 });
  assert.ok(!refused.el('map-note').hidden && !refused.el('list').hidden && refused.el('flow').hidden);
  const noToken = await runPage(BOARD, { token: '' });
  assert.deepEqual(noToken.errors, []);
  assert.equal(noToken.M.maps.length, 0, "Mapbox GL's licence needs a Mapbox account");
  assert.match(noToken.el('map-note').textContent, /Mapbox/);
  assert.ok(!noToken.el('list').hidden && noToken.el('list').innerHTML.includes('<li '));
  const ahead = await runPage({ ...BOARD, day: '2026-09-08' }, { search: '?layer=clouds' });
  const tiles = ahead.M.maps[0]?.sources['marola-raster']?.src.tiles as string[] | undefined;
  assert.match(tiles?.[0] ?? '', /\/default\/2026-09-05\//, "dates count back from the board's today");
});

test('pt-BR by default: decimal commas, the catalog words, the board kept verbatim', async () => {
  const pt = await runPage(BOARD, { storeThrows: true, geolocation: deny });
  assert.deepEqual(pt.errors, []);
  assert.equal(pt.documentElement.lang, 'pt-BR');
  assert.equal(pt.el('hour-label').textContent, 'melhor horário de cada praia');
  const tip = plain(tipOf(waveOf(pt, 'Praia da Joaquina')));
  for (const needle of ['55/100 às 10:00', '[wind] brisa, 27 km/h', '[thermometer] água 19,0 °C', '[waves] ondas 1,3 m a cada 6 s', '[jellyfish] água-viva: baixa'])
    assert.ok(tip.includes(needle), needle);
  assert.match(tipOf(waveOf(pt, 'Praia da Joaquina')), /27\u00a0km\/h/, 'a no-break space between a number and its unit');
  assert.match(pt.el('days').innerHTML, />hoje <small>09-06<\/small><\/button>/);
  assert.ok(pt.el('footer').innerHTML.includes('atualizado em 2026-09-06 06:00 · Fixture Bay, dia 2026-09-06 · 2 praias · fontes: <span class="src">'));
  const card = openCard(pt, 'Praia da Joaquina');
  for (const needle of [
    'aria-label="fechar"',
    'melhor às <b>10:00</b>',
    '<li>brisa (27 km/h)</li><li>água fria (19,0 °C)</li>',
    '<small>fonte: <span class="src">IMA/SC</span></small>',
    '<span class="water proper">Ponto 33 (Joaquina): PRÓPRIA</span>, 2026-08-25, 12 enterococos/100 mL',
    '19,0°C, ondas 1,3 m a cada 6 s, ondulação 1,0 m, corrente 1,2 km/h',
    'alta 06:40 (+0,9 m), baixa 12:50 (-0,7 m)',
    '22°C, vento 27 km/h, UV 5, 10% de chuva',
    'baixa, melhor chance às 07:00 · temporada das jubartes',
    '>-27.6296, -48.4487</a>',
  ])
    assert.ok(card.includes(needle), needle);
  pt.el('near').click();
  assert.deepEqual(pt.alerts, ['sem acesso à localização. a lista continua ordenada pela pontuação.']);
});

test('a schema-1 board without note_codes shows its notes verbatim', async () => {
  assert.ok(openCard(await runPage(BOARD_V1), 'Praia da Joaquina').includes('<li>breezy (27km/h)</li><li>cold water (19.0°C)</li>'));
});

test('the language: ?lang= beats a stored choice, which beats the browser', async () => {
  const pinned = await runPage(BOARD, { search: '?lang=pt-BR', store: { 'marola.lang': 'en' }, languages: ['en-US'] });
  assert.equal(pinned.el('hour-label').textContent, 'melhor horário de cada praia');
  const browserEn = await runPage(BOARD, { languages: ['en-US'] });
  assert.equal(browserEn.el('hour-label').textContent, 'best hour per beach');
});

test('a language flip redraws everything in place, from state, with no fetch', async () => {
  const r = await runPage(BOARD);
  openCard(r, 'Praia da Joaquina');
  slide(r, 0);
  const fetched = r.fetched.length;
  pickLang(r, 'en');
  assert.equal(r.fetched.length, fetched);
  assert.equal(r.el('hour-label').textContent, 'at 07:00');
  assert.match(r.el('days').innerHTML, /class="on"[^>]*>today <small>/);
  assert.ok(r.el('list').innerHTML.includes('Praia Brava <span class="dist">dark</span>'));
  assert.ok(r.el('card').innerHTML.includes('at <b>07:00</b> (best 10:00, 55)'));
  assert.ok(plain(tipOf(waveOf(r, 'Praia da Joaquina'))).includes('[jellyfish] jellyfish low'));
  assert.ok(r.el('footer').innerHTML.includes('· 2 beaches · data:'));
  pickLang(r, 'pt-BR');
  assert.equal(r.el('hour-label').textContent, 'às 07:00');
  assert.ok(r.el('card').innerHTML.includes('<dt>por quê</dt>'));
  assert.equal(points(r).filter((p) => tipOf(p).includes('Ponto 33')).length, 1, 'flips leave one water point, not three');
});

// MIP-0054 task 3: note codes per language; `notes` verbatim when a code has no key.
const unfitArgs = { source: 'IMA/SC', sampled_on: '2026-08-25', point: 'Ponto 12', location: 'Brava' };
const CASES: [string, Record<string, unknown>, string, string][] = [
  ['rough_seas', { wave_m: 2.26 }, 'rough seas (2.3m waves)', 'mar agitado (ondas de 2,3 m)'],
  ['choppy', { wave_m: 1.25 }, 'choppy (1.3m waves)', 'mar picado (ondas de 1,3 m)'],
  ['no_wave_data', {}, 'no wave data', 'sem dados de ondas'],
  ['strong_wind', { wind_kmh: 33.4 }, 'strong wind (33km/h)', 'vento forte (33 km/h)'],
  ['breezy', { wind_kmh: 22.5 }, 'breezy (23km/h)', 'brisa (23 km/h)'],
  ['no_wind_data', {}, 'no wind data', 'sem dados de vento'],
  ['cold_water', { sea_temp_c: 18.96 }, 'cold water (19.0°C)', 'água fria (19,0 °C)'],
  ['warm_water', { sea_temp_c: 28.04 }, 'warm water (28.0°C)', 'água quente (28,0 °C)'],
  ['no_sea_temp_data', {}, 'no sea temperature data', 'sem dados de temperatura da água'],
  ['rain_likely', { rain_pct: 64.6 }, '65% chance of rain', '65% de chance de chuva'],
  ['dark', {}, 'dark', 'à noite'],
  ['jellyfish_elevated', {}, 'elevated jellyfish likelihood', 'chance alta de água-viva'],
  ['jellyfish_some', {}, 'some jellyfish likelihood', 'alguma chance de água-viva'],
  ['water_stale', { sampled_on: '2026-08-05' }, 'water quality data stale (Aug 5)', 'laudo de balneabilidade antigo (5 de ago.)'],
  [
    'water_unfit',
    { enterococci_per_100ml: 800, ...unfitArgs },
    'water unfit for bathing: IMA/SC Aug 25, Ponto 12 (Brava), 800 enterococci/100mL',
    'água imprópria para banho: IMA/SC, 25 de ago., Ponto 12 (Brava), 800 enterococos/100 mL',
  ],
  ['water_unfit', unfitArgs, 'water unfit for bathing: IMA/SC Aug 25, Ponto 12 (Brava), count n/a', 'água imprópria para banho: IMA/SC, 25 de ago., Ponto 12 (Brava), contagem n/d'],
  [
    'water_mixed',
    { proper: 1, total: 3, avoid: ['Ponto 7 (Canto)', 'Ponto 9 (Centro)'] },
    '1/3 points PRÓPRIA; avoid Ponto 7 (Canto); Ponto 9 (Centro)',
    '1 de 3 pontos com laudo PRÓPRIA; evite Ponto 7 (Canto); Ponto 9 (Centro)',
  ],
  ['a_code_from_a_newer_board', {}, 'its english note', 'its english note'],
];
const coded = clone(BOARD);
coded.schema = 2;
const [c0, c1] = coded.beaches;
assert.ok(c0 && c1);
c0.best.note_codes = CASES.map(([code, args]) => ({ code, args }));
c0.best.notes = CASES.map(([code], i) => (i === CASES.length - 1 ? 'its english note' : `fallback ${code}`));
for (const b of coded.beaches) for (const h of b.hours) h.note_codes = h.notes.map(() => ({ code: 'dark', args: {} }));
c1.best.note_codes = [{ code: 'water_unfit', args: { enterococci_per_100ml: 800, ...unfitArgs } }];
const whyItems = (html: string): string[] =>
  (/<dt>(?:why|por quê)<\/dt><dd><ul>(.*?)<\/ul><\/dd>/.exec(html)?.[1] ?? '')
    .split('</li>')
    .filter(Boolean)
    .map((x) => x.replace('<li>', ''));

for (const [lang, col] of [
  ['en', 2],
  ['pt-BR', 3],
] as const)
  test(`${lang}: every note code renders in words`, async () => {
    const r = await runPage(coded, { search: `?lang=${lang}` });
    assert.deepEqual(r.errors, []);
    assert.deepEqual(
      whyItems(openCard(r, 'Praia da Joaquina')),
      CASES.map((c) => c[col]),
    );
    slide(r, 0);
    assert.equal(whyItems(r.el('card').innerHTML)[0], lang === 'en' ? 'dark' : 'à noite', "an hour's own note_codes at that hour");
  });

test('"near me" off takes the "you" dot off the map', async () => {
  const geo = { getCurrentPosition: (ok: (p: { coords: { latitude: number; longitude: number } }) => void) => ok({ coords: { latitude: -27.6, longitude: -48.5 } }) };
  const r = await runPage(BOARD, { geolocation: geo });
  const you = (): Marker[] => r.M.created.filter((m): m is Marker => m.kind === 'marker' && m.added && m.element.className.includes('here'));
  r.el('near').click();
  assert.equal(you().length, 1);
  r.el('near').click();
  assert.equal(you().length, 0);
});

test('another area drops the open beach from the URL', async () => {
  const r = await runPage(BOARD, { secondArea: true });
  openCard(r, 'Praia da Joaquina');
  assert.match(r.location.search, /beach=/);
  r.el('area').value = 'other';
  r.el('area').fire('change');
  await new Promise((done) => setTimeout(done, 20));
  assert.doesNotMatch(r.location.search, /beach=/);
  assert.equal(r.el('card').hidden, true);
});

test('board text is escaped wherever the page writes it as markup', async () => {
  const evil = clone(BOARD);
  const b = evil.beaches[0];
  assert.ok(b);
  b.name = 'Praia <img src=x onerror=alert(1)>';
  const r = await runPage(evil, { search: '?lang=en' });
  const where = { tooltip: tipOf(waveOf(r, 'Praia &lt;img')), list: r.el('list').innerHTML, card: openCard(r, 'Praia &lt;img') };
  for (const [part, html] of Object.entries(where)) {
    assert.ok(html.includes('Praia &lt;img'), part);
    assert.ok(!html.includes('<img'), part);
  }
});

test('a board newer than the page, or a missing one, is refused in words', async () => {
  const future = await runPage({ ...BOARD, schema: 3 }, { search: '?lang=en' });
  assert.equal(future.el('status').textContent, 'could not load the board: board schema 3, this page understands 1, 2');
  assert.equal(waves(future).length, 0);
  const missing = await runPage(BOARD, { noBoard: true });
  assert.equal(missing.el('status').textContent, 'não foi possível carregar os dados das praias: 404 data/fixture/2026-09-06.json. você rodou `just site-build` antes?');
});

test('x-pseudo: everything the map page builds came through t()', async () => {
  const pz = clone(coded);
  pz.generated_at = '2026-09-06T11:00:00-03:00'; // 07:00 is past, so the past badges render
  pz.trails = clone(trails);
  pz.lore = { kind: 'creature', text: 'Humpback whales sing in winter.', source: 'https://example.test/lore', lang: 'en' };
  const [b0, b1] = pz.beaches;
  assert.ok(b0 && b1);
  b0.best.note_codes?.pop();
  b0.best.notes.pop();
  b0.facilities = { parking: 3, toilets: 1, shower: 2, lifeguard: 1 };
  b0.water.points.push({ point: 'Ponto 34', location: 'Joaquina Norte', lat: -27.62, lon: -48.44, condition: 'unknown', sampled_on: '2026-08-25', enterococci_per_100ml: null, rain: null });
  b1.whales.season = false;
  const nulls = { temp_c: null, wave_m: null, period_s: null, wave_dir_deg: null, swell_m: null, swell_period_s: null, current_kmh: null, wind_kmh: null, wind_dir_deg: null, air_temp_c: null, uv: null, rain_pct: null };
  pz.beaches.push({
    name: 'Praia do Campeche',
    lat: -27.68,
    lon: -48.48,
    best: { hour: '11:00', score: 72, notes: [], note_codes: [] },
    hours: [{ h: '11:00', score: 72, notes: [], note_codes: [], sea_temp_c: null, wave_m: null, wind_kmh: null, jellyfish: 'High', whales: 'Moderate' }],
    water: { summary: 'no data', unfit: false, note: null, source: null, points: [] },
    tides: [],
    sea: nulls,
    jellyfish: 'High',
    whales: { now: 'Moderate', peak: null, season: false },
  });
  const ptDate = (iso: string): string => new Intl.DateTimeFormat('pt-BR', { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${iso}T00:00:00Z`));
  const data = [
    'Fixture Bay',
    'PRÓPRIA',
    'IMPRÓPRIA',
    'Ponto 7 (Canto)',
    'Ponto 9 (Centro)',
    pz.lore.text,
    'data/fixture/2026-09-06.json',
    ...Object.values(pz.sources).flatMap((s) => (s ? [s] : [])),
    ...trails.map((x) => x.name),
    ...['2026-08-05', '2026-08-25'].map(ptDate),
    ...pz.beaches.flatMap((b) => [b.name, b.water.source ?? '', b.water.summary === 'no data' ? '' : b.water.summary, ...b.water.points.flatMap((q) => [q.point, q.location])]),
  ].filter(Boolean);
  const visible = (html: string): string =>
    `${html.replace(/<[^>]*>/g, ' ').replace(/\[[a-z]+\]/g, ' ')} ${[...html.matchAll(/\s(?:aria-label|title|placeholder)="([^"]*)"/g)].map((m) => m[1]).join(' ')}`;

  const here = { getCurrentPosition: (ok: (p: { coords: { latitude: number; longitude: number } }) => void) => ok({ coords: { latitude: -27.6, longitude: -48.5 } }) };
  const px = await runPage(pz, { search: '?lang=x-pseudo', geolocation: here });
  assert.deepEqual(px.errors, []);
  assert.ok(px.el('hour-label').textContent.startsWith('⟦'));
  const seen: [string, string][] = [];
  const grab = (where: string): void => {
    for (const id of ['hour-label', 'days', 'list', 'footer']) seen.push([`${where}, ${id}`, px.el(id).innerHTML || px.el(id).textContent]);
    for (const m of px.M.created) if (m.kind === 'marker' && m.added) seen.push([`${where}, tooltip`, tipOf(m)]);
    for (const b of pz.beaches) seen.push([`${where}, card of ${b.name}`, openCard(px, b.name)]);
    for (const p of points(px)) seen.push([`${where}, water point`, tipOf(p)]);
    for (const f of (px.map?.sources.trails?.data as { features: { properties: { tip: string } }[] }).features) seen.push([`${where}, trail`, f.properties.tip]);
  };
  grab('best hours');
  slide(px, 0);
  grab('07:00');
  px.el('near').click();
  grab('near me');
  const noGeo = await runPage(BOARD, { search: '?lang=x-pseudo' });
  noGeo.el('near').click();
  const denied = await runPage(BOARD, { search: '?lang=x-pseudo', geolocation: deny });
  denied.el('near').click();
  const refused = await runPage({ ...BOARD, schema: 3 }, { search: '?lang=x-pseudo' });
  const missing = await runPage(BOARD, { search: '?lang=x-pseudo', noBoard: true });
  seen.push(['alerts', [...noGeo.alerts, ...denied.alerts].join(' ')], ['schema status', refused.el('status').textContent], ['404 status', missing.el('status').textContent]);
  assert.ok(noGeo.alerts.length === 1 && denied.alerts.length === 1 && seen.every(([, h]) => h.length > 0));
  const found = seen.map(([where, html]) => [where, leaks(visible(html), data).join(' ')]).filter(([, l]) => l);
  assert.deepEqual(found, []);
});
