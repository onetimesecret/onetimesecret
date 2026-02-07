// src/tests/utils/brand-palette.spec.ts

import { describe, expect, it } from 'vitest';
import {
  DEFAULT_BRAND_HEX,
  DEFAULT_BRAND_PALETTE,
  generateBrandPalette,
  hexToOklch,
  isValidHex,
  oklchToHex,
} from '@/utils/brand-palette';

const SHADE_STEPS = [
  '50', '100', '200', '300', '400', '500',
  '600', '700', '800', '900', '950',
];
const PALETTE_PREFIXES = [
  'brand', 'branddim', 'brandcomp', 'brandcompdim',
];

describe('brand-palette', () => {
  describe('generateBrandPalette', () => {
    it('generates 44 CSS variable entries', () => {
      const palette = generateBrandPalette('#dc4a22');
      expect(Object.keys(palette)).toHaveLength(44);
    });

    it('uses correct CSS variable naming convention', () => {
      const palette = generateBrandPalette('#dc4a22');
      for (const prefix of PALETTE_PREFIXES) {
        for (const step of SHADE_STEPS) {
          const key = `--color-${prefix}-${step}`;
          expect(palette).toHaveProperty(key);
        }
      }
    });

    it('produces valid hex color values', () => {
      const palette = generateBrandPalette('#dc4a22');
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('brand-500 is perceptually close to input color', () => {
      const palette = generateBrandPalette('#dc4a22');
      // Should be the same color (roundtrip through oklch)
      const [L1, C1, H1] = hexToOklch('#dc4a22');
      const [L2, C2, H2] = hexToOklch(palette['--color-brand-500']);
      expect(Math.abs(L1 - L2)).toBeLessThan(0.02);
      expect(Math.abs(C1 - C2)).toBeLessThan(0.02);
      expect(Math.abs(H1 - H2)).toBeLessThan(2);
    });

    it('brandcomp hue is ~180° from brand hue', () => {
      const palette = generateBrandPalette('#dc4a22');
      const [, , brandH] = hexToOklch(palette['--color-brand-500']);
      const [, , compH] = hexToOklch(
        palette['--color-brandcomp-500']
      );
      // Normalize hue difference to [0, 360), then check
      // distance from 180°
      const hueDiff = ((compH - brandH) % 360 + 360) % 360;
      expect(Math.abs(hueDiff - 180)).toBeLessThan(5);
    });

    it('lighter shades have higher lightness (monotonic)', () => {
      const palette = generateBrandPalette('#dc4a22');
      for (const prefix of PALETTE_PREFIXES) {
        const lightness = SHADE_STEPS.map((step) => {
          const hex = palette[`--color-${prefix}-${step}`];
          const [L] = hexToOklch(hex);
          return L;
        });
        // Each shade should be lighter than the next
        for (let i = 0; i < lightness.length - 1; i++) {
          expect(lightness[i]).toBeGreaterThan(lightness[i + 1]);
        }
      }
    });

    it('handles edge case: pure white input', () => {
      const palette = generateBrandPalette('#ffffff');
      expect(Object.keys(palette)).toHaveLength(44);
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('handles edge case: pure black input', () => {
      const palette = generateBrandPalette('#000000');
      expect(Object.keys(palette)).toHaveLength(44);
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('handles invalid input by falling back to default', () => {
      const invalid = generateBrandPalette('not-a-color');
      const fallback = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(invalid).toEqual(fallback);
    });

    it('handles null input by falling back to default', () => {
      const palette = generateBrandPalette(null);
      const fallback = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(palette).toEqual(fallback);
    });

    it('handles hex without # prefix', () => {
      const with_ = generateBrandPalette('#3b82f6');
      const without = generateBrandPalette('3b82f6');
      expect(with_).toEqual(without);
    });

    it('produces different palettes for different inputs', () => {
      const orange = generateBrandPalette('#dc4a22');
      const blue = generateBrandPalette('#3b82f6');
      expect(orange['--color-brand-500']).not.toEqual(
        blue['--color-brand-500']
      );
    });

    it('dim variants are darker than main variants', () => {
      const palette = generateBrandPalette('#dc4a22');
      const [mainL] = hexToOklch(palette['--color-brand-500']);
      const [dimL] = hexToOklch(palette['--color-branddim-500']);
      expect(dimL).toBeLessThan(mainL);
    });
  });

  describe('performance', () => {
    it('generates 1000 palettes in under 100ms', () => {
      const start = performance.now();
      for (let i = 0; i < 1000; i++) {
        generateBrandPalette('#dc4a22');
      }
      const elapsed = performance.now() - start;
      expect(elapsed).toBeLessThan(100);
    });
  });

  describe('DEFAULT_BRAND_PALETTE', () => {
    it('is pre-computed and available', () => {
      expect(Object.keys(DEFAULT_BRAND_PALETTE)).toHaveLength(44);
    });

    it('matches runtime generation', () => {
      const runtime = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(DEFAULT_BRAND_PALETTE).toEqual(runtime);
    });
  });

  describe('isValidHex', () => {
    it('accepts valid hex with #', () => {
      expect(isValidHex('#dc4a22')).toBe(true);
    });

    it('accepts valid hex without #', () => {
      expect(isValidHex('dc4a22')).toBe(true);
    });

    it('accepts uppercase hex', () => {
      expect(isValidHex('#DC4A22')).toBe(true);
    });

    it('rejects short hex', () => {
      expect(isValidHex('#fff')).toBe(false);
    });

    it('rejects invalid chars', () => {
      expect(isValidHex('#gggggg')).toBe(false);
    });

    it('rejects empty string', () => {
      expect(isValidHex('')).toBe(false);
    });
  });

  describe('color conversion roundtrip', () => {
    it('hex → oklch → hex roundtrips accurately', () => {
      const colors = [
        '#dc4a22', '#3b82f6', '#22c55e',
        '#f59e0b', '#8b5cf6', '#ef4444',
      ];
      for (const hex of colors) {
        const [L, C, H] = hexToOklch(hex);
        const result = oklchToHex(L, C, H);
        // Should roundtrip within 1 step (±1/255)
        const [r1, g1, b1] = hexToSrgbValues(hex);
        const [r2, g2, b2] = hexToSrgbValues(result);
        expect(Math.abs(r1 - r2)).toBeLessThanOrEqual(1);
        expect(Math.abs(g1 - g2)).toBeLessThanOrEqual(1);
        expect(Math.abs(b1 - b2)).toBeLessThanOrEqual(1);
      }
    });
  });
});

/** Helper: parse hex to [r, g, b] as 0-255 integers */
function hexToSrgbValues(
  hex: string
): [number, number, number] {
  const h = hex.replace('#', '');
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
  ];
}
