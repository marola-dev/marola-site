import assert from 'node:assert/strict';
import { test } from 'node:test';
import { format, resolveLang, SUPPORTED } from '../site/src/i18n.ts';
import { CATALOGS } from './harness.ts';

const S = ['pt-BR', 'en'];
const rl = (o: Parameters<typeof resolveLang>[0] extends infer T ? Omit<T, 'supported'> : never): string => resolveLang({ supported: S, ...o });

test('resolveLang: ?lang=, then the stored choice, then the browser, then pt-BR', () => {
  assert.equal(rl({}), 'pt-BR');
  assert.equal(rl({ param: 'en' }), 'en');
  assert.equal(rl({ param: 'pt-BR', stored: 'en', languages: ['en-US'] }), 'pt-BR');
  assert.equal(rl({ stored: 'en', languages: ['pt-BR'] }), 'en');
  assert.equal(rl({ languages: ['en-US'] }), 'en');
  assert.equal(rl({ languages: ['fr-FR'] }), 'pt-BR');
  assert.equal(rl({ languages: ['fr', 'pt-PT', 'en'] }), 'pt-BR', 'the first shipped primary subtag wins');
  assert.equal(rl({ languages: ['fr', 'en-GB'] }), 'en');
  assert.equal(rl({ param: 'de' }), 'pt-BR', 'an unshipped ?lang= falls through');
});

test('resolveLang: x-pseudo only from ?lang=, never from the store or the browser', () => {
  assert.equal(rl({ param: 'x-pseudo' }), 'x-pseudo');
  assert.equal(rl({ stored: 'x-pseudo', languages: ['x-pseudo'] }), 'pt-BR');
  assert.ok(!SUPPORTED.includes('x-pseudo') && SUPPORTED.includes('pt-BR') && SUPPORTED.includes('en'));
});

test('format: plural, select, numbers in the language, missing args left visible', () => {
  const n = '{n, plural, one {# praia} other {# praias}}';
  assert.equal(format(n, { n: 1 }), '1 praia');
  assert.equal(format(n, { n: 2 }), '2 praias');
  assert.equal(format('{n, plural, one {# beach} other {# beaches}}', { n: 1 }, 'en'), '1 beach');
  assert.equal(format('ondas {x} m', { x: 1.3 }), 'ondas 1,3 m', 'a decimal comma in pt-BR');
  assert.equal(format('waves {x} m', { x: 1.3 }, 'en'), 'waves 1.3 m');
  assert.equal(format('{w, select, yes {sim} other {não}}', { w: 'yes' }), 'sim');
  assert.equal(format('{w, select, yes {sim} other {não}}', { w: 'maybe' }), 'não');
  assert.equal(format('olá {name}'), 'olá {name}');
  assert.equal(format('{n, plural, =0 {nenhuma} other {#}}', { n: 0 }), 'nenhuma');
  assert.throws(() => format('{n, plural, one {# x}'), /i18n/);
});

test('every catalog message parses and pt-BR, en share their keys', () => {
  assert.deepEqual(Object.keys(CATALOGS.en).sort(), Object.keys(CATALOGS['pt-BR']).sort());
  for (const [lang, cat] of Object.entries(CATALOGS)) for (const [k, v] of Object.entries(cat)) assert.doesNotThrow(() => format(v, {}, lang), `${lang} ${k}`);
});

// Lowercase house style in the catalogs; these are names marola did not choose.
const CASE_OK = ['°C', 'UV', 'km/h', 'mL', 'PRÓPRIA', 'IMPRÓPRIA', 'GitHub', 'Open-Meteo', 'IMA/SC', 'OpenStreetMap', 'Mapbox', 'NASA', 'VIIRS', 'MUR', 'El Niño', 'La Niña', 'Niño'];
test('every catalog value is lowercase outside the allowlist', () => {
  for (const [lang, cat] of Object.entries(CATALOGS)) {
    const shouty = Object.entries(cat).filter(([k, v]) => {
      if (k.startsWith('dir.')) return !/^[A-Z]{1,2}$/.test(v); // compass abbreviations, shown uppercase
      const rest = CASE_OK.reduce((acc, w) => acc.split(w).join(''), v);
      return rest !== rest.toLowerCase();
    });
    assert.deepEqual(shouty.map(([k]) => k), [], lang);
  }
});
