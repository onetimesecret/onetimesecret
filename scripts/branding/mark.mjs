// scripts/branding/mark.mjs
//
// Pure, dependency-free builders for the neutral keyhole brand mark.
//
// This module is the SINGLE SOURCE OF TRUTH for the mark geometry, the neutral
// palette, and the text assets (SVGs + web manifest). It deliberately imports
// nothing (no `sharp`) so it can run anywhere — the rasterizing generator
// (generate-favicons.mjs) and the CI drift check (check.mjs) both import it.
//
// ## Usage
//
// Regenerate the OSS-default pack (neutral blue keyhole):
//
//   pnpm run gen:favicons          # from repo root; installs isolated deps, rasterizes
//
// Generate a custom-coloured pack without editing this file, by overriding the
// constants below via env vars:
//
//   MARK_PRIMARY_COLOR='#3B82F6' pnpm run gen:favicons        # re-tint the mark
//   MARK_BACKGROUND_COLOR='#0B1020' pnpm run gen:favicons     # dark tile/keyhole
//   MARK_PATH='m...' pnpm run gen:favicons                    # swap the glyph
//
// A swapped-in glyph is rarely drawn on the keyhole's own native canvas (512
// wide x 1024 tall), so pair MARK_PATH with its real dimensions or the
// transform below will scale/center it as if it were keyhole-shaped:
//
//   MARK_NATIVE_WIDTH=64 MARK_NATIVE_HEIGHT=64 MARK_PATH='m...' pnpm run gen:favicons
//
// These are deliberately MARK_*-prefixed, NOT the runtime BRAND_* vars: a dev or
// CI shell often has BRAND_PRIMARY_COLOR set, and reusing it would silently
// regenerate non-neutral defaults and trip the drift check. Overrides here are
// explicit opt-in for producing your own pack. Drop the output into
// `docker/public/` (build-time overlay) to bake it into the image. CI runs
// `pnpm run gen:favicons:check` (with no MARK_* set) to guard the committed
// neutral defaults. See docs/architecture/branding.md.

// Keyhole glyph from WebHostingHub Glyphs (OFL). Native viewBox is 0 0 512 1024
// (tall: a circle over a flared stem). Matches src/shared/components/icons/KeyholeIcon.vue.
export const KEYHOLE_PATH =
  process.env.MARK_PATH ||
  'm363 488l149 472q0 27-18.5 45.5T448 1024H64q-26 0-45-18.5T0 960l149-472q-67-31-108-93.5T0 256Q0 150 75 75T256 0t181 75t75 181q0 76-41 138.5T363 488';

// Neutral palette. Mirrors the frontend NEUTRAL_BRAND_DEFAULTS (#3B82F6) so
// the shipped favicon and the first-paint Vue theme agree. Override via env
// vars to generate a custom pack (see Usage above).
// See src/shared/constants/brand.ts.
export const PRIMARY_COLOUR = process.env.MARK_PRIMARY_COLOR || '#3B82F6'; // a neutral blue
export const BACKGROUND_COLOUR = process.env.MARK_BACKGROUND_COLOR || '#FFFFFF';

// Native bounding box of KEYHOLE_PATH's geometry. Defaults match the keyhole
// (tall: 512 wide x 1024 high); a swapped-in MARK_PATH with a different native
// size must override both, or markTransform below will scale/center it as if
// it were keyhole-shaped.
export const NATIVE_WIDTH = Number(process.env.MARK_NATIVE_WIDTH) || 512;
export const NATIVE_HEIGHT = Number(process.env.MARK_NATIVE_HEIGHT) || 1024;

// Centers the native-size glyph inside a `size`x`size` canvas, scaled so it
// occupies ~`coverage` of the height, leaving even padding.
export function markTransform(size, coverage = 0.58) {
  const targetHeight = size * coverage;
  const scale = targetHeight / NATIVE_HEIGHT;
  const width = NATIVE_WIDTH * scale;
  const tx = (size - width) / 2;
  const ty = (size - targetHeight) / 2;
  return `translate(${tx.toFixed(2)} ${ty.toFixed(2)}) scale(${scale.toFixed(5)})`;
}

// Square app/favicon icon: rounded brand-color tile with a light keyhole.
export function squareIconSvg(size = 512) {
  const radius = Math.round(size * 0.1875); // ~iOS superellipse-ish corner
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="App icon">
  <rect width="${size}" height="${size}" rx="${radius}" ry="${radius}" fill="${PRIMARY_COLOUR}"/>
  <path transform="${markTransform(size)}" fill="${BACKGROUND_COLOUR}" d="${KEYHOLE_PATH}"/>
</svg>
`;
}

// Monochrome mask for Safari pinned tabs: single black path on transparent.
// Safari recolors it via the `color` attribute on the <link rel="mask-icon">.
export function maskIconSvg(size = 512) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="App icon (monochrome)">
  <path transform="${markTransform(size, 0.7)}" fill="#000000" d="${KEYHOLE_PATH}"/>
</svg>
`;
}

// Open Graph / Twitter social card (1200x630), purposely text-free so it stays
// neutral; operators set BRAND_OG_IMAGE_URL to ship their own card.
export function ogImageSvg() {
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
      <stop offset="1" stop-color="${PRIMARY_COLOUR}"/>
    </linearGradient>
  </defs>
  <rect width="${w}" height="${h}" fill="url(#bg)"/>
  <g transform="translate(${tx} ${ty})">
    <path transform="${markTransform(markSize, 0.78)}" fill="${BACKGROUND_COLOUR}" d="${KEYHOLE_PATH}"/>
  </g>
</svg>
`;
}

// Neutral PWA manifest. Name/colors are deliberately generic; the runtime
// /site.webmanifest route overlays brand.product_name / brand.primary_color
// when configured (see Core::Controllers::Page#webmanifest), and operators can
// also replace this file via the brand directory.
export function webmanifest() {
  return (
    JSON.stringify(
      {
        name: 'My App',
        short_name: 'My App',
        icons: [
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
        theme_color: PRIMARY_COLOUR,
        background_color: '#ffffff',
        display: 'standalone',
        start_url: '/',
      },
      null,
      2
    ) + '\n'
  );
}
