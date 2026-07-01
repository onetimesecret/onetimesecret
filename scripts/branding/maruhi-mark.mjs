// scripts/branding/maruhi-mark.mjs
//
// Pure, dependency-free builders for the OTS-brand "maruhi" mark — the
// circled 秘 ("secret") glyph, colloquially "maruhi" (マル秘), styled to match
// the current Onetime Secret logo (src/shared/components/icons/OnetimeSecretIcon.vue,
// aka onetime-logo-v3): a solid #DC4A22 tile with a white mark centered on it.
//
// This is company branding, NOT the OSS-neutral default — see mark.mjs for
// that. Nothing here is imported by the neutral generator or its CI drift
// guard (check.mjs), and running generate-maruhi-favicons.mjs never touches
// public/web or src/assets/branding (#3048/#3049: the shipped default must
// stay brand-neutral). Deploy this pack the same way as any other custom
// pack — drop it in docker/public/ (build-time overlay) or point BRAND_*_URL
// at hosted copies. See docs/product/branding-favicon.md.
//
// ## Usage
//
//   pnpm run gen:favicons:maruhi   # from repo root; installs isolated deps,
//                                   # writes docker/public/ + a reviewable
//                                   # source copy in src/assets/branding/maruhi/
//
// Override the palette via env vars, same pattern as mark.mjs:
//
//   MARUHI_PRIMARY_COLOR='#DC4A22' MARUHI_BACKGROUND_COLOR='#FEFEFE' \
//     pnpm run gen:favicons:maruhi

// Maruhi (Japanese "secret" button) glyph. A single path whose fill-rule
// carves the 秘 characters as negative space out of a solid circle, so one
// fill colour renders the whole two-tone badge — same technique KEYHOLE_PATH
// uses in mark.mjs, just for a native 64x64 (square) canvas instead of a
// 512x1024 (tall) one. Matches
// src/shared/components/icons/MonotoneJapaneseSecretButtonIcon.vue.
//
// Emoji artwork provided by EmojiTwo, originally released as EmojiOne 2.2 by
// Ranks.com with contributions from the EmojiTwo community. Licensed under
// Creative Commons Attribution 4.0 International (CC-BY-4.0).
// Source: https://github.com/EmojiTwo/emojitwo
export const MARUHI_PATH =
  'M32 2C15.432 2 2 15.432 2 32s13.432 30 30 30s30-13.432 30-30S48.568 2 32 2m2.723 12c2.696 1.475 5.974 3.823 7.561 5.682l-3.172 3.495c-1.482-1.802-4.652-4.369-7.402-6.009zM24.467 50h-4.389V36.508c-1.162 3.004-2.483 5.68-3.963 7.592c-.371-1.42-1.375-3.551-2.115-4.861c1.956-2.35 3.858-6.336 5.128-10.106h-4.547v-4.589h5.497v-4.097a73 73 0 0 1-4.439.655c-.212-1.093-.793-2.732-1.375-3.823c4.071-.602 8.723-1.64 11.419-3.005l3.226 3.715c-1.323.601-2.854 1.092-4.441 1.529v5.025h3.699v4.589h-3.699v.327c.898.875 3.014 3.168 3.912 4.262c.422-2.021.688-4.262.845-6.337l3.543.874c-.317 4.426-.952 9.451-2.749 12.51l-3.383-1.803c.633-1.201 1.162-2.678 1.531-4.314l-2.324 2.895c-.318-.656-.794-1.639-1.375-2.623V50zm14.273-4.697h3.172c1.004 0 1.216-.766 1.375-5.682c.95.766 2.695 1.529 3.963 1.803c-.422 6.445-1.585 8.193-4.861 8.193h-4.283c-3.331 0-4.599-.928-4.916-3.934a47 47 0 0 1-4.123 3.225c-.688-.93-2.539-2.732-3.543-3.553c2.855-1.746 5.393-3.822 7.561-6.281v-16.77h4.439v10.599c2.802-4.809 4.76-10.49 6.081-16.937l4.651.874c-.847 3.771-1.851 7.267-3.066 10.489l1.639-.437c1.639 3.551 2.908 8.248 3.172 11.363l-4.388 1.311c-.105-2.404-.846-5.736-1.85-8.797c-1.745 3.881-3.807 7.322-6.239 10.326v2.459c-.001 1.53.159 1.749 1.216 1.749';

// OTS orange + white. Matches OnetimeSecretIcon.vue / onetime-logo-v3-xl.svg
// exactly (#DC4A22 tile, #FEFEFE mark) — "the new Onetime Secret logo".
export const PRIMARY_COLOUR = process.env.MARUHI_PRIMARY_COLOR || '#DC4A22';
export const BACKGROUND_COLOUR = process.env.MARUHI_BACKGROUND_COLOR || '#FEFEFE';
// A darker shade of PRIMARY_COLOUR for the OG-card gradient's top stop.
const OG_GRADIENT_DARK = process.env.MARUHI_OG_GRADIENT_DARK || '#7A2410';

const NATIVE_WIDTH = 64;
const NATIVE_HEIGHT = 64;

// Centers the native 64x64 maruhi glyph inside a `size`x`size` canvas, scaled
// so it occupies ~`coverage` of the height, leaving even padding.
function markTransform(size, coverage = 0.7) {
  const targetHeight = size * coverage;
  const scale = targetHeight / NATIVE_HEIGHT;
  const width = NATIVE_WIDTH * scale;
  const tx = (size - width) / 2;
  const ty = (size - targetHeight) / 2;
  return `translate(${tx.toFixed(2)} ${ty.toFixed(2)}) scale(${scale.toFixed(5)})`;
}

// Square app/favicon icon: rounded orange tile with the white maruhi mark —
// same construction as mark.mjs's squareIconSvg, mirroring how the "s" mark
// sits on onetime-logo-v3's tile.
export function squareIconSvg(size = 512) {
  const radius = Math.round(size * 0.1875); // ~iOS superellipse-ish corner, matches mark.mjs
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="Onetime Secret app icon">
  <rect width="${size}" height="${size}" rx="${radius}" ry="${radius}" fill="${PRIMARY_COLOUR}"/>
  <path transform="${markTransform(size)}" fill="${BACKGROUND_COLOUR}" d="${MARUHI_PATH}"/>
</svg>
`;
}

// Monochrome mask for Safari pinned tabs: single black path on transparent.
// Safari recolors it via the `color` attribute on the <link rel="mask-icon">.
export function maskIconSvg(size = 512) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" role="img" aria-label="Onetime Secret app icon (monochrome)">
  <path transform="${markTransform(size, 0.82)}" fill="#000000" d="${MARUHI_PATH}"/>
</svg>
`;
}

// Open Graph / Twitter social card (1200x630): deep-orange to brand-orange
// gradient with the white maruhi mark centered — same layout as mark.mjs's
// ogImageSvg, re-tinted.
export function ogImageSvg() {
  const w = 1200;
  const h = 630;
  const markSize = 320;
  const tx = (w - markSize) / 2;
  const ty = (h - markSize) / 2;
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="Onetime Secret social preview">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${OG_GRADIENT_DARK}"/>
      <stop offset="1" stop-color="${PRIMARY_COLOUR}"/>
    </linearGradient>
  </defs>
  <rect width="${w}" height="${h}" fill="url(#bg)"/>
  <g transform="translate(${tx} ${ty})">
    <path transform="${markTransform(markSize, 0.9)}" fill="${BACKGROUND_COLOUR}" d="${MARUHI_PATH}"/>
  </g>
</svg>
`;
}

// OTS-branded PWA manifest — unlike mark.mjs's neutral placeholder, this pack
// is only ever opted into deliberately, so it carries the real product name.
export function webmanifest() {
  return (
    JSON.stringify(
      {
        name: 'Onetime Secret',
        short_name: 'Onetime Secret',
        icons: [
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
        theme_color: PRIMARY_COLOUR,
        background_color: BACKGROUND_COLOUR,
        display: 'standalone',
        start_url: '/',
      },
      null,
      2
    ) + '\n'
  );
}
