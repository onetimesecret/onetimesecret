// scripts/branding/presets/linkdepot.mjs
//
// Branding preset for "LinkDepot" — a second sample general-purpose brand
// identity for the brand-pack system (alongside `vshare`), with a name/mark/
// palette unrelated to Onetime Secret's own identity (unlike `maruhi` /
// `onetimesecret`, which regenerate the company's historical marks).
//
// A chain-link mark on a teal tile — the link is the product's core object.
// Run it with:
//
//   pnpm run gen:favicons:linkdepot          # = --preset linkdepot
//
// Data-only bundle of MARK_* overrides for the shared generator — NOT a second
// implementation. Writes to public/branding/linkdepot/ (gitignored runtime
// pack) plus a reviewable source copy in src/assets/branding/linkdepot/, so it
// never touches the neutral defaults in public/web (#3048/#3049).
//
// MARK_PATH is the "link-solid" glyph from Heroicons (MIT), unmodified (native
// 24x24 viewBox).
// Source: https://heroicons.com (MIT License, Refactoring UI Inc.)
const LINK_PATH =
  'M19.902 4.098a3.75 3.75 0 0 0-5.304 0l-4.5 4.5a3.75 3.75 0 0 0 1.035 6.037a.75.75 0 0 1-.646 1.353a5.25 5.25 0 0 1-1.449-8.45l4.5-4.5a5.25 5.25 0 1 1 7.424 7.424l-1.757 1.757a.75.75 0 1 1-1.06-1.06l1.757-1.757a3.75 3.75 0 0 0 0-5.304m-7.389 4.267a.75.75 0 0 1 1-.353a5.25 5.25 0 0 1 1.449 8.45l-4.5 4.5a5.25 5.25 0 1 1-7.424-7.424l1.757-1.757a.75.75 0 1 1 1.06 1.06l-1.757 1.757a3.75 3.75 0 1 0 5.304 5.304l4.5-4.5a3.75 3.75 0 0 0-1.035-6.037a.75.75 0 0 1-.354-1';

export default {
  MARK_PATH: LINK_PATH,
  MARK_NATIVE_WIDTH: 24,
  MARK_NATIVE_HEIGHT: 24,
  MARK_PRIMARY_COLOR: '#0D9488', // teal — distinct from vshare's indigo and OTS orange
  MARK_BACKGROUND_COLOR: '#FEFEFE',
  MARK_OG_GRADIENT_DARK: '#134E4A', // a darker shade of the tile colour
  MARK_PRODUCT_NAME: 'LinkDepot',
  MARK_ATTRIBUTION: 'Link mark from Heroicons, MIT License — https://heroicons.com',
  MARK_COVERAGE: 0.62,
  MARK_MASK_COVERAGE: 0.74,
  MARK_OG_COVERAGE: 0.82,
  // Sample brand, so it never lands in the neutral default dirs.
  // Runtime brand pack (#3739): resolved against REPO_ROOT by the generator.
  MARK_OUT_PUBLIC_DIR: 'public/branding/linkdepot',
  MARK_OUT_SRC_DIR: 'src/assets/branding/linkdepot',
};
