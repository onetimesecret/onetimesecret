// src/tests/composables/useBrandTheme.spec.ts

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { nextTick, ref, effectScope } from 'vue';
import { generateBrandPalette, DEFAULT_BRAND_HEX } from '@/utils/brand-palette';

// The 44 CSS variable keys
const ALL_KEYS = Object.keys(generateBrandPalette(DEFAULT_BRAND_HEX));

// Mock the identity store with a controllable reactive ref
const mockPrimaryColor = ref<string>(DEFAULT_BRAND_HEX);

vi.mock('@/shared/stores/identityStore', () => ({
  useProductIdentity: () => ({}),
}));

vi.mock('pinia', async (importOriginal) => {
  const actual = await importOriginal<typeof import('pinia')>();
  return {
    ...actual,
    storeToRefs: () => ({
      primaryColor: mockPrimaryColor,
    }),
  };
});

// Import after mocks are set up
import { useBrandTheme } from '@/shared/composables/useBrandTheme';

describe('useBrandTheme', () => {
  beforeEach(() => {
    // Reset primaryColor to default
    mockPrimaryColor.value = DEFAULT_BRAND_HEX;
    // Clear any inline styles on documentElement
    for (const key of ALL_KEYS) {
      document.documentElement.style.removeProperty(key);
    }
  });

  it('does not set overrides for the default brand color', () => {
    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // Default color should remove (not set) overrides
    for (const key of ALL_KEYS) {
      expect(
        document.documentElement.style.getPropertyValue(key)
      ).toBe('');
    }

    scope.stop();
  });

  it('sets 44 CSS variables for a custom color', async () => {
    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // Change to a non-default color
    mockPrimaryColor.value = '#3b82f6';
    await nextTick();

    const palette = generateBrandPalette('#3b82f6');
    for (const [key, value] of Object.entries(palette)) {
      expect(
        document.documentElement.style.getPropertyValue(key)
      ).toBe(value);
    }

    scope.stop();
  });

  it('reactively updates when primaryColor changes', async () => {
    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // First custom color
    mockPrimaryColor.value = '#3b82f6';
    await nextTick();

    const bluePalette = generateBrandPalette('#3b82f6');
    expect(
      document.documentElement.style.getPropertyValue('--color-brand-500')
    ).toBe(bluePalette['--color-brand-500']);

    // Change to different custom color
    mockPrimaryColor.value = '#22c55e';
    await nextTick();

    const greenPalette = generateBrandPalette('#22c55e');
    expect(
      document.documentElement.style.getPropertyValue('--color-brand-500')
    ).toBe(greenPalette['--color-brand-500']);

    scope.stop();
  });

  it('removes all CSS variables on scope disposal', async () => {
    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // Set a custom color so vars are applied
    mockPrimaryColor.value = '#3b82f6';
    await nextTick();

    // Verify vars are set
    expect(
      document.documentElement.style.getPropertyValue('--color-brand-500')
    ).not.toBe('');

    // Dispose the scope
    scope.stop();

    // All vars should be removed
    for (const key of ALL_KEYS) {
      expect(
        document.documentElement.style.getPropertyValue(key)
      ).toBe('');
    }
  });

  it('removes overrides when color reverts to default', async () => {
    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // Set custom color
    mockPrimaryColor.value = '#3b82f6';
    await nextTick();
    expect(
      document.documentElement.style.getPropertyValue('--color-brand-500')
    ).not.toBe('');

    // Revert to default
    mockPrimaryColor.value = DEFAULT_BRAND_HEX;
    await nextTick();

    for (const key of ALL_KEYS) {
      expect(
        document.documentElement.style.getPropertyValue(key)
      ).toBe('');
    }

    scope.stop();
  });

  it('treats null/undefined as default color (no-op)', async () => {
    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // Set custom first
    mockPrimaryColor.value = '#3b82f6';
    await nextTick();

    // Set to empty string (falsy)
    mockPrimaryColor.value = '';
    await nextTick();

    // Should have removed all overrides
    for (const key of ALL_KEYS) {
      expect(
        document.documentElement.style.getPropertyValue(key)
      ).toBe('');
    }

    scope.stop();
  });

  it('gracefully handles palette generation errors', async () => {
    // Mock generateBrandPalette to throw on a specific input
    const generateSpy = vi.spyOn(
      await import('@/utils/brand-palette'),
      'generateBrandPalette'
    );
    generateSpy.mockImplementationOnce(() => {
      throw new Error('Simulated palette failure');
    });

    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // Set a custom color that will trigger the mocked throw
    mockPrimaryColor.value = '#ff0000';
    await nextTick();

    // Error should be caught — overrides removed, not set
    for (const key of ALL_KEYS) {
      expect(
        document.documentElement.style.getPropertyValue(key)
      ).toBe('');
    }

    generateSpy.mockRestore();
    scope.stop();
  });

  it('falls back to default palette for invalid hex input', async () => {
    const scope = effectScope();
    scope.run(() => {
      useBrandTheme();
    });

    // Set an invalid hex — generateBrandPalette falls back to default
    // Since the color string is not DEFAULT_BRAND_HEX, isDefaultColor
    // returns false, so it will call generateBrandPalette which
    // internally falls back. The vars will be set to default values.
    mockPrimaryColor.value = 'not-a-color';
    await nextTick();

    const defaultPalette = generateBrandPalette(DEFAULT_BRAND_HEX);
    expect(
      document.documentElement.style.getPropertyValue('--color-brand-500')
    ).toBe(defaultPalette['--color-brand-500']);

    scope.stop();
  });
});
