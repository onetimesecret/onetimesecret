// scripts/branding/generate-favicons.mjs
//
// Favicon + mobile/social variety-pack generator.
//
// WHY THIS EXISTS
// ---------------
// The open-source repo must ship a brand-NEUTRAL icon set. Shipping the
// onetimesecret.com mark as the default would mean every self-hosted install
// serves our company favicon — a trust/impersonation hazard (#3048/#3049).
// This script renders a generic "keyhole" mark (OFL-licensed glyph, the same
// one used by KeyholeIcon.vue) into the full set of files referenced by the
// HTML head. Operators override per deployment via BRAND_* env vars (URL
// overrides), by selecting a generated pack (BRAND_PACK / BRAND_ASSETS_DIR at
// runtime, or --build-arg BRAND_PACK at build time), or by mounting replacement
// files over public/web at runtime — see docs/product/branding-favicon.md.
//
// SINGLE SOURCE OF TRUTH
// ----------------------
// The mark geometry, palette, and text assets live in ./mark.mjs. Every emitted
// asset derives from them, so re-skinning the OSS default is a one-line change
// there followed by a re-run. `check.mjs` verifies the committed text assets
// still match mark.mjs (a CI drift guard).
//
// USAGE
// -----
//   cd scripts/branding
//   npm install          # installs the isolated sharp + png-to-ico deps
//   npm run generate     # writes assets into ../../public/web and ../../src/assets/branding
//
// This folder is intentionally isolated from the root pnpm workspace so the
// heavy native `sharp` dependency never enters the application bundle or the
// project lockfile.
//
// CUSTOM PACKS
// ------------
// This is a reusable generator, not a single-mark tool. Every knob mark.mjs
// exposes (glyph path, native size, palette, social gradient, product name,
// glyph coverage) is overridable via MARK_* env vars — so a differently-branded
// pack is a set of overrides, never a forked copy of this file.
//
//   - One-off overrides: set MARK_* inline, e.g.
//       MARK_PRIMARY_COLOR='#DC4A22' MARK_PATH='M32 2C…' \
//         MARK_NATIVE_WIDTH=64 MARK_NATIVE_HEIGHT=64 pnpm run gen:favicons
//
//   - A named bundle: drop the overrides in scripts/branding/presets/<name>.mjs
//     (default-exporting a plain { MARK_*: value } object) and select it with
//     `--preset <name>` (or MARK_PRESET=<name>). The OTS "maruhi" mark ships as
//     one — see `pnpm run gen:favicons:maruhi`.
//
// A custom/preset run writes to public/web + src/assets/branding by default,
// which would overwrite the committed neutral defaults. Point it elsewhere with
// MARK_OUT_PUBLIC_DIR / MARK_OUT_SRC_DIR — each is resolved against the repo root
// when relative, or used as-is when absolute (handy for a throwaway/CI dir). A
// preset typically sets these itself.

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import sharp from 'sharp';
import pngToIco from 'png-to-ico';

import { applyPreset } from './preset-loader.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');

// A preset is a named bag of MARK_* overrides (presets/<name>.mjs, see
// preset-loader.mjs). Select it with `--preset <name>` — shell-portable, so it
// works where inline `MARK_PRESET=… node …` env syntax doesn't (e.g. Windows
// cmd) — or with the MARK_PRESET env var. Its values are applied to process.env
// BEFORE importing mark.mjs, whose exported constants read env at module-eval
// time. Precedence: explicit env var > preset > mark.mjs neutral default.
function presetFromArgv(argv) {
  const i = argv.indexOf('--preset');
  if (i !== -1) return argv[i + 1];
  return process.env.MARK_PRESET;
}

const presetName = presetFromArgv(process.argv.slice(2));
if (presetName) {
  try {
    const { applied, skipped } = await applyPreset(presetName);
    console.log(`Applied preset '${presetName}' (${applied.length} value(s)).`);
    if (skipped.length) {
      console.warn(`  ⚠ ignored unknown preset key(s): ${skipped.join(', ')}`);
    }
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }
}

// Resolved after the preset, so a preset can target its own output dirs. A
// custom/preset run must NOT overwrite the committed neutral defaults — redirect
// it with MARK_OUT_PUBLIC_DIR / MARK_OUT_SRC_DIR (paths relative to the repo root).
const PUBLIC_WEB = process.env.MARK_OUT_PUBLIC_DIR
  ? resolve(REPO_ROOT, process.env.MARK_OUT_PUBLIC_DIR)
  : resolve(REPO_ROOT, 'public', 'web');
const SRC_BRANDING = process.env.MARK_OUT_SRC_DIR
  ? resolve(REPO_ROOT, process.env.MARK_OUT_SRC_DIR)
  : resolve(REPO_ROOT, 'src', 'assets', 'branding');

// Dynamic import: must come AFTER applyPreset so mark.mjs reads the preset's env.
const { squareIconSvg, maskIconSvg, ogImageSvg, webmanifest } = await import('./mark.mjs');

function write(path, contents) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents);
  const rel = path.replace(REPO_ROOT + '/', '');
  const size = Buffer.isBuffer(contents) ? `${contents.length} B` : `${Buffer.byteLength(contents)} B`;
  console.log(`  wrote ${rel} (${size})`);
}

async function pngFromSvg(svg, size) {
  return sharp(Buffer.from(svg), { density: 384 })
    .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
}

async function main() {
  console.log('Generating favicon + variety pack…');

  const faviconSvg = squareIconSvg(512);
  const maskSvg = maskIconSvg(512);
  const ogSvg = ogImageSvg();

  // Source SVGs (committed so the mark is reviewable in version control).
  write(resolve(SRC_BRANDING, 'favicon-source.svg'), faviconSvg);
  write(resolve(SRC_BRANDING, 'safari-pinned-tab-source.svg'), maskSvg);
  write(resolve(SRC_BRANDING, 'og-image-source.svg'), ogSvg);

  // Served SVGs (modern browsers prefer these; no rasterization needed).
  write(resolve(PUBLIC_WEB, 'favicon.svg'), faviconSvg);
  write(resolve(PUBLIC_WEB, 'safari-pinned-tab.svg'), maskSvg);

  // Raster icons.
  const png16 = await pngFromSvg(faviconSvg, 16);
  const png32 = await pngFromSvg(faviconSvg, 32);
  const png48 = await pngFromSvg(faviconSvg, 48);
  write(resolve(PUBLIC_WEB, 'apple-touch-icon.png'), await pngFromSvg(faviconSvg, 180));
  write(resolve(PUBLIC_WEB, 'icon-192.png'), await pngFromSvg(faviconSvg, 192));
  write(resolve(PUBLIC_WEB, 'icon-512.png'), await pngFromSvg(faviconSvg, 512));

  // Legacy multi-size .ico for old browsers / bookmarks.
  write(resolve(PUBLIC_WEB, 'favicon.ico'), await pngToIco([png16, png32, png48]));

  // Social card.
  write(
    resolve(PUBLIC_WEB, 'social-preview.png'),
    await sharp(Buffer.from(ogSvg), { density: 192 }).png().toBuffer()
  );

  // PWA manifest.
  write(resolve(PUBLIC_WEB, 'site.webmanifest'), webmanifest());

  console.log('Done.');
  console.log(`  Pack:   ${PUBLIC_WEB}`);
  console.log(`  Source: ${SRC_BRANDING}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
