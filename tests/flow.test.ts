import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildField, KINDS, mercX, mercY, rampPixels, sample } from '../site/src/flow.ts';

const one = buildField([{ lon: -48.5, lat: -27.6, mag: 20, dir: 0 }], 40);

test('a north wind (from 0°) flows south, at half the ramp for 20 of 40, fully confident at its beach', () => {
  assert.ok(one);
  const c = sample(one, mercX(-48.5), mercY(-27.6));
  assert.ok(c);
  assert.ok(Math.abs(c[0]) < 1e-6 && Math.abs(c[1] + 20) < 1e-3 && Math.abs(c[2] - 0.5) < 1e-3 && c[3] > 0.99, JSON.stringify(c));
});

test('the field fades out away from the beaches and stops outside its padded box', () => {
  assert.ok(one);
  const far = sample(one, mercX(-48.5 + 25 / (111.32 * Math.cos((27.6 * Math.PI) / 180))), mercY(-27.6));
  assert.ok(far && far[3] < 0.2, JSON.stringify(far));
  assert.equal(sample(one, mercX(-40), mercY(-27.6)), null);
});

test('a beach missing the number or the direction is left out, never read as zero', () => {
  assert.equal(
    buildField(
      [
        { lon: -48.5, lat: -27.6, mag: null, dir: 90 },
        { lon: -48.4, lat: -27.5, mag: 5, dir: null },
      ],
      40,
    ),
    null,
  );
});

test('a ramp is 256 opaque texels from the first stop to the last', () => {
  const ramp = rampPixels(['#000000', '#ffffff']);
  assert.equal(ramp.length, 1024);
  assert.deepEqual([ramp[0], ramp[3], ramp[1020], ramp[1023]], [0, 255, 255, 255]);
});

test('every kind has a ramp top and a particle budget', () => {
  for (const k of Object.values(KINDS)) assert.ok(k.max > 0 && k.trail > 1 && k.life[0] < k.life[1]);
});
