// scripts/branding/presets/vshare.mjs
//
// Branding preset for "VaultShare" — a sample general-purpose brand identity
// demonstrating the brand-pack system with a name/mark/palette that has no
// connection to Onetime Secret's own identity (unlike `maruhi` / `onetimesecret`,
// which regenerate the company's historical marks).
//
// A closed-padlock mark on a deep indigo tile — "vault" as the product metaphor
// for held secrets. Run it with:
//
//   pnpm run gen:favicons:vshare          # = --preset vshare
//
// Data-only bundle of MARK_* overrides for the shared generator — NOT a second
// implementation. Writes to public/branding/vshare/ (gitignored runtime pack)
// plus a reviewable source copy in src/assets/branding/vshare/, so it never
// touches the neutral defaults in public/web (#3048/#3049).
//
// MARK_PATH is the "lock-closed-solid" glyph from Heroicons (MIT), unmodified
// (native 24x24 viewBox — no MARK_NATIVE_WIDTH/HEIGHT override needed since
// mark.mjs's neutral default already assumes a square-ish path unless told
// otherwise; set explicitly below for clarity).
// Source: https://heroicons.com (MIT License, Refactoring UI Inc.)
const LOCK_PATH =
  'M12 1.5a5.25 5.25 0 0 0-5.25 5.25v3a3 3 0 0 0-3 3v6.75a3 3 0 0 0 3 3h10.5a3 3 0 0 0 3-3v-6.75a3 3 0 0 0-3-3v-3c0-2.9-2.35-5.25-5.25-5.25m3.75 8.25v-3a3.75 3.75 0 1 0-7.5 0v3z';

export default {
  MARK_PATH: LOCK_PATH,
  MARK_NATIVE_WIDTH: 24,
  MARK_NATIVE_HEIGHT: 24,
  MARK_PRIMARY_COLOR: '#4F46E5', // deep indigo — "vault" trust/security tone
  MARK_BACKGROUND_COLOR: '#FEFEFE',
  MARK_OG_GRADIENT_DARK: '#312E81', // a darker shade of the tile colour
  MARK_PRODUCT_NAME: 'VaultShare',
  MARK_ATTRIBUTION: 'Lock mark from Heroicons, MIT License — https://heroicons.com',
  MARK_COVERAGE: 0.62,
  MARK_MASK_COVERAGE: 0.74,
  MARK_OG_COVERAGE: 0.82,
  // Sample brand, so it never lands in the neutral default dirs.
  // Runtime brand pack (#3739): resolved against REPO_ROOT by the generator.
  MARK_OUT_PUBLIC_DIR: 'public/branding/vshare',
  MARK_OUT_SRC_DIR: 'src/assets/branding/vshare',
};
