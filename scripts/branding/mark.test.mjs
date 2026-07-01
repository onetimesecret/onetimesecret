// scripts/branding/mark.test.mjs
//
// Dependency-free unit tests for the favicon generator's pure logic — the mark
// builders (mark.mjs) and the preset loader's validation (preset-loader.mjs).
// Uses only node:test + node:assert (no sharp), so it runs in CI without the
// isolated generator deps:
//
//   node --test scripts/branding/        # or: pnpm run gen:favicons:test
//
// These complement check.mjs (which guards committed output) by exercising the
// branches that check.mjs can't reach: alternate env, presets, and bad input.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  numEnv,
  markTransform,
  squareIconSvg,
  maskIconSvg,
  ogImageSvg,
  webmanifest,
  NATIVE_WIDTH,
  NATIVE_HEIGHT,
  KEYHOLE_PATH,
  PRIMARY_COLOUR,
} from './mark.mjs';

import { applyPreset, validatePresetName, KNOWN_MARK_KEYS } from './preset-loader.mjs';

test('numEnv: unset / empty / non-numeric fall back to the default', () => {
  delete process.env.__MARK_TEST;
  assert.equal(numEnv('__MARK_TEST', 5), 5);
  process.env.__MARK_TEST = '';
  assert.equal(numEnv('__MARK_TEST', 5), 5);
  process.env.__MARK_TEST = 'abc';
  assert.equal(numEnv('__MARK_TEST', 5), 5);
  delete process.env.__MARK_TEST;
});

test('numEnv: an explicit 0 is honored (the bug plain `Number(x) || def` has)', () => {
  process.env.__MARK_TEST = '0';
  assert.equal(numEnv('__MARK_TEST', 5), 0);
  process.env.__MARK_TEST = '2.5';
  assert.equal(numEnv('__MARK_TEST', 5), 2.5);
  delete process.env.__MARK_TEST;
});

test('markTransform: centers and scales the glyph by coverage', () => {
  const t = markTransform(300, 0.6);
  const m = t.match(/^translate\((-?[\d.]+) (-?[\d.]+)\) scale\((-?[\d.]+)\)$/);
  assert.ok(m, `unexpected transform format: ${t}`);
  const [, tx, ty, scale] = m.map(Number);

  const expectedScale = (300 * 0.6) / NATIVE_HEIGHT;
  assert.ok(Math.abs(scale - expectedScale) < 1e-4, 'scale tracks coverage/native-height');
  // Even horizontal + vertical padding = centered.
  assert.ok(Math.abs(tx - (300 - NATIVE_WIDTH * scale) / 2) < 0.01, 'horizontally centered');
  assert.ok(Math.abs(ty - (300 - 300 * 0.6) / 2) < 0.01, 'vertically centered');
});

test('markTransform: higher coverage → larger scale', () => {
  const scaleOf = (t) => Number(t.match(/scale\((-?[\d.]+)\)/)[1]);
  assert.ok(scaleOf(markTransform(512, 0.8)) > scaleOf(markTransform(512, 0.4)));
});

test('squareIconSvg: neutral tile + mark, no stray attribution comment', () => {
  const svg = squareIconSvg(64);
  assert.match(svg, /viewBox="0 0 64 64"/);
  assert.ok(svg.includes(`fill="${PRIMARY_COLOUR}"`), 'tile uses primary colour');
  assert.ok(svg.includes(KEYHOLE_PATH), 'draws the mark path');
  assert.ok(!svg.includes('<!--'), 'no attribution comment when MARK_ATTRIBUTION is unset');
});

test('maskIconSvg: monochrome black mark', () => {
  const svg = maskIconSvg(64);
  assert.ok(svg.includes('fill="#000000"'));
  assert.match(svg, /aria-label="App icon \(monochrome\)"/);
});

test('ogImageSvg: fixed 1200x630 card with a two-stop gradient', () => {
  const svg = ogImageSvg();
  assert.match(svg, /width="1200" height="630"/);
  assert.equal((svg.match(/stop-color=/g) || []).length, 2);
  assert.ok(svg.includes(KEYHOLE_PATH));
});

test('webmanifest: valid JSON with neutral defaults', () => {
  const m = JSON.parse(webmanifest());
  assert.equal(m.name, 'Secure Links');
  assert.equal(m.theme_color, PRIMARY_COLOUR);
  assert.equal(m.icons.length, 3);
});

test('validatePresetName: accepts safe names, rejects traversal', () => {
  assert.equal(validatePresetName('maruhi'), 'maruhi');
  assert.equal(validatePresetName('acme-dark'), 'acme-dark');
  for (const bad of ['../evil', 'a/b', 'foo.bar', '', 'sp ace']) {
    assert.throws(() => validatePresetName(bad), /Invalid preset name/);
  }
});

test('applyPreset: applies known keys as defaults, skips unknown', async () => {
  const env = {};
  const importer = async () => ({
    default: { MARK_PRIMARY_COLOR: '#123456', MARK_PRIMARY_COLOUR: '#oops' },
  });
  const { applied, skipped } = await applyPreset('fake', { env, importer });

  assert.equal(env.MARK_PRIMARY_COLOR, '#123456');
  assert.deepEqual(applied, ['MARK_PRIMARY_COLOR']);
  assert.deepEqual(skipped, ['MARK_PRIMARY_COLOUR']); // British-spelling typo caught
  assert.ok(KNOWN_MARK_KEYS.has('MARK_PRIMARY_COLOR'));
});

test('applyPreset: an explicit env var overrides the preset', async () => {
  const env = { MARK_PRIMARY_COLOR: '#000000' };
  const importer = async () => ({ default: { MARK_PRIMARY_COLOR: '#ffffff' } });
  const { applied } = await applyPreset('fake', { env, importer });

  assert.equal(env.MARK_PRIMARY_COLOR, '#000000');
  assert.deepEqual(applied, []);
});

test('applyPreset: rejects a non-object default export', async () => {
  const importer = async () => ({ default: 42 });
  await assert.rejects(() => applyPreset('fake', { env: {}, importer }), /plain object/);
});

test('applyPreset: rejects an unsafe preset name before importing', async () => {
  let imported = false;
  const importer = async () => {
    imported = true;
    return { default: {} };
  };
  await assert.rejects(() => applyPreset('../evil', { env: {}, importer }), /Invalid preset name/);
  assert.equal(imported, false, 'must not import when the name is rejected');
});
