// src/utils/brand-palette.ts
//
// Pure function: generateBrandPalette(hex) → 44 CSS variable entries
// Uses oklch color space for perceptual uniformity.
// Complement derived via 180° hue rotation.

// ─── Types ───────────────────────────────────────────

/** CSS variable name → hex color value */
export type BrandPalette = Record<string, string>;

// ─── Constants ───────────────────────────────────────

const SHADE_STEPS = [
  '50', '100', '200', '300', '400', '500',
  '600', '700', '800', '900', '950',
] as const;

const PALETTE_PREFIXES = [
  'brand', 'branddim', 'brandcomp', 'brandcompdim',
] as const;

/** Lightness ceiling for shade 50 */
const L_MAX = 0.98;
/** Lightness floor for shade 950 */
const L_MIN = 0.25;
/** Lightness multiplier for dim palette base */
const DIM_L_FACTOR = 0.84;
/** Chroma multiplier for dim palette base */
const DIM_C_FACTOR = 0.90;

export const DEFAULT_BRAND_HEX = '#dc4a22';

// ─── Color Space Conversions ─────────────────────────
// Chain: hex → sRGB → linear RGB → LMS → oklab → oklch

/** Parse hex string to sRGB [0-1] triplet */
function hexToSrgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  return [
    parseInt(h.slice(0, 2), 16) / 255,
    parseInt(h.slice(2, 4), 16) / 255,
    parseInt(h.slice(4, 6), 16) / 255,
  ];
}

/** sRGB component → linear (inverse gamma / degamma) */
function srgbToLinear(c: number): number {
  return c <= 0.04045
    ? c / 12.92
    : Math.pow((c + 0.055) / 1.055, 2.4);
}

/** Linear component → sRGB (gamma / compand) */
function linearToSrgb(c: number): number {
  return c <= 0.0031308
    ? c * 12.92
    : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}

/** Linear sRGB → LMS cone responses (Ottosson's M1 matrix) */
function linearRgbToLms(
  r: number, g: number, b: number
): [number, number, number] {
  return [
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
  ];
}

/** LMS → oklab (Ottosson's M2 matrix, with cube root) */
function lmsToOklab(
  l: number, m: number, s: number
): [number, number, number] {
  const lp = Math.cbrt(l);
  const mp = Math.cbrt(m);
  const sp = Math.cbrt(s);
  return [
    0.2104542553 * lp + 0.7936177850 * mp - 0.0040720468 * sp,
    1.9779984951 * lp - 2.4285922050 * mp + 0.4505937099 * sp,
    0.0259040371 * lp + 0.7827717662 * mp - 0.8086757660 * sp,
  ];
}

/** oklab → LMS (inverse M2, then cube) */
function oklabToLms(
  L: number, a: number, b: number
): [number, number, number] {
  const lp = L + 0.3963377774 * a + 0.2158037573 * b;
  const mp = L - 0.1055613458 * a - 0.0638541728 * b;
  const sp = L - 0.0894841775 * a - 1.2914855480 * b;
  return [lp * lp * lp, mp * mp * mp, sp * sp * sp];
}

/** LMS → linear sRGB (inverse M1 matrix) */
function lmsToLinearRgb(
  l: number, m: number, s: number
): [number, number, number] {
  return [
    +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  ];
}

/** oklab → oklch (polar form) */
function oklabToOklch(
  L: number, a: number, b: number
): [number, number, number] {
  const C = Math.sqrt(a * a + b * b);
  let H = Math.atan2(b, a) * (180 / Math.PI);
  if (H < 0) H += 360;
  return [L, C, H];
}

/** oklch → oklab (from polar) */
function oklchToOklab(
  L: number, C: number, H: number
): [number, number, number] {
  const hRad = H * (Math.PI / 180);
  return [L, C * Math.cos(hRad), C * Math.sin(hRad)];
}

// ─── Full Conversion Chains ──────────────────────────

/** hex → oklch */
function hexToOklch(hex: string): [number, number, number] {
  const [r, g, b] = hexToSrgb(hex);
  const [rl, gl, bl] = [srgbToLinear(r), srgbToLinear(g), srgbToLinear(b)];
  const [l, m, s] = linearRgbToLms(rl, gl, bl);
  const [L, a, ob] = lmsToOklab(l, m, s);
  return oklabToOklch(L, a, ob);
}

/** oklch → hex (with clamping to sRGB) */
function oklchToHex(L: number, C: number, H: number): string {
  const [oL, oa, ob] = oklchToOklab(L, C, H);
  const [l, m, s] = oklabToLms(oL, oa, ob);
  const [rl, gl, bl] = lmsToLinearRgb(l, m, s);
  // Clamp to [0, 1] after gamut mapping (should be in gamut already)
  const r = Math.round(Math.min(1, Math.max(0, linearToSrgb(rl))) * 255);
  const g = Math.round(Math.min(1, Math.max(0, linearToSrgb(gl))) * 255);
  const b = Math.round(Math.min(1, Math.max(0, linearToSrgb(bl))) * 255);
  return (
    '#' +
    r.toString(16).padStart(2, '0') +
    g.toString(16).padStart(2, '0') +
    b.toString(16).padStart(2, '0')
  );
}

// ─── Gamut Clipping ──────────────────────────────────

/** Check if linear RGB values are within sRGB gamut */
function isInSrgbGamut(r: number, g: number, b: number): boolean {
  const eps = -0.001; // Small tolerance for floating point
  return r >= eps && r <= 1.001
    && g >= eps && g <= 1.001
    && b >= eps && b <= 1.001;
}

/**
 * Binary search for maximum chroma at given L and H
 * that produces in-gamut sRGB. Returns clipped oklch.
 */
function gamutClip(
  L: number, C: number, H: number
): [number, number, number] {
  // Check if already in gamut
  const [oa, ob, oc] = oklchToOklab(L, C, H);
  const [l, m, s] = oklabToLms(oa, ob, oc);
  const [r, g, b] = lmsToLinearRgb(l, m, s);
  if (isInSrgbGamut(r, g, b)) return [L, C, H];

  // Binary search: find max chroma that's in gamut
  let lo = 0;
  let hi = C;
  for (let i = 0; i < 32; i++) {
    const mid = (lo + hi) / 2;
    const [a2, b2, c2] = oklchToOklab(L, mid, H);
    const [l2, m2, s2] = oklabToLms(a2, b2, c2);
    const [r2, g2, b2r] = lmsToLinearRgb(l2, m2, s2);
    if (isInSrgbGamut(r2, g2, b2r)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return [L, lo, H];
}

// ─── Shade Generation ────────────────────────────────

/**
 * Compute lightness values for each shade step.
 *
 * Lighter shades use a sqrt curve to stay lighter longer
 * (Tailwind-style compressed light end). Darker shades
 * use linear interpolation toward L_MIN.
 */
function lightnessForShade(shade: number, baseL: number): number {
  if (shade === 500) return baseL;
  if (shade < 500) {
    // sqrt curve keeps shades 50-200 in a narrow light range
    const t = (500 - shade) / (500 - 50);
    return baseL + (L_MAX - baseL) * Math.pow(t, 0.5);
  }
  // shade > 500: linear toward dark
  const t = (shade - 500) / (950 - 500);
  return baseL - (baseL - L_MIN) * t;
}

/**
 * Scale chroma for a given shade.
 *
 * Lighter shades (50-400) get progressive chroma reduction
 * because near-white colors look better with subtle tints.
 * Darker shades (600-950) maintain full chroma — the gamut
 * clipper will constrain if needed. Dark warm/cool colors in
 * sRGB naturally support high chroma.
 */
function chromaForShade(
  shade: number, baseC: number
): number {
  if (shade >= 500) {
    // Darker shades: full chroma, let gamut clipping handle
    return baseC;
  }
  // Lighter shades: power 1.5 falloff for warm tints
  const distance = (500 - shade) / 450;
  const factor = Math.pow(1 - distance, 1.5);
  return baseC * Math.max(factor, 0.025);
}

/**
 * Generate an 11-shade scale from a base oklch color.
 * Returns shade step → hex string.
 */
function generateScale(
  baseL: number, baseC: number, baseH: number
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const step of SHADE_STEPS) {
    const shade = parseInt(step, 10);
    const L = lightnessForShade(shade, baseL);
    const C = chromaForShade(shade, baseC);
    const [cL, cC, cH] = gamutClip(L, C, baseH);
    result[step] = oklchToHex(cL, cC, cH);
  }
  return result;
}

// ─── Validation ──────────────────────────────────────

const HEX_REGEX = /^#?[0-9a-fA-F]{6}$/;

function isValidHex(hex: string): boolean {
  return HEX_REGEX.test(hex);
}

function normalizeHex(hex: string): string {
  const clean = hex.replace('#', '').toLowerCase();
  return `#${clean}`;
}

// ─── Main API ────────────────────────────────────────

/**
 * Generate a complete brand palette from a single hex color.
 *
 * Produces 44 CSS variable entries covering 4 palette groups
 * (brand, branddim, brandcomp, brandcompdim), each with 11
 * shades (50–950).
 *
 * Keys are CSS variable names: `--color-brand-500`, etc.
 * Values are hex color strings: `#dc4a22`, etc.
 *
 * Invalid input falls back to the default brand color.
 */
export function generateBrandPalette(
  hex: string | null
): BrandPalette {
  const safeHex = (hex && isValidHex(hex))
    ? normalizeHex(hex)
    : DEFAULT_BRAND_HEX;

  const [baseL, baseC, baseH] = hexToOklch(safeHex);

  // Complement: 180° hue rotation
  const compH = (baseH + 180) % 360;

  // Dim variants: darker and slightly desaturated base
  const dimL = baseL * DIM_L_FACTOR;
  const dimC = baseC * DIM_C_FACTOR;

  // Generate all four scale groups
  const scales: Record<string, Record<string, string>> = {
    brand: generateScale(baseL, baseC, baseH),
    branddim: generateScale(dimL, dimC, baseH),
    brandcomp: generateScale(baseL, baseC, compH),
    brandcompdim: generateScale(dimL, dimC, compH),
  };

  // Flatten to CSS variable map
  const palette: BrandPalette = {};
  for (const prefix of PALETTE_PREFIXES) {
    const scale = scales[prefix];
    for (const step of SHADE_STEPS) {
      palette[`--color-${prefix}-${step}`] = scale[step];
    }
  }

  return palette;
}

/**
 * Pre-computed default palette for validation and fallback.
 * Generated from the canonical OTS brand color #dc4a22.
 */
export const DEFAULT_BRAND_PALETTE: BrandPalette =
  generateBrandPalette(DEFAULT_BRAND_HEX);

// Re-export for use in tests and composables
export { isValidHex, hexToOklch, oklchToHex };
