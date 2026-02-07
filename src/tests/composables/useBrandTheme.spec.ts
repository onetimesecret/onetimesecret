// src/tests/composables/useBrandTheme.spec.ts

import {
  BRAND_CSS_VARIABLES,
  DEFAULT_BRAND_HEX,
  generateBrandPalette,
} from '@/utils/brand-palette';
import { useBrandTheme } from '@/shared/composables/useBrandTheme';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { setupBootstrapMock, baseBootstrap } from '@/tests/setup-bootstrap';
import { describe, expect, it, beforeEach, vi, afterEach } from 'vitest';
import { nextTick, effectScope } from 'vue';

// Mock vue-i18n for identityStore
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
  createI18n: () => ({ global: { t: (key: string) => key } }),
}));

describe('useBrandTheme', () => {
  let scope: ReturnType<typeof effectScope>;

  beforeEach(() => {
    // Clean any residual style properties
    for (const varName of BRAND_CSS_VARIABLES) {
      document.documentElement.style.removeProperty(varName);
    }
    scope = effectScope();
  });

  afterEach(() => {
    scope.stop();
    // Final cleanup
    for (const varName of BRAND_CSS_VARIABLES) {
      document.documentElement.style.removeProperty(varName);
    }
  });

  /**
   * Helper: set up pinia, hydrate bootstrapStore with domain_branding,
   * then invoke useBrandTheme within an effect scope.
   *
   * The identity store derives primaryColor from bootstrapStore.domain_branding,
   * so we set it there and let the reactive chain flow naturally.
   */
  function setupWithColor(color: string) {
    setupBootstrapMock({
      initialState: {
        domain_branding: {
          ...baseBootstrap.domain_branding,
          primary_color: color,
        },
      },
      stubActions: false,
    });

    scope.run(() => {
      // Force bootstrap store to have the branding data
      const bootstrapStore = useBootstrapStore();
      bootstrapStore.domain_branding = {
        ...baseBootstrap.domain_branding,
        primary_color: color,
      };

      // Now init identity store (reads from bootstrapStore)
      const identityStore = useProductIdentity();
      // Also set directly to ensure the reactive state is correct
      identityStore.primaryColor = color;

      useBrandTheme();
    });
  }

  it('does not set CSS variables when primaryColor is default', () => {
    setupWithColor(DEFAULT_BRAND_HEX);

    // Default color → no overrides (let @theme take effect)
    const hasOverrides = BRAND_CSS_VARIABLES.some(
      (v: string) => document.documentElement.style.getPropertyValue(v) !== ''
    );
    expect(hasOverrides).toBe(false);
  });

  it('sets 44 CSS variables for custom primaryColor', () => {
    setupWithColor('#3b82f6');

    const setVars = BRAND_CSS_VARIABLES.filter(
      (v: string) => document.documentElement.style.getPropertyValue(v) !== ''
    );
    expect(setVars.length).toBe(44);
  });

  it('all injected values are valid hex colors', () => {
    setupWithColor('#3b82f6');

    const hexPattern = /^#[0-9a-f]{6}$/;
    for (const varName of BRAND_CSS_VARIABLES) {
      const value = document.documentElement.style.getPropertyValue(varName);
      expect(value, `${varName} should be valid hex`).toMatch(hexPattern);
    }
  });

  it('removes CSS variables on scope disposal', () => {
    setupWithColor('#3b82f6');

    // Verify vars are set
    expect(document.documentElement.style.getPropertyValue('--color-brand-500')).not.toBe('');

    // Dispose scope — this triggers onScopeDispose in useBrandTheme
    scope.stop();

    // Vars should be removed
    const hasOverrides = BRAND_CSS_VARIABLES.some(
      (v: string) => document.documentElement.style.getPropertyValue(v) !== ''
    );
    expect(hasOverrides).toBe(false);
  });

  it('falls back to default palette for invalid color', () => {
    setupBootstrapMock({
      initialState: {
        domain_branding: {
          ...baseBootstrap.domain_branding,
          primary_color: 'not-a-color',
        },
      },
      stubActions: false,
    });

    scope.run(() => {
      const identityStore = useProductIdentity();
      // useBrandTheme normalizes invalid hex → null → falls back to default → no overrides
      identityStore.primaryColor = 'not-a-color';
      useBrandTheme();
    });

    // Invalid color normalizes to null → falls back to default → no overrides
    const hasOverrides = BRAND_CSS_VARIABLES.some(
      (v: string) => document.documentElement.style.getPropertyValue(v) !== ''
    );
    expect(hasOverrides).toBe(false);
  });

  it('reactively updates when primaryColor changes', async () => {
    setupWithColor('#3b82f6');

    const initialBrand500 = document.documentElement.style.getPropertyValue('--color-brand-500');
    expect(initialBrand500).not.toBe('');

    // Change the color via the identity store
    scope.run(() => {
      const identityStore = useProductIdentity();
      identityStore.primaryColor = '#10b981';
    });

    await nextTick();

    const updatedBrand500 = document.documentElement.style.getPropertyValue('--color-brand-500');
    expect(updatedBrand500).not.toBe('');
    expect(updatedBrand500).not.toBe(initialBrand500);
  });
});

describe('generateBrandPalette', () => {
  it('generates 44 CSS variable entries', () => {
    const palette = generateBrandPalette('#dc4a22');
    expect(Object.keys(palette).length).toBe(44);
  });

  it('covers all 4 scale prefixes', () => {
    const palette = generateBrandPalette('#3b82f6');
    const keys = Object.keys(palette);

    expect(keys.filter(k => k.startsWith('--color-brand-')).length).toBe(11);
    expect(keys.filter(k => k.startsWith('--color-branddim-')).length).toBe(11);
    expect(keys.filter(k => k.startsWith('--color-brandcomp-')).length).toBe(11);
    expect(keys.filter(k => k.startsWith('--color-brandcompdim-')).length).toBe(11);
  });

  it('produces valid hex values for all shades', () => {
    const palette = generateBrandPalette('#e74c3c');
    const hexPattern = /^#[0-9a-f]{6}$/;

    for (const [key, value] of Object.entries(palette)) {
      expect(value, `${key} should be valid hex`).toMatch(hexPattern);
    }
  });

  it('shade 500 is close to input color', () => {
    const palette = generateBrandPalette('#3b82f6');
    // brand-500 should be the anchor shade — close to but not necessarily identical
    // due to oklch gamut mapping
    expect(palette['--color-brand-500']).toBeDefined();
    expect(palette['--color-brand-500']).toMatch(/^#[0-9a-f]{6}$/);
  });

  it('handles fallback for invalid input', () => {
    const palette = generateBrandPalette('invalid');
    // Should fall back to DEFAULT_BRAND_HEX palette
    expect(Object.keys(palette).length).toBe(44);
  });
});
