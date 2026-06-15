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
// The keyhole path and the neutral palette are defined ONCE below. Every
// emitted asset (SVG, PNG, ICO, webmanifest, OG image) derives from them, so
// re-skinning the OSS default is a one-line change here followed by a re-run.
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

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const PUBLIC_WEB = resolve(REPO_ROOT, 'public', 'web');
const SRC_BRANDING = resolve(REPO_ROOT, 'src', 'assets', 'branding');

// --- Single source of truth -------------------------------------------------

// Keyhole glyph from WebHostingHub Glyphs (OFL). Native viewBox is 0 0 512 1024
// (tall: a circle over a flared stem). Matches src/shared/components/icons/KeyholeIcon.vue.
const KEYHOLE_PATH =
  'm363 488l149 472q0 27-18.5 45.5T448 1024H64q-26 0-45-18.5T0 960l149-472q-67-31-108-93.5T0 256Q0 150 75 75T256 0t181 75t75 181q0 76-41 138.5T363 488';

// Neutral palette — must NOT be OTS orange (#DC4A22). Mirrors the frontend
// NEUTRAL_BRAND_DEFAULTS (#3B82F6) so the shipped favicon and the first-paint
// Vue theme agree. See src/shared/constants/brand.ts.
const NEUTRAL_BLUE = '#3B82F6';
const MARK_ON_COLOR = '#FFFFFF';

// Centers the native 512x1024 keyhole inside a `size`x`size` canvas, scaled so
// the glyph occupies ~`coverage` of the height, leaving even padding.
function keyholeTransform(size, coverage = 0.58) {
  const targetHeight = size * coverage;
  const scale = targetHeight / 1024;
  const width = 512 * scale;
  const tx = (size - width) / 2;
  const ty = (size - targetHeight) / 2;
  return `translate(${tx.toFixed(2)} ${ty.toFixed(2)}) scale(${scale.toFixed(5)})`;
}

// Square app/favicon icon: rounded brand-color tile with a light keyhole.
function squareIconSvg(size = 512) {
  const radius = Math.round(size * 0.1875); // ~iOS superellipse-ish corner
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="App icon">
  <rect width="${size}" height="${size}" rx="${radius}" ry="${radius}" fill="${NEUTRAL_BLUE}"/>
  <path transform="${keyholeTransform(size)}" fill="${MARK_ON_COLOR}" d="${KEYHOLE_PATH}"/>
</svg>
`;
}

// Monochrome mask for Safari pinned tabs: single black path on transparent.
// Safari recolors it via the `color` attribute on the <link rel="mask-icon">.
function maskIconSvg(size = 512) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="App icon (monochrome)">
  <path transform="${keyholeTransform(size, 0.7)}" fill="#000000" d="${KEYHOLE_PATH}"/>
</svg>
`;
}

// Open Graph / Twitter social card (1200x630), purposely text-free so it stays
// neutral; operators set BRAND_OG_IMAGE_URL to ship their own card.
function ogImageSvg() {
  const w = 1200;
  const h = 630;
  const markSize = 320;
  const tx = (w - markSize) / 2;
  const ty = (h - markSize) / 2;
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="Social preview">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1E3A8A"/>
      <stop offset="1" stop-color="${NEUTRAL_BLUE}"/>
    </linearGradient>
  </defs>
  <rect width="${w}" height="${h}" fill="url(#bg)"/>
  <g transform="translate(${tx} ${ty})">
    <path transform="${keyholeTransform(markSize, 0.78)}" fill="${MARK_ON_COLOR}" d="${KEYHOLE_PATH}"/>
  </g>
</svg>
`;
}

// Neutral PWA manifest. Name/colors are deliberately generic; operators
// override by replacing this file via the brand directory (see docs).
function webmanifest() {
  return JSON.stringify(
    {
      name: 'My App',
      short_name: 'My App',
      icons: [
        { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
        { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
        { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
      ],
      theme_color: NEUTRAL_BLUE,
      background_color: '#ffffff',
      display: 'standalone',
      start_url: '/',
    },
    null,
    2
  ) + '\n';
}

// --- Emit -------------------------------------------------------------------

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
