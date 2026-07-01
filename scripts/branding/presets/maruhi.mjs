// scripts/branding/presets/maruhi.mjs
//
// Branding preset for the OTS "maruhi" mark — the circled 秘 ("secret") glyph,
// colloquially "maruhi" (マル秘), styled to match the current Onetime Secret logo
// (src/shared/components/icons/OnetimeSecretIcon.vue, aka onetime-logo-v3): a
// solid #DC4A22 tile with a white mark centered on it.
//
// This is a data-only bundle of MARK_* overrides for the shared generator — NOT
// a second implementation. Run it with:
//
//   pnpm run gen:favicons:maruhi          # = MARK_PRESET=maruhi ... generate-favicons.mjs
//
// It writes to docker/public/ (the gitignored build-time brand overlay) plus a
// reviewable source copy in src/assets/branding/maruhi/, so it never touches the
// neutral defaults in public/web (#3048/#3049). Override any value inline, e.g.
// MARK_PRIMARY_COLOR='#…' pnpm run gen:favicons:maruhi.
//
// The 秘 kanji's fine strokes stop being legible below ~24px, so a true 16px tab
// favicon renders as a soft white blob on orange; it reads clearly from the 32px
// .ico size up through the social card. Inherent to the glyph, not the generator.
//
// Emoji artwork provided by EmojiTwo, originally released as EmojiOne 2.2 by
// Ranks.com with contributions from the EmojiTwo community. Licensed under
// Creative Commons Attribution 4.0 International (CC-BY-4.0).
// Source: https://github.com/EmojiTwo/emojitwo
// A single path whose fill-rule carves the 秘 characters as negative space out
// of a solid circle, so one fill colour renders the whole two-tone badge on a
// native 64x64 canvas. Matches MonotoneJapaneseSecretButtonIcon.vue.
const MARUHI_PATH =
  'M32 2C15.432 2 2 15.432 2 32s13.432 30 30 30s30-13.432 30-30S48.568 2 32 2m2.723 12c2.696 1.475 5.974 3.823 7.561 5.682l-3.172 3.495c-1.482-1.802-4.652-4.369-7.402-6.009zM24.467 50h-4.389V36.508c-1.162 3.004-2.483 5.68-3.963 7.592c-.371-1.42-1.375-3.551-2.115-4.861c1.956-2.35 3.858-6.336 5.128-10.106h-4.547v-4.589h5.497v-4.097a73 73 0 0 1-4.439.655c-.212-1.093-.793-2.732-1.375-3.823c4.071-.602 8.723-1.64 11.419-3.005l3.226 3.715c-1.323.601-2.854 1.092-4.441 1.529v5.025h3.699v4.589h-3.699v.327c.898.875 3.014 3.168 3.912 4.262c.422-2.021.688-4.262.845-6.337l3.543.874c-.317 4.426-.952 9.451-2.749 12.51l-3.383-1.803c.633-1.201 1.162-2.678 1.531-4.314l-2.324 2.895c-.318-.656-.794-1.639-1.375-2.623V50zm14.273-4.697h3.172c1.004 0 1.216-.766 1.375-5.682c.95.766 2.695 1.529 3.963 1.803c-.422 6.445-1.585 8.193-4.861 8.193h-4.283c-3.331 0-4.599-.928-4.916-3.934a47 47 0 0 1-4.123 3.225c-.688-.93-2.539-2.732-3.543-3.553c2.855-1.746 5.393-3.822 7.561-6.281v-16.77h4.439v10.599c2.802-4.809 4.76-10.49 6.081-16.937l4.651.874c-.847 3.771-1.851 7.267-3.066 10.489l1.639-.437c1.639 3.551 2.908 8.248 3.172 11.363l-4.388 1.311c-.105-2.404-.846-5.736-1.85-8.797c-1.745 3.881-3.807 7.322-6.239 10.326v2.459c-.001 1.53.159 1.749 1.216 1.749';

export default {
  MARK_PATH: MARUHI_PATH,
  MARK_NATIVE_WIDTH: 64,
  MARK_NATIVE_HEIGHT: 64,
  // OTS orange + white — matches OnetimeSecretIcon.vue / onetime-logo-v3-xl.svg.
  MARK_PRIMARY_COLOR: '#DC4A22',
  MARK_BACKGROUND_COLOR: '#FEFEFE',
  MARK_OG_GRADIENT_DARK: '#7A2410', // a darker shade of the tile colour
  MARK_PRODUCT_NAME: 'Onetime Secret',
  // Travels into every generated SVG as a comment, so the committed sources
  // under src/assets/branding/maruhi/ carry their license with them.
  MARK_ATTRIBUTION:
    'Maruhi mark derived from EmojiTwo (EmojiOne 2.2), CC-BY-4.0 — https://github.com/EmojiTwo/emojitwo',
  // The square glyph fills more of the canvas than the tall keyhole's defaults.
  MARK_COVERAGE: 0.7,
  MARK_MASK_COVERAGE: 0.82,
  MARK_OG_COVERAGE: 0.9,
  // Company branding, so it never lands in the neutral default dirs.
  MARK_OUT_PUBLIC_DIR: 'docker/public',
  MARK_OUT_SRC_DIR: 'src/assets/branding/maruhi',
};
