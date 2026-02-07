// src/tests/utils/brand-palette.spec.ts

import {
  generateBrandPalette,
  DEFAULT_BRAND_PALETTE,
  DEFAULT_BRAND_HEX,
  BRAND_CSS_VARIABLES,
  _internals,
} from '@/utils/brand-palette';
import { describe, expect, it } from 'vitest';

const { hexToOklch, normalizeHex } = _internals;

describe('generateBrandPalette', () => {
  describe('output structure', () => {
    it('generates exactly 44 CSS variable entries', () => {
      const palette = generateBrandPalette('#dc4a22');
      expect(Object.keys(palette)).toHaveLength(44);
    });

    it('produces 11 shades for each of 4 palettes', () => {
      const palette = generateBrandPalette('#dc4a22');
      const prefixes = ['--color-brand-', '--color-branddim-', '--color-brandcomp-', '--color-brandcompdim-'];
      const shades = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950'];

      for (const prefix of prefixes) {
        for (const shade of shades) {
          expect(palette).toHaveProperty(`${prefix}${shade}`);
        }
      }
    });

    it('all values are valid 7-character hex strings', () => {
      const palette = generateBrandPalette('#dc4a22');
      const hexPattern = /^#[0-9a-f]{6}$/;

      for (const [key, value] of Object.entries(palette)) {
        expect(value, `${key} should be valid hex`).toMatch(hexPattern);
      }
    });
  });

  describe('brand-500 fidelity', () => {
    it('brand-500 is perceptually close to the input color', () => {
      const palette = generateBrandPalette('#dc4a22');
      const inputOklch = hexToOklch('#dc4a22');
      const brand500Oklch = hexToOklch(palette['--color-brand-500']);

      // Hue should be very close (same hue, different lightness target)
      const hueDiff = Math.abs(inputOklch[2] - brand500Oklch[2]);
      expect(hueDiff, 'hue difference').toBeLessThan(5);
    });

    it('brand-500 for blue input is perceptually close', () => {
      const palette = generateBrandPalette('#3b82f6');
      const inputOklch = hexToOklch('#3b82f6');
      const brand500Oklch = hexToOklch(palette['--color-brand-500']);

      const hueDiff = Math.abs(inputOklch[2] - brand500Oklch[2]);
      expect(hueDiff, 'hue difference for blue').toBeLessThan(5);
    });
  });

  describe('complement hue rotation', () => {
    it('brandcomp hue is approximately 180° from brand hue', () => {
      const palette = generateBrandPalette('#dc4a22');
      const brandOklch = hexToOklch(palette['--color-brand-500']);
      const compOklch = hexToOklch(palette['--color-brandcomp-500']);

      // Calculate hue difference, accounting for wraparound
      let hueDiff = Math.abs(brandOklch[2] - compOklch[2]);
      if (hueDiff > 180) hueDiff = 360 - hueDiff;

      expect(hueDiff, 'complement hue offset').toBeGreaterThan(150);
      expect(hueDiff, 'complement hue offset').toBeLessThan(210);
    });
  });

  describe('lightness monotonicity', () => {
    it('lighter shades have higher lightness values', () => {
      const palette = generateBrandPalette('#dc4a22');
      const shades = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950'];

      for (const prefix of ['--color-brand-', '--color-brandcomp-']) {
        const lightnesses = shades.map((s) => hexToOklch(palette[`${prefix}${s}`])[0]);

        for (let i = 0; i < lightnesses.length - 1; i++) {
          expect(
            lightnesses[i],
            `${prefix}${shades[i]} (L=${lightnesses[i].toFixed(3)}) should be lighter than ${prefix}${shades[i + 1]} (L=${lightnesses[i + 1].toFixed(3)})`
          ).toBeGreaterThan(lightnesses[i + 1]);
        }
      }
    });
  });

  describe('dimmed variants', () => {
    it('branddim has lower chroma than brand at same shade', () => {
      const palette = generateBrandPalette('#dc4a22');
      // Check a mid-range shade where chroma differences are most visible
      const brandOklch = hexToOklch(palette['--color-brand-500']);
      const dimOklch = hexToOklch(palette['--color-branddim-500']);

      expect(dimOklch[1], 'dim chroma should be less than brand chroma').toBeLessThan(
        brandOklch[1]
      );
    });
  });

  describe('edge cases', () => {
    it('handles pure white input', () => {
      const palette = generateBrandPalette('#ffffff');
      expect(Object.keys(palette)).toHaveLength(44);
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('handles pure black input', () => {
      const palette = generateBrandPalette('#000000');
      expect(Object.keys(palette)).toHaveLength(44);
      for (const value of Object.values(palette)) {
        expect(value).toMatch(/^#[0-9a-f]{6}$/);
      }
    });

    it('handles 3-digit hex shorthand', () => {
      const palette = generateBrandPalette('#f00');
      expect(Object.keys(palette)).toHaveLength(44);
      expect(palette['--color-brand-500']).toMatch(/^#[0-9a-f]{6}$/);
    });

    it('falls back to default palette for invalid input', () => {
      const palette = generateBrandPalette('not-a-color');
      expect(palette).toEqual(DEFAULT_BRAND_PALETTE);
    });

    it('falls back to default palette for empty string', () => {
      const palette = generateBrandPalette('');
      expect(palette).toEqual(DEFAULT_BRAND_PALETTE);
    });

    it('handles hex without hash prefix', () => {
      const withHash = generateBrandPalette('#dc4a22');
      const withoutHash = generateBrandPalette('dc4a22');
      expect(withHash).toEqual(withoutHash);
    });
  });

  describe('DEFAULT_BRAND_PALETTE', () => {
    it('is pre-computed from DEFAULT_BRAND_HEX', () => {
      const freshPalette = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(DEFAULT_BRAND_PALETTE).toEqual(freshPalette);
    });

    it('has exactly 44 entries', () => {
      expect(Object.keys(DEFAULT_BRAND_PALETTE)).toHaveLength(44);
    });
  });

  describe('BRAND_CSS_VARIABLES', () => {
    it('lists all 44 variable names', () => {
      expect(BRAND_CSS_VARIABLES).toHaveLength(44);
    });

    it('all names start with --color-', () => {
      for (const name of BRAND_CSS_VARIABLES) {
        expect(name).toMatch(/^--color-(brand|branddim|brandcomp|brandcompdim)-/);
      }
    });
  });

  describe('normalizeHex', () => {
    it('normalizes 3-digit hex to 6-digit', () => {
      expect(normalizeHex('#f00')).toBe('#ff0000');
      expect(normalizeHex('#abc')).toBe('#aabbcc');
    });

    it('lowercases 6-digit hex', () => {
      expect(normalizeHex('#DC4A22')).toBe('#dc4a22');
    });

    it('handles missing hash prefix', () => {
      expect(normalizeHex('dc4a22')).toBe('#dc4a22');
    });

    it('returns null for invalid input', () => {
      expect(normalizeHex('')).toBeNull();
      expect(normalizeHex('not-hex')).toBeNull();
      expect(normalizeHex('#gg0000')).toBeNull();
      expect(normalizeHex('#12345')).toBeNull();
    });
  });

  describe('determinism', () => {
    it('produces identical output for same input across calls', () => {
      const a = generateBrandPalette('#dc4a22');
      const b = generateBrandPalette('#dc4a22');
      expect(a).toEqual(b);
    });

    it('produces different output for different inputs', () => {
      const orange = generateBrandPalette('#dc4a22');
      const blue = generateBrandPalette('#3b82f6');
      expect(orange['--color-brand-500']).not.toBe(blue['--color-brand-500']);
    });
  });

  describe('performance', () => {
    it('generates 1000 palettes in under 100ms', () => {
      const start = performance.now();
      for (let i = 0; i < 1000; i++) {
        generateBrandPalette(`#${(i * 256).toString(16).padStart(6, '0').slice(0, 6)}`);
      }
      const elapsed = performance.now() - start;
      expect(elapsed, `took ${elapsed.toFixed(1)}ms`).toBeLessThan(100);
    });
  });
});
