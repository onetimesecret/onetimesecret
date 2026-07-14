// scripts/branding/check.mjs
//
// CI drift guard for the neutral branding assets.
//
// Verifies that the committed TEXT assets (the served SVGs and the web
// manifest) still match what mark.mjs produces. This catches the common
// mistake of editing the mark geometry / palette in mark.mjs without
// re-running the generator. It is dependency-free (no `sharp`), so it runs in
// CI without installing the isolated generator deps.
//
// The raster assets (.png/.ico) are derived from the same source SVGs but
// require `sharp` to verify; run `npm run generate` and `git diff` locally to
// confirm those. This check intentionally covers only the deterministic,
// node-only text assets.
//
// Exit code 0 = in sync, 1 = drift detected.

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { squareIconSvg, maskIconSvg, webmanifest } from './mark.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
// The neutral text assets live in the tracked DEFAULT brand pack (#3774), which
// is where `pnpm run gen:favicons` now writes them.
const DEFAULT_PACK = resolve(__dirname, '..', '..', 'public', 'branding', 'default');

const expected = {
  'favicon.svg': squareIconSvg(512),
  'safari-pinned-tab.svg': maskIconSvg(512),
  'site.webmanifest': webmanifest(),
};

const drift = [];
for (const [name, want] of Object.entries(expected)) {
  let got;
  try {
    got = readFileSync(resolve(DEFAULT_PACK, name), 'utf8');
  } catch {
    drift.push(`${name}: missing on disk`);
    continue;
  }
  if (got !== want) {
    drift.push(`${name}: out of sync with scripts/branding/mark.mjs`);
  }
}

if (drift.length) {
  console.error('Branding asset drift detected:');
  for (const d of drift) console.error(`  - ${d}`);
  console.error('\nRe-run `pnpm run gen:favicons` (from the repo root) and commit the result.');
  process.exit(1);
}

console.log('Branding text assets are in sync with scripts/branding/mark.mjs.');
