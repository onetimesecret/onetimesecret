// src/tests/utils/brand-palette.spec.ts
//
// Spec for the pure oklch-based brand palette generator.
// Adapted from develop's reference for the NEUTRAL defaults strategy
// (issue #3048, #3049): the canonical default is NEUTRAL_BRAND_DEFAULTS,
// not the legacy OTS orange. The OTS orange (#dc4a22) appears here only
// as a non-default custom-color input to exercise palette behavior.

import { describe, expect, it } from 'vitest';
import {
  DEFAULT_BRAND_PALETTE,
  generateBrandPalette,
  hexToOklch,
  oklchToHex,
  isValidHex,
  contrastRatio,
  checkBrandContrast,
} from '@/utils/brand-palette';
import type { ContrastCheck } from '@/utils/brand-palette';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';

const NEUTRAL_HEX = NEUTRAL_BRAND_DEFAULTS.primary_color; // '#3B82F6'
const OTS_ORANGE = '#dc4a22'; // Legacy OTS color, used as a custom input only

const SHADE_STEPS = [
  '50', '100', '200', '300', '400', '500',
  '600', '700', '800', '900', '950',
];

const PALETTE_PREFIXES = ['brand', 'branddim', 'brandcomp', 'brandcompdim'];

const TOTAL_KEYS = SHADE_STEPS.length * PALETTE_PREFIXES.length; // 44

/** Helper for roundtrip tests */
function hexToSrgbValues(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
  ];
}

describe('brand-palette', () => {
  describe('generateBrandPalette', () => {
    it('emits exactly 44 CSS variable entries', () => {
      const palette = generateBrandPalette(NEUTRAL_HEX);
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
      expect(TOTAL_KEYS).toBe(44);
    });

    it('uses --color-{prefix}-{shade} naming for every entry', () => {
      const palette = generateBrandPalette(NEUTRAL_HEX);
      for (const prefix of PALETTE_PREFIXES) {
        for (const step of SHADE_STEPS) {
          const key = `--color-${prefix}-${step}`;
          expect(palette).toHaveProperty(key);
        }
      }
    });

    it('produces 6-digit hex string values for every entry', () => {
      const palette = generateBrandPalette(NEUTRAL_HEX);
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('brand-500 is perceptually close to the input color (oklch roundtrip)', () => {
      const palette = generateBrandPalette(NEUTRAL_HEX);
      const [L1, C1, H1] = hexToOklch(NEUTRAL_HEX);
      const [L2, C2, H2] = hexToOklch(palette['--color-brand-500']);
      expect(Math.abs(L1 - L2)).toBeLessThan(0.02);
      expect(Math.abs(C1 - C2)).toBeLessThan(0.02);
      expect(Math.abs(H1 - H2)).toBeLessThan(2);
    });

    it('brandcomp hue is approximately 180 degrees from brand hue', () => {
      const palette = generateBrandPalette(NEUTRAL_HEX);
      const [, , brandH] = hexToOklch(palette['--color-brand-500']);
      const [, , compH] = hexToOklch(palette['--color-brandcomp-500']);
      const hueDiff = ((compH - brandH) % 360 + 360) % 360;
      expect(Math.abs(hueDiff - 180)).toBeLessThan(5);
    });

    it('lighter shades have higher lightness (monotonic per prefix)', () => {
      const palette = generateBrandPalette(NEUTRAL_HEX);
      for (const prefix of PALETTE_PREFIXES) {
        const lightness = SHADE_STEPS.map((step) => {
          const hex = palette[`--color-${prefix}-${step}`];
          const [L] = hexToOklch(hex);
          return L;
        });
        for (let i = 0; i < lightness.length - 1; i++) {
          expect(lightness[i]).toBeGreaterThan(lightness[i + 1]);
        }
      }
    });

    it('dim variants are darker than main variants at shade 500', () => {
      const palette = generateBrandPalette(NEUTRAL_HEX);
      const [mainL] = hexToOklch(palette['--color-brand-500']);
      const [dimL] = hexToOklch(palette['--color-branddim-500']);
      expect(dimL).toBeLessThan(mainL);
    });

    it('is deterministic — same input yields the same output', () => {
      const a = generateBrandPalette(NEUTRAL_HEX);
      const b = generateBrandPalette(NEUTRAL_HEX);
      expect(a).toEqual(b);
    });

    it('produces different palettes for different inputs', () => {
      const blue = generateBrandPalette(NEUTRAL_HEX);
      const orange = generateBrandPalette(OTS_ORANGE);
      expect(blue['--color-brand-500']).not.toEqual(orange['--color-brand-500']);
    });

    it('handles 6-digit hex with # prefix', () => {
      const palette = generateBrandPalette('#22c55e');
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
    });

    it('handles 6-digit hex without # prefix (normalized)', () => {
      const withHash = generateBrandPalette(NEUTRAL_HEX);
      const withoutHash = generateBrandPalette(NEUTRAL_HEX.replace('#', ''));
      expect(withoutHash).toEqual(withHash);
    });

    it('treats uppercase and lowercase hex as equivalent', () => {
      const lower = generateBrandPalette('#3b82f6');
      const upper = generateBrandPalette('#3B82F6');
      expect(lower).toEqual(upper);
    });

    it('handles pure black input without crashing', () => {
      const palette = generateBrandPalette('#000000');
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('handles pure white input without crashing', () => {
      const palette = generateBrandPalette('#ffffff');
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('falls back to default palette for invalid hex input', () => {
      const invalid = generateBrandPalette('not-a-color');
      const fallback = generateBrandPalette(null);
      // Both invalid and null route to the same internal default.
      // We don't assert which color that is — only that the function
      // returns a complete 44-key palette without throwing.
      expect(Object.keys(invalid)).toHaveLength(TOTAL_KEYS);
      expect(invalid).toEqual(fallback);
    });

    it('falls back to default palette for null input', () => {
      const palette = generateBrandPalette(null);
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
    });

    it('does not throw on 3-digit shorthand hex (falls back gracefully)', () => {
      // Shorthand hex (#fff) is not in the spec; the implementation falls
      // back to the default palette rather than expanding the shorthand.
      const palette = generateBrandPalette('#fff');
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
    });

    it('falls back when given 8-digit hex (alpha channel)', () => {
      // isValidHex regex is /^#?[0-9a-fA-F]{6}$/ — 8-digit input fails
      // validation and routes through the default fallback.
      const palette = generateBrandPalette('#aabbccff');
      const fallback = generateBrandPalette(null);
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
      expect(palette).toEqual(fallback);
    });

    it('falls back when input has leading whitespace', () => {
      // The implementation does not trim — ' #abc' fails validation.
      const palette = generateBrandPalette(' #3B82F6');
      const fallback = generateBrandPalette(null);
      expect(Object.keys(palette)).toHaveLength(TOTAL_KEYS);
      expect(palette).toEqual(fallback);
    });

    it('produces byte-identical output for the same input on repeated calls', () => {
      const a = generateBrandPalette('#3B82F6');
      const b = generateBrandPalette('#3B82F6');
      // Stricter than `.toEqual()` — JSON-stringification compares the
      // serialized form, catching key-order or value-format drift.
      expect(JSON.stringify(a)).toBe(JSON.stringify(b));
    });

    it('adjacent hex inputs (#3B82F6 vs #3B82F7) yield distinguishable palettes', () => {
      // Guards against false collapse from over-aggressive rounding/quantization.
      const a = generateBrandPalette('#3B82F6');
      const b = generateBrandPalette('#3B82F7');
      // The palettes overall must not collide. (Individual shades may
      // happen to round to the same hex due to gamut clipping; what we
      // care about is no full-palette collapse.)
      expect(JSON.stringify(a)).not.toBe(JSON.stringify(b));
    });
  });

  describe('DEFAULT_BRAND_PALETTE', () => {
    it('is pre-computed with 44 entries', () => {
      expect(Object.keys(DEFAULT_BRAND_PALETTE)).toHaveLength(TOTAL_KEYS);
    });
  });

  describe('isValidHex', () => {
    it('accepts 6-digit hex with #', () => {
      expect(isValidHex('#3b82f6')).toBe(true);
    });

    it('accepts 6-digit hex without #', () => {
      expect(isValidHex('3b82f6')).toBe(true);
    });

    it('accepts uppercase hex', () => {
      expect(isValidHex('#3B82F6')).toBe(true);
    });

    it('rejects 3-digit shorthand hex', () => {
      expect(isValidHex('#fff')).toBe(false);
    });

    it('rejects strings with non-hex characters', () => {
      expect(isValidHex('#gggggg')).toBe(false);
    });

    it('rejects empty string', () => {
      expect(isValidHex('')).toBe(false);
    });
  });

  describe('color conversion roundtrip', () => {
    it('hex → oklch → hex roundtrips within ±1/255 per channel', () => {
      const colors = [
        NEUTRAL_HEX,
        OTS_ORANGE,
        '#22c55e',
        '#f59e0b',
        '#8b5cf6',
        '#ef4444',
      ];
      for (const hex of colors) {
        const [L, C, H] = hexToOklch(hex);
        const result = oklchToHex(L, C, H);
        const [r1, g1, b1] = hexToSrgbValues(hex);
        const [r2, g2, b2] = hexToSrgbValues(result);
        expect(Math.abs(r1 - r2)).toBeLessThanOrEqual(1);
        expect(Math.abs(g1 - g2)).toBeLessThanOrEqual(1);
        expect(Math.abs(b1 - b2)).toBeLessThanOrEqual(1);
      }
    });
  });

  describe('WCAG contrast', () => {
    describe('contrastRatio', () => {
      it('returns ~21:1 for black against white', () => {
        const ratio = contrastRatio('#000000', '#ffffff');
        expect(ratio).toBeCloseTo(21, 0);
      });

      it('returns ~1:1 for identical colors', () => {
        const ratio = contrastRatio(NEUTRAL_HEX, NEUTRAL_HEX);
        expect(ratio).toBeCloseTo(1, 1);
      });

      it('is symmetric — order of arguments does not change result', () => {
        const ab = contrastRatio(NEUTRAL_HEX, '#ffffff');
        const ba = contrastRatio('#ffffff', NEUTRAL_HEX);
        expect(ab).toBeCloseTo(ba, 5);
      });

      it('returns a value in [1, 21]', () => {
        const ratio = contrastRatio('#808080', '#ffffff');
        expect(ratio).toBeGreaterThanOrEqual(1);
        expect(ratio).toBeLessThanOrEqual(21);
      });
    });

    describe('checkBrandContrast', () => {
      const edgeCases: Array<{
        name: string;
        hex: string;
        expectWhiteText: boolean;
        minRatio: number;
      }> = [
        {
          name: 'neutral default blue (#3B82F6)',
          hex: NEUTRAL_HEX,
          expectWhiteText: false, // black at ~5.71:1 vs white's ~3.68:1
          minRatio: 4.5,
        },
        {
          name: 'saturated orange (#dc4a22)',
          hex: OTS_ORANGE,
          expectWhiteText: false, // black at ~5.05:1 vs white's ~4.16:1
          minRatio: 4.5,
        },
        {
          name: 'near-white (#f0f0f0)',
          hex: '#f0f0f0',
          expectWhiteText: false,
          minRatio: 14.0,
        },
        {
          name: 'near-black (#1a1a1a)',
          hex: '#1a1a1a',
          expectWhiteText: true,
          minRatio: 14.0,
        },
        {
          name: 'mid-gray (#808080)',
          hex: '#808080',
          expectWhiteText: false,
          minRatio: 4.5,
        },
      ];

      it.each(edgeCases)(
        '$name: returns a well-formed ContrastCheck',
        ({ hex }) => {
          const result: ContrastCheck = checkBrandContrast(hex);
          expect(result.ratio).toBeGreaterThanOrEqual(1);
          expect(result.ratio).toBeLessThanOrEqual(21);
          expect(typeof result.passesAA).toBe('boolean');
          expect(typeof result.passesAALarge).toBe('boolean');
          expect(typeof result.useWhiteText).toBe('boolean');
        }
      );

      it.each(edgeCases)(
        '$name: recommends correct text color',
        ({ hex, expectWhiteText }) => {
          const result = checkBrandContrast(hex);
          expect(result.useWhiteText).toBe(expectWhiteText);
        }
      );

      it.each(edgeCases)(
        '$name: meets minimum expected contrast ratio',
        ({ hex, minRatio }) => {
          const result = checkBrandContrast(hex);
          expect(result.ratio).toBeGreaterThanOrEqual(minRatio);
        }
      );
    });
  });

  describe('regression guard — neutral defaults (#3048 / #3049)', () => {
    it('the documented default constant is the neutral blue, not OTS orange', () => {
      expect(NEUTRAL_HEX.toLowerCase()).toBe('#3b82f6');
      expect(NEUTRAL_HEX.toLowerCase()).not.toBe(OTS_ORANGE.toLowerCase());
    });

    it('palette generated from neutral default differs from OTS-orange palette', () => {
      const neutral = generateBrandPalette(NEUTRAL_HEX);
      const orange = generateBrandPalette(OTS_ORANGE);
      // Spot check the key shade — neutral and orange must not collide.
      expect(neutral['--color-brand-500']).not.toEqual(orange['--color-brand-500']);
    });
  });
});
