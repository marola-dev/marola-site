import assert from 'node:assert/strict';
import { test } from 'node:test';
import { areaCode, band, type Board, haversineKm, hoursOf, isPast, ranked, shown } from '../site/src/board.ts';
import { rasterDay, RASTERS, tileUrl } from '../site/src/gibs.ts';
import { BOARD, BOARD_V1, clone, readJson, SCHEMA, SCHEMA_PATH, validate } from './harness.ts';

test('the fixtures are valid boards, schema 1 included, and the checker bites', () => {
  assert.deepEqual(validate(SCHEMA, BOARD), [], SCHEMA_PATH);
  assert.equal(BOARD_V1.schema, 1);
  assert.deepEqual(validate(SCHEMA, BOARD_V1), []);
  const broken: Partial<Board> = clone(BOARD);
  delete broken.beaches;
  assert.ok(validate(SCHEMA, broken).some((e) => e.includes('beaches')));
  const badEnum = clone(BOARD) as unknown as { beaches: { hours: Record<string, unknown>[] }[] };
  const h0 = badEnum.beaches[0]?.hours[0];
  if (h0) h0.wind_level = 'gale';
  assert.ok(validate(SCHEMA, badEnum).some((e) => e.includes('not in enum')));
});

// site/areas.json is what the app's --site reads live, and its Areas.parse silently drops a malformed entry.
test('site/areas.json: every entry has the fields Areas.parse needs, with unique ids', () => {
  const areas = readJson<Record<string, unknown>[]>(process.env.SITE_AREAS_JSON ?? 'site/areas.json');
  const zones = Intl.supportedValuesOf('timeZone');
  assert.ok(areas.length > 0);
  for (const e of areas) {
    assert.ok(typeof e.id === 'string' && /^[a-z0-9-]+$/.test(e.id), JSON.stringify(e.id));
    assert.ok(typeof e.name === 'string' && typeof e.lat === 'number' && typeof e.lon === 'number', e.id);
    assert.ok(typeof e.radius_km === 'number' && typeof e.beach_limit === 'number' && typeof e.tiles === 'string', e.id);
    assert.ok(typeof e.tz === 'string' && zones.includes(e.tz), e.id);
  }
  const ids = areas.map((a) => a.id);
  assert.equal(new Set(ids).size, ids.length);
});

test('a beach shows its best hour, or an hour of its own, or nothing when dark', () => {
  const [joaq, brava] = BOARD.beaches;
  assert.ok(joaq && brava);
  assert.deepEqual(shown(joaq, null), { h: '10:00', score: 55, notes: joaq.best.notes, note_codes: joaq.best.note_codes, best: true });
  assert.equal(shown(joaq, '07:00')?.score, 48);
  assert.equal(shown(brava, '07:00'), null);
  assert.deepEqual(hoursOf(BOARD), ['07:00', '09:00', '10:00', '12:00', '13:00']);
});

test('the list ranks by score, or by distance after "near me"', () => {
  const byScore = ranked(BOARD.beaches, (b) => b.best.score, null).map((r) => r.beach.name);
  assert.deepEqual(byScore, ['Praia da Joaquina', 'Praia Brava']);
  const near = ranked(BOARD.beaches, (b) => b.best.score, { lat: -27.41, lon: -48.42 });
  assert.equal(near[0]?.beach.name, 'Praia Brava');
  assert.ok((near[0]?.km ?? 99) < 2);
  assert.ok(Math.abs(haversineKm({ lat: 0, lon: 0 }, { lat: 1, lon: 0 }) - 111.19) < 0.01);
});

test('score bands: unfit or zero is red, no score is grey', () => {
  assert.deepEqual([band(70), band(69), band(40), band(39), band(1), band(0), band(80, true), band(null)], ['c70', 'c40', 'c40', 'c1', 'c1', 'c0', 'c0', 'cna']);
});

test('an hour is past only on the board of the day it was made', () => {
  const b = { ...BOARD, generated_at: '2026-09-06T11:00:00-03:00' };
  assert.ok(isPast(b, '07:00') && !isPast(b, '12:00'));
  assert.ok(!isPast({ ...b, day: '2026-09-07' }, '07:00'));
});

test('area codes: the known ones, else two letters of the name', () => {
  assert.equal(areaCode({ id: 'rio', name: 'Rio de Janeiro', lat: 0, lon: 0 }), 'RJ');
  assert.equal(areaCode({ id: 'fixture', name: 'Fixture Bay', lat: 0, lon: 0 }), 'FI');
  assert.equal(areaCode({ id: 'x', name: 'Ébano', lat: 0, lon: 0 }), 'EB');
});

test('GIBS imagery is dated back from the day the board was made', () => {
  const sst = RASTERS.sst;
  assert.ok(sst && RASTERS.clouds);
  assert.equal(rasterDay(sst, '2026-09-06'), '2026-09-04');
  assert.equal(rasterDay(RASTERS.clouds, '2026-03-01'), '2026-02-28');
  assert.equal(
    tileUrl(sst, '2026-09-06'),
    'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/GHRSST_L4_MUR_Sea_Surface_Temperature/default/2026-09-04/GoogleMapsCompatible_Level7/{z}/{y}/{x}.png',
  );
});
