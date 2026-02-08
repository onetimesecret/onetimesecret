// src/tests/schemas/models/brand-roundtrip.spec.ts
//
// Round-trip validation: simulated backend color values → Zod schema
// → generateBrandPalette. Catches mismatches between Ruby validation
// (BrandSettings.valid_color?) and frontend validation (isValidHex).

import { describe, expect, it } from 'vitest';
import { brandSettingSchema } from '@/schemas/models/domain/brand';
import {
  DEFAULT_BRAND_HEX,
  generateBrandPalette,
  isValidHex,
} from '@/utils/brand-palette';

/**
 * Simulates a color value arriving from the Ruby backend
 * through the Zod schema and into the palette generator.
 * Returns the brand-500 shade or null if any step fails.
 */
function roundTrip(
  inputColor: unknown
): { zodOutput: string | null | undefined; paletteColor: string | null } {
  // Step 1: Parse through Zod (like identityStore does)
  const parsed = brandSettingSchema.safeParse({ primary_color: inputColor });
  const zodOutput = parsed.success ? parsed.data.primary_color : null;

  // Step 2: Feed into palette generator (like useBrandTheme does)
  const palette = generateBrandPalette(zodOutput ?? null);
  const paletteColor = palette['--color-brand-500'];

  return { zodOutput, paletteColor };
}

describe('brand color round-trip validation', () => {
  describe('valid 6-digit hex colors', () => {
    it('lowercase 6-digit hex survives the full round-trip', () => {
      const { zodOutput, paletteColor } = roundTrip('#3b82f6');
      expect(zodOutput).toBe('#3b82f6');
      expect(isValidHex(zodOutput!)).toBe(true);
      // brand-500 should be perceptually close to input
      expect(paletteColor).toMatch(/^#[0-9a-f]{6}$/);
      // Should NOT fall back to the default (using non-default color)
      const defaultPalette = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(paletteColor).not.toEqual(defaultPalette['--color-brand-500']);
    });

    it('uppercase 6-digit hex survives the full round-trip', () => {
      const { zodOutput, paletteColor } = roundTrip('#DC4A22');
      // Zod regex accepts uppercase; no case transform in schema for hex body
      expect(zodOutput).toBeTruthy();
      expect(isValidHex(zodOutput!)).toBe(true);
      expect(paletteColor).toMatch(/^#[0-9a-f]{6}$/);
    });

    it('mixed case 6-digit hex survives the full round-trip', () => {
      const { zodOutput } = roundTrip('#Dc4A22');
      expect(zodOutput).toBeTruthy();
      expect(isValidHex(zodOutput!)).toBe(true);
    });
  });

  describe('3-digit hex shorthand', () => {
    // Ruby BrandSettings.valid_color? accepts #F00 and normalizes it.
    // Zod schema also accepts 3-digit hex and expands it.
    // brand-palette isValidHex rejects 3-digit hex.
    // This round-trip test verifies the Zod schema normalizes 3-digit
    // to 6-digit BEFORE it reaches the palette generator.

    it('3-digit hex is expanded to 6-digit by Zod and accepted by palette', () => {
      const { zodOutput, paletteColor } = roundTrip('#F00');
      // Zod schema transforms #F00 -> #FF0000
      expect(zodOutput).toBe('#FF0000');
      expect(isValidHex(zodOutput!)).toBe(true);
      expect(paletteColor).toMatch(/^#[0-9a-f]{6}$/);
    });

    it('3-digit lowercase hex is expanded by Zod', () => {
      const { zodOutput } = roundTrip('#abc');
      expect(zodOutput).toBe('#AABBCC');
      expect(isValidHex(zodOutput!)).toBe(true);
    });
  });

  describe('edge cases: empty and null values', () => {
    it('null primary_color passes Zod (nullish) and palette falls back to default', () => {
      const { zodOutput, paletteColor } = roundTrip(null);
      expect(zodOutput).toBeNull();
      const defaultPalette = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(paletteColor).toEqual(defaultPalette['--color-brand-500']);
    });

    it('undefined primary_color passes Zod (nullish) and palette falls back to default', () => {
      const { zodOutput, paletteColor } = roundTrip(undefined);
      expect(zodOutput).toBeUndefined();
      const defaultPalette = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(paletteColor).toEqual(defaultPalette['--color-brand-500']);
    });

    it('empty string fails Zod validation', () => {
      const parsed = brandSettingSchema.safeParse({ primary_color: '' });
      // Empty string should fail the hex regex in the schema
      expect(parsed.success).toBe(false);
    });
  });

  describe('invalid colors', () => {
    it('invalid hex string fails Zod validation', () => {
      const parsed = brandSettingSchema.safeParse({ primary_color: 'not-a-color' });
      expect(parsed.success).toBe(false);
    });

    it('rgb() format fails Zod validation', () => {
      const parsed = brandSettingSchema.safeParse({ primary_color: 'rgb(220,74,34)' });
      expect(parsed.success).toBe(false);
    });

    it('hex without # prefix fails Zod validation', () => {
      const parsed = brandSettingSchema.safeParse({ primary_color: 'dc4a22' });
      // Zod schema requires # prefix (regex: ^#...)
      expect(parsed.success).toBe(false);
    });
  });

  describe('absent primary_color (no field in payload)', () => {
    it('omitted field produces nullish output', () => {
      const parsed = brandSettingSchema.safeParse({});
      expect(parsed.success).toBe(true);
      // primary_color is nullish so omitting it is fine
      expect(parsed.data!.primary_color).toBeUndefined();
    });

    it('palette generator falls back to default for undefined', () => {
      const palette = generateBrandPalette(undefined as unknown as string);
      const defaultPalette = generateBrandPalette(DEFAULT_BRAND_HEX);
      expect(palette).toEqual(defaultPalette);
    });
  });

  describe('Ruby vs Zod validation alignment', () => {
    // Ruby BrandSettings.valid_color? accepts: #FFF, #FFFFFF (3 or 6 digit with #)
    // Zod brandSettingSchema accepts: #FFF, #FFFFFF (3 or 6 digit with #)
    // brand-palette isValidHex accepts: #FFFFFF, FFFFFF (6 digit, # optional)
    //
    // The key invariant: any color that passes Zod MUST be accepted
    // by isValidHex after Zod's transform normalizes it.

    const colorsAcceptedByRuby = [
      '#dc4a22',
      '#DC4A22',
      '#F00',     // 3-digit
      '#fff',     // 3-digit lowercase
      '#000000',
      '#FFFFFF',
    ];

    for (const color of colorsAcceptedByRuby) {
      it(`Ruby-valid color "${color}" survives Zod → palette round-trip`, () => {
        const { zodOutput } = roundTrip(color);
        expect(zodOutput).toBeTruthy();
        expect(isValidHex(zodOutput!)).toBe(true);
      });
    }
  });
});
