// scripts/branding/generate-maruhi-favicons.mjs
//
// OTS-brand ("maruhi") favicon + mobile/social variety-pack generator.
//
// Sibling of generate-favicons.mjs that rasterizes scripts/branding/maruhi-mark.mjs
// instead of the neutral mark.mjs. This is company branding, so — unlike the
// neutral generator — it never writes into public/web/ (the shipped,
// brand-neutral default, protected by #3048/#3049 and check.mjs's CI drift
// guard). Output goes to:
//
//   - docker/public/                 the full rasterized pack, ready for the
//                                     Dockerfile's build-time brand overlay
//                                     (gitignored — never committed)
//   - src/assets/branding/maruhi/    the source SVGs, committed so the mark
//                                     is reviewable in version control
//
// USAGE
// -----
//   pnpm run gen:favicons:maruhi
//
// This folder is intentionally isolated from the root pnpm workspace (see
// generate-favicons.mjs) — this script reuses the same isolated sharp +
// png-to-ico deps, installed by the same `npm install` step.

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import sharp from 'sharp';
import pngToIco from 'png-to-ico';

import { squareIconSvg, maskIconSvg, ogImageSvg, webmanifest } from './maruhi-mark.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const OUT_PACK = process.env.MARK_OUT_PUBLIC_DIR
  ? resolve(REPO_ROOT, process.env.MARK_OUT_PUBLIC_DIR)
  : resolve(REPO_ROOT, 'docker', 'public');
const OUT_SOURCE = process.env.MARK_OUT_SRC_DIR
  ? resolve(REPO_ROOT, process.env.MARK_OUT_SRC_DIR)
  : resolve(REPO_ROOT, 'src', 'assets', 'branding', 'maruhi');

function write(path, contents) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, contents);
  const rel = path.startsWith(REPO_ROOT + '/') ? path.replace(REPO_ROOT + '/', '') : path;
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
  console.log('Generating OTS-brand (maruhi) favicon + variety pack…');

  const faviconSvg = squareIconSvg(512);
  const maskSvg = maskIconSvg(512);
  const ogSvg = ogImageSvg();

  // Source SVGs (committed so the mark is reviewable in version control).
  write(resolve(OUT_SOURCE, 'favicon-source.svg'), faviconSvg);
  write(resolve(OUT_SOURCE, 'safari-pinned-tab-source.svg'), maskSvg);
  write(resolve(OUT_SOURCE, 'og-image-source.svg'), ogSvg);

  // Served SVGs (modern browsers prefer these; no rasterization needed).
  write(resolve(OUT_PACK, 'favicon.svg'), faviconSvg);
  write(resolve(OUT_PACK, 'safari-pinned-tab.svg'), maskSvg);

  // Raster icons.
  const png16 = await pngFromSvg(faviconSvg, 16);
  const png32 = await pngFromSvg(faviconSvg, 32);
  const png48 = await pngFromSvg(faviconSvg, 48);
  write(resolve(OUT_PACK, 'apple-touch-icon.png'), await pngFromSvg(faviconSvg, 180));
  write(resolve(OUT_PACK, 'icon-192.png'), await pngFromSvg(faviconSvg, 192));
  write(resolve(OUT_PACK, 'icon-512.png'), await pngFromSvg(faviconSvg, 512));

  // Legacy multi-size .ico for old browsers / bookmarks.
  write(resolve(OUT_PACK, 'favicon.ico'), await pngToIco([png16, png32, png48]));

  // Social card.
  write(
    resolve(OUT_PACK, 'social-preview.png'),
    await sharp(Buffer.from(ogSvg), { density: 192 }).png().toBuffer()
  );

  // PWA manifest.
  write(resolve(OUT_PACK, 'site.webmanifest'), webmanifest());

  console.log('Done.');
  console.log(`  Pack:   ${OUT_PACK}`);
  console.log(`  Source: ${OUT_SOURCE}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
