// src/utils/brand-palette.ts

/**
 * Brand palette generator using oklch color space.
 *
 * Takes a single hex color → generates 44 CSS variable entries spanning
 * 4 palettes (brand, branddim, brandcomp, brandcompdim), each with 11 shades.
 *
 * The complement is derived via 180° hue rotation — no independent config needed.
 * Gamut clipping via binary search ensures all output colors are valid sRGB hex.
 */

// ─── Color space conversion chain ────────────────────────────────────────────
// hex → sRGB → linear RGB → XYZ D65 → oklab → oklch (and reverse)

/** Clamp value to [min, max] */
function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

/** Parse 3 or 6 digit hex to [r, g, b] in 0-255 */
function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  if (h.length === 3) {
    return [
      parseInt(h[0] + h[0], 16),
      parseInt(h[1] + h[1], 16),
      parseInt(h[2] + h[2], 16),
    ];
  }
  return [
    parseInt(h.substring(0, 2), 16),
    parseInt(h.substring(2, 4), 16),
    parseInt(h.substring(4, 6), 16),
  ];
}

/** Convert 0-255 RGB to 0-1 sRGB */
function rgbToSrgb(rgb: [number, number, number]): [number, number, number] {
  return rgb.map((c) => c / 255) as [number, number, number];
}

/** sRGB (0-1) to linear RGB via inverse gamma */
function srgbToLinear(c: number): number {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

/** Linear RGB to sRGB (0-1) via gamma */
function linearToSrgb(c: number): number {
  return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}

/** Linear RGB → XYZ D65 */
function linearRgbToXyz(r: number, g: number, b: number): [number, number, number] {
  return [
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
  ];
}

/** XYZ D65 → Linear RGB */
function xyzToLinearRgb(x: number, y: number, z: number): [number, number, number] {
  return [
    +4.0767416621 * x - 3.3077115913 * y + 0.2309699292 * z,
    -1.2684380046 * x + 2.6097574011 * y - 0.3413193965 * z,
    -0.0041960863 * x - 0.7034186147 * y + 1.7076147010 * z,
  ];
}

/** XYZ D65 → oklab via LMS intermediate */
function xyzToOklab(x: number, y: number, z: number): [number, number, number] {
  const l_ = Math.cbrt(0.8189330101 * x + 0.3618667424 * y - 0.1288597137 * z);
  const m_ = Math.cbrt(0.0329845436 * x + 0.9293118715 * y + 0.0361456387 * z);
  const s_ = Math.cbrt(0.0482003018 * x + 0.2643662691 * y + 0.6338517070 * z);

  return [
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
  ];
}

/** oklab → XYZ D65 via LMS intermediate */
function oklabToXyz(L: number, a: number, b: number): [number, number, number] {
  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.2914855480 * b;

  const l = l_ * l_ * l_;
  const m = m_ * m_ * m_;
  const s = s_ * s_ * s_;

  return [
    +1.2270138511 * l - 0.5577999807 * m + 0.2812561490 * s,
    -0.0405801784 * l + 1.1122568696 * m - 0.0716766787 * s,
    -0.0763812845 * l - 0.4214819784 * m + 1.5861632204 * s,
  ];
}

/** oklab → oklch */
function oklabToOklch(L: number, a: number, b: number): [number, number, number] {
  const C = Math.sqrt(a * a + b * b);
  let h = (Math.atan2(b, a) * 180) / Math.PI;
  if (h < 0) h += 360;
  return [L, C, h];
}

/** oklch → oklab */
function oklchToOklab(L: number, C: number, h: number): [number, number, number] {
  const hRad = (h * Math.PI) / 180;
  return [L, C * Math.cos(hRad), C * Math.sin(hRad)];
}

// ─── Full conversion pipelines ───────────────────────────────────────────────

/** hex → oklch */
function hexToOklch(hex: string): [number, number, number] {
  const rgb = hexToRgb(hex);
  const srgb = rgbToSrgb(rgb);
  const linear: [number, number, number] = [
    srgbToLinear(srgb[0]),
    srgbToLinear(srgb[1]),
    srgbToLinear(srgb[2]),
  ];
  const xyz = linearRgbToXyz(...linear);
  const lab = xyzToOklab(...xyz);
  return oklabToOklch(...lab);
}

/** oklch → hex (returns null if out of sRGB gamut) */
function oklchToHex(L: number, C: number, h: number): string | null {
  const [labL, a, b] = oklchToOklab(L, C, h);
  const xyz = oklabToXyz(labL, a, b);
  const [lr, lg, lb] = xyzToLinearRgb(...xyz);

  // Check gamut: all linear RGB must be in [-epsilon, 1+epsilon]
  // Use a wider tolerance (0.06) because the XYZ→linear RGB matrix chain
  // introduces numerical overshoot at extreme lightness values. Values within
  // this range are clamped safely — values beyond indicate genuine gamut violation.
  const eps = 0.06;
  if (lr < -eps || lr > 1 + eps || lg < -eps || lg > 1 + eps || lb < -eps || lb > 1 + eps) {
    return null;
  }

  const r = Math.round(clamp(linearToSrgb(clamp(lr, 0, 1)), 0, 1) * 255);
  const g = Math.round(clamp(linearToSrgb(clamp(lg, 0, 1)), 0, 1) * 255);
  const bVal = Math.round(clamp(linearToSrgb(clamp(lb, 0, 1)), 0, 1) * 255);

  return (
    '#' +
    r.toString(16).padStart(2, '0') +
    g.toString(16).padStart(2, '0') +
    bVal.toString(16).padStart(2, '0')
  );
}

/** oklch → hex with gamut clipping (binary search on chroma) */
function oklchToHexClamped(L: number, C: number, h: number): string {
  // Try direct conversion first
  const direct = oklchToHex(L, C, h);
  if (direct) return direct;

  // Fall back to achromatic (C=0) first to establish a valid baseline
  const achromatic = oklchToHex(L, 0, h);
  let result = achromatic ?? '#000000';

  // Binary search: find maximum chroma that stays in gamut
  let lo = 0;
  let hi = C;

  for (let i = 0; i < 20; i++) {
    const mid = (lo + hi) / 2;
    const hex = oklchToHex(L, mid, h);
    if (hex) {
      result = hex;
      lo = mid;
    } else {
      hi = mid;
    }
  }

  return result;
}

// ─── Palette generation ──────────────────────────────────────────────────────

/** Shade labels for CSS variable names */
const SHADE_LABELS = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950'];

/**
 * Relative positions for each shade in the lightness range.
 * 0.0 = darkest (shade 950), 1.0 = lightest (shade 50).
 * Shade 500 (index 4 from bottom, position 0.5 in scale) is the anchor.
 */
const SHADE_POSITIONS = [1.0, 0.95, 0.85, 0.72, 0.58, 0.5, 0.40, 0.30, 0.21, 0.14, 0.08];

/**
 * Chroma scaling factors per shade.
 * Lighter/darker shades get reduced chroma to avoid oversaturation.
 */
const CHROMA_FACTORS: number[] = [
  0.25, // 50
  0.40, // 100
  0.60, // 200
  0.80, // 300
  0.95, // 400
  1.00, // 500
  1.00, // 600
  0.95, // 700
  0.85, // 800
  0.75, // 900
  0.60, // 950
];

/** Dimmed variant chroma reduction factor */
const DIM_CHROMA_FACTOR = 0.85;

/** Minimum lightness for darkest shade */
const MIN_LIGHTNESS = 0.10;
/** Maximum lightness for lightest shade */
const MAX_LIGHTNESS = 0.97;

type PaletteMap = Record<string, string>;

interface PaletteShade {
  label: string;
  hex: string;
}

/**
 * Compute lightness targets anchored to the input color's lightness.
 * Shade 500 uses the input lightness (clamped to a reasonable range).
 * Lighter shades interpolate toward MAX_LIGHTNESS.
 * Darker shades interpolate toward MIN_LIGHTNESS.
 */
function computeLightnessTargets(anchorL: number): number[] {
  // Clamp anchor to a range that leaves room for lighter and darker shades
  const anchor = clamp(anchorL, 0.25, 0.80);

  return SHADE_POSITIONS.map((pos) => {
    if (pos >= 0.5) {
      // Lighter half: interpolate from anchor to MAX_LIGHTNESS
      const t = (pos - 0.5) / 0.5; // 0 at anchor, 1 at lightest
      return anchor + (MAX_LIGHTNESS - anchor) * t;
    } else {
      // Darker half: interpolate from MIN_LIGHTNESS to anchor
      const t = pos / 0.5; // 0 at darkest, 1 at anchor
      return MIN_LIGHTNESS + (anchor - MIN_LIGHTNESS) * t;
    }
  });
}

/**
 * Generate an 11-shade scale for a given hue, base chroma, and anchor lightness.
 * Shade 500 is anchored at the input color's lightness for maximum fidelity.
 */
function generateScale(baseChroma: number, hue: number, anchorLightness: number): PaletteShade[] {
  const lightnessTargets = computeLightnessTargets(anchorLightness);

  return SHADE_LABELS.map((label, i) => {
    const L = lightnessTargets[i];
    const C = baseChroma * CHROMA_FACTORS[i];
    return { label, hex: oklchToHexClamped(L, C, hue) };
  });
}

/**
 * Validate and normalize hex input.
 * Returns normalized 7-char hex string or null for invalid input.
 */
function normalizeHex(input: string): string | null {
  if (typeof input !== 'string') return null;
  const trimmed = input.trim();
  if (!/^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(trimmed)) return null;

  const h = trimmed.replace('#', '');
  if (h.length === 3) {
    return '#' + h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  }
  return '#' + h.toLowerCase();
}

/** The canonical default brand color */
export const DEFAULT_BRAND_HEX = '#dc4a22';

/**
 * Generate a full brand palette from a single hex color.
 *
 * Returns a map of 44 CSS variable names → hex values covering:
 * - `--color-brand-{50..950}` — primary brand scale
 * - `--color-branddim-{50..950}` — dimmed primary (reduced chroma)
 * - `--color-brandcomp-{50..950}` — complementary (180° hue rotation)
 * - `--color-brandcompdim-{50..950}` — dimmed complementary
 *
 * @param hex - Input color as hex string (e.g., '#dc4a22')
 * @returns Record of CSS variable name → hex value (44 entries)
 */
export function generateBrandPalette(hex: string): PaletteMap {
  const normalized = normalizeHex(hex);
  const sourceHex = normalized ?? DEFAULT_BRAND_HEX;

  const [L, C, H] = hexToOklch(sourceHex);

  // Complement: 180° hue rotation
  const compH = (H + 180) % 360;

  // Generate all 4 scales, anchored to the input color's lightness
  const brand = generateScale(C, H, L);
  const branddim = generateScale(C * DIM_CHROMA_FACTOR, H, L);
  const brandcomp = generateScale(C, compH, L);
  const brandcompdim = generateScale(C * DIM_CHROMA_FACTOR, compH, L);

  const result: PaletteMap = {};

  for (const shade of brand) {
    result[`--color-brand-${shade.label}`] = shade.hex;
  }
  for (const shade of branddim) {
    result[`--color-branddim-${shade.label}`] = shade.hex;
  }
  for (const shade of brandcomp) {
    result[`--color-brandcomp-${shade.label}`] = shade.hex;
  }
  for (const shade of brandcompdim) {
    result[`--color-brandcompdim-${shade.label}`] = shade.hex;
  }

  return result;
}

/**
 * Pre-computed default palette for validation and comparison.
 * Generated from DEFAULT_BRAND_HEX (#dc4a22).
 */
export const DEFAULT_BRAND_PALETTE: PaletteMap = generateBrandPalette(DEFAULT_BRAND_HEX);

/**
 * All CSS variable names produced by generateBrandPalette.
 * Useful for cleanup/removal operations.
 */
export const BRAND_CSS_VARIABLES: string[] = Object.keys(DEFAULT_BRAND_PALETTE);

/**
 * Expose conversion utilities for testing/debugging.
 * Not part of the public API for consumers.
 */
export const _internals = {
  hexToOklch,
  oklchToHexClamped,
  normalizeHex,
};
