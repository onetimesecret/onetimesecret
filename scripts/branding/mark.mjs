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
// Generate a custom pack without editing this file by overriding the constants
// below via env vars (all optional; unset = the neutral defaults above):
//
//   MARK_PATH                 glyph path data              (default: keyhole)
//   MARK_NATIVE_WIDTH/HEIGHT  native px bounds of that path (default: 512x1024)
//   MARK_PRIMARY_COLOR        tile / gradient colour       (default: #3B82F6)
//   MARK_BACKGROUND_COLOR     mark colour                  (default: #FFFFFF)
//   MARK_OG_GRADIENT_DARK     social-card top gradient stop (default: #1E3A8A)
//   MARK_PRODUCT_NAME         webmanifest name             (default: Secure Links)
//   MARK_SHORT_NAME           webmanifest short_name       (default: product name)
//   MARK_COVERAGE             icon glyph height ratio       (default: 0.58)
//   MARK_MASK_COVERAGE        pinned-tab glyph height ratio (default: 0.70)
//   MARK_OG_COVERAGE          social-card glyph height ratio (default: 0.78)
//
// e.g. swap the glyph, remembering its real native bounds — a square emoji is
// not the keyhole's tall 512x1024, so the transform would otherwise mis-scale
// and mis-center it:
//
//   MARK_NATIVE_WIDTH=64 MARK_NATIVE_HEIGHT=64 MARK_PATH='M32 2C…' pnpm run gen:favicons
//
// A named bundle of these overrides (e.g. the OTS "maruhi" mark) lives as a
// preset in scripts/branding/presets/<name>.mjs; run it with MARK_PRESET=<name>
// (see generate-favicons.mjs). Custom runs should also set MARK_OUT_PUBLIC_DIR /
// MARK_OUT_SRC_DIR so they don't overwrite the committed neutral files.
//
// These are deliberately MARK_*-prefixed, NOT the runtime BRAND_* vars: a dev or
// CI shell often has BRAND_PRIMARY_COLOR set, and reusing it would silently
// regenerate non-neutral defaults and trip the drift check. CI runs
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
// Top stop of the social-card gradient (bottom stop is PRIMARY_COLOUR).
const OG_GRADIENT_DARK = process.env.MARK_OG_GRADIENT_DARK || '#1E3A8A';

// Web manifest text. Neutral defaults are deliberately generic (the runtime
// /site.webmanifest route overlays the real brand.product_name when configured).
export const PRODUCT_NAME = process.env.MARK_PRODUCT_NAME || 'Secure Links';
const SHORT_NAME = process.env.MARK_SHORT_NAME || PRODUCT_NAME;

// Optional licensing/credit line for a swapped-in glyph. When set, it is emitted
// as an SVG comment in every generated SVG, so attribution travels with the
// redistributable source (e.g. the CC-BY maruhi mark). Empty by default, so the
// neutral pack's SVGs are byte-for-byte unchanged. `--` is collapsed because it
// can't appear inside an XML comment.
const ATTRIBUTION = (process.env.MARK_ATTRIBUTION || '').replace(/-{2,}/g, '-').trim();
const svgAttribution = ATTRIBUTION ? `<!-- ${ATTRIBUTION} -->\n` : '';

// Reads a numeric env var, allowing an explicit 0 but falling back to `def` for
// unset / empty / non-numeric values. (Plain `Number(x) || def` can't represent
// 0 and silently treats "" as 0.)
export function numEnv(name, def) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return def;
  const n = Number(raw);
  return Number.isFinite(n) ? n : def;
}

// Native bounding box of KEYHOLE_PATH's geometry. Defaults match the keyhole
// (tall: 512 wide x 1024 high); a swapped-in MARK_PATH with a different native
// size must override both, or markTransform below will scale/center it as if
// it were keyhole-shaped.
export const NATIVE_WIDTH = numEnv('MARK_NATIVE_WIDTH', 512);
export const NATIVE_HEIGHT = numEnv('MARK_NATIVE_HEIGHT', 1024);

// How much of each canvas's height the glyph fills. The keyhole is tall, so its
// defaults leave generous padding; a squarer glyph usually wants a larger ratio
// (set these via MARK_COVERAGE / MARK_MASK_COVERAGE / MARK_OG_COVERAGE).
const COVERAGE = numEnv('MARK_COVERAGE', 0.58);
const MASK_COVERAGE = numEnv('MARK_MASK_COVERAGE', 0.7);
const OG_COVERAGE = numEnv('MARK_OG_COVERAGE', 0.78);

// Centers the native-size glyph inside a `size`x`size` canvas, scaled so it
// occupies ~`coverage` of the height, leaving even padding.
export function markTransform(size, coverage = COVERAGE) {
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
${svgAttribution}<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="App icon">
  <rect width="${size}" height="${size}" rx="${radius}" ry="${radius}" fill="${PRIMARY_COLOUR}"/>
  <path transform="${markTransform(size)}" fill="${BACKGROUND_COLOUR}" d="${KEYHOLE_PATH}"/>
</svg>
`;
}

// Monochrome mask for Safari pinned tabs: single black path on transparent.
// Safari recolors it via the `color` attribute on the <link rel="mask-icon">.
export function maskIconSvg(size = 512) {
  return `<?xml version="1.0" encoding="UTF-8"?>
${svgAttribution}<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="App icon (monochrome)">
  <path transform="${markTransform(size, MASK_COVERAGE)}" fill="#000000" d="${KEYHOLE_PATH}"/>
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
${svgAttribution}<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="Social preview">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${OG_GRADIENT_DARK}"/>
      <stop offset="1" stop-color="${PRIMARY_COLOUR}"/>
    </linearGradient>
  </defs>
  <rect width="${w}" height="${h}" fill="url(#bg)"/>
  <g transform="translate(${tx} ${ty})">
    <path transform="${markTransform(markSize, OG_COVERAGE)}" fill="${BACKGROUND_COLOUR}" d="${KEYHOLE_PATH}"/>
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
        name: PRODUCT_NAME,
        short_name: SHORT_NAME,
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
