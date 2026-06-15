// scripts/branding/generate-favicons.mjs
//
// Neutral favicon + mobile/social variety-pack generator.
//
// WHY THIS EXISTS
// ---------------
// The open-source repo must ship a brand-NEUTRAL icon set. Shipping the
// onetimesecret.com mark as the default would mean every self-hosted install
// serves our company favicon — a trust/impersonation hazard (#3048/#3049).
// This script renders a generic "keyhole" mark (OFL-licensed glyph, the same
// one used by KeyholeIcon.vue) into the full set of files referenced by the
// HTML head. Operators override per deployment via BRAND_* env vars (URL
// overrides) or by dropping replacement files into the brand directory
// (docker/branding/ at build time, or public/web at runtime) — see
// docs/customization/branding-favicon.md.
//
// SINGLE SOURCE OF TRUTH
// ----------------------
// The mark geometry, neutral palette, and text assets live in ./mark.mjs.
// Every emitted asset derives from them, so re-skinning the OSS default is a
// one-line change there followed by a re-run. `check.mjs` verifies the
// committed text assets still match mark.mjs (a CI drift guard).
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

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import sharp from 'sharp';
import pngToIco from 'png-to-ico';

import { squareIconSvg, maskIconSvg, ogImageSvg, webmanifest } from './mark.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const PUBLIC_WEB = resolve(REPO_ROOT, 'public', 'web');
const SRC_BRANDING = resolve(REPO_ROOT, 'src', 'assets', 'branding');

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
  console.log('Generating neutral favicon + variety pack…');

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
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
