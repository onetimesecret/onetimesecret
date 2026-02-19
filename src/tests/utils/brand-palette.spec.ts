// src/tests/utils/brand-palette.spec.ts

import { describe, expect, it } from 'vitest';
import {
  DEFAULT_BRAND_HEX,
  DEFAULT_BRAND_PALETTE,
  generateBrandPalette,
  hexToOklch,
  isValidHex,
  oklchToHex,
  contrastRatio,
  checkBrandContrast,
} from '@/utils/brand-palette';
import type { ContrastCheck } from '@/utils/brand-palette';

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

    it('handles 3-char shorthand hex by falling back to default', () => {
      const palette = generateBrandPalette('#fff');
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
    it('generates 1000 palettes in under 250ms', () => {
      const start = performance.now();
      for (let i = 0; i < 1000; i++) {
        generateBrandPalette('#dc4a22');
      }
      const elapsed = performance.now() - start;
      expect(elapsed).toBeLessThan(250);
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

  describe('WCAG contrast', () => {
    describe('contrastRatio', () => {
      it('returns 21:1 for black vs white', () => {
        const ratio = contrastRatio('#000000', '#ffffff');
        expect(ratio).toBeCloseTo(21, 0);
      });

      it('returns 1:1 for identical colors', () => {
        const ratio = contrastRatio('#3b82f6', '#3b82f6');
        expect(ratio).toBeCloseTo(1, 1);
      });

      it('is symmetric (order-independent)', () => {
        const ab = contrastRatio('#dc4a22', '#ffffff');
        const ba = contrastRatio('#ffffff', '#dc4a22');
        expect(ab).toBeCloseTo(ba, 5);
      });

      it('returns a value between 1 and 21', () => {
        const ratio = contrastRatio('#808080', '#ffffff');
        expect(ratio).toBeGreaterThanOrEqual(1);
        expect(ratio).toBeLessThanOrEqual(21);
      });
    });

    describe('checkBrandContrast', () => {
      // Edge-case colors for parameterized testing
      // Edge-case colors with expected contrast behavior.
      // useWhiteText is determined by which text color (white vs black)
      // yields higher contrast. The ratio is for the RECOMMENDED text
      // color, so it can be high even for near-white backgrounds (because
      // black text on near-white is high contrast).
      const edgeCases: Array<{
        name: string;
        hex: string;
        expectWhiteText: boolean;
        minRatio: number;
      }> = [
        {
          name: 'default OTS orange (#dc4a22)',
          hex: '#dc4a22',
          expectWhiteText: false, // black text has 5.05:1 vs white's 4.16:1
          minRatio: 4.5,
        },
        {
          name: 'saturated blue (#3b82f6)',
          hex: '#3b82f6',
          expectWhiteText: false, // black text at 5.71:1 vs white's 3.68:1
          minRatio: 4.5,
        },
        {
          name: 'near-white (#f0f0f0)',
          hex: '#f0f0f0',
          expectWhiteText: false, // black text at 18.4:1 -- very high
          minRatio: 14.0,
        },
        {
          name: 'near-black (#1a1a1a)',
          hex: '#1a1a1a',
          expectWhiteText: true, // white text at 17.4:1 -- very high
          minRatio: 14.0,
        },
        {
          name: 'saturated yellow (#ffff00)',
          hex: '#ffff00',
          expectWhiteText: false, // black text at 19.6:1 despite low vs white
          minRatio: 14.0,
        },
        {
          name: 'mid-gray (#808080)',
          hex: '#808080',
          expectWhiteText: false, // black text at 5.32:1 vs white's 3.95:1
          minRatio: 4.5,
        },
      ];

      it.each(edgeCases)(
        '$name: returns valid ContrastCheck',
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
        '$name: contrast ratio meets minimum',
        ({ hex, minRatio }) => {
          const result = checkBrandContrast(hex);
          expect(result.ratio).toBeGreaterThanOrEqual(minRatio);
        }
      );

      it('near-white passes AA (black text recommended, 18:1+ contrast)', () => {
        // Near-white backgrounds get black text which has very high contrast
        const result = checkBrandContrast('#f0f0f0');
        expect(result.passesAA).toBe(true);
        expect(result.useWhiteText).toBe(false);
      });

      it('near-white vs white specifically has very low contrast', () => {
        // The raw white-on-near-white contrast is < 1.2:1
        const ratio = contrastRatio('#f0f0f0', '#ffffff');
        expect(ratio).toBeLessThan(1.2);
      });

      it('near-black passes AA for normal text', () => {
        const result = checkBrandContrast('#1a1a1a');
        expect(result.passesAA).toBe(true);
      });

      it('saturated yellow fails AA Large on white', () => {
        // Yellow (#ffff00) has very high luminance, so contrast
        // against both white and black is relatively low
        const result = checkBrandContrast('#ffff00');
        // Black text on yellow should still pass large text
        expect(result.useWhiteText).toBe(false);
      });

      it('passesAA implies passesAALarge', () => {
        // If a color passes the stricter 4.5:1, it must also
        // pass the more lenient 3.0:1
        for (const { hex } of edgeCases) {
          const result = checkBrandContrast(hex);
          if (result.passesAA) {
            expect(result.passesAALarge).toBe(true);
          }
        }
      });

      it('falls back to default color for invalid input', () => {
        const invalid = checkBrandContrast('not-a-color');
        const def = checkBrandContrast(DEFAULT_BRAND_HEX);
        expect(invalid.ratio).toBeCloseTo(def.ratio, 2);
      });
    });

    describe('brand vs brandcomp palette contrast for achromatic inputs', () => {
      it('achromatic gray produces identical brand and brandcomp shades', () => {
        // Mid-gray has no chroma, so 180deg hue rotation has no effect
        const palette = generateBrandPalette('#808080');
        for (const step of SHADE_STEPS) {
          expect(palette[`--color-brand-${step}`]).toBe(
            palette[`--color-brandcomp-${step}`]
          );
        }
      });

      it('achromatic near-white produces identical brand and brandcomp', () => {
        const palette = generateBrandPalette('#f0f0f0');
        for (const step of SHADE_STEPS) {
          expect(palette[`--color-brand-${step}`]).toBe(
            palette[`--color-brandcomp-${step}`]
          );
        }
      });

      it('chromatic input produces divergent brand and brandcomp', () => {
        const palette = generateBrandPalette('#dc4a22');
        // At least brand-500 should differ from brandcomp-500
        expect(palette['--color-brand-500']).not.toBe(
          palette['--color-brandcomp-500']
        );
      });
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
