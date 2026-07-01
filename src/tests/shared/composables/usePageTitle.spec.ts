// src/tests/shared/composables/usePageTitle.spec.ts
//
// A4 fix: the page-title composable must never leak OTS branding into the
// document <title>, og:title or twitter:title. When no display domain is
// available it falls back to the configured brand product name, and finally to
// the neutral default ('My App') — never the hardcoded "Onetime Secret".
//
// The product-name fallback goes through the shared resolveProductName helper
// (the same one identityStore.productName uses) rather than the store itself,
// because usePageTitle runs in router guards, outside a component/i18n context.
// These tests exercise getAppName()'s fallback chain via the public
// formatTitle() / setTitle() API and assert on the resulting jsdom document.title.

import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import { usePageTitle } from '@/shared/composables/usePageTitle';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// usePageTitle reads `const { t, te } = globalComposer` from '@/i18n' at the
// top of the composable (so it can run outside a component setup context).
// Mock the module to supply a deterministic, pass-through composer:
//   - te() returns false so titles are treated as plain strings, not i18n keys
//   - t() echoes the key back (never reached here, kept for completeness)
vi.mock('@/i18n', () => ({
  globalComposer: {
    t: (key: string) => key,
    te: () => false,
  },
}));

/**
 * Installs a fresh testing Pinia with the given bootstrap fields and makes it
 * the active instance so useBootstrapStore() (called inside usePageTitle)
 * resolves against it.
 */
const setupPinia = (bootstrap: {
  display_domain?: string;
  brand_product_name?: string | null;
}) => {
  const pinia = createTestingPinia({
    createSpy: vi.fn,
    stubActions: false,
    initialState: {
      bootstrap,
    },
  });
  setActivePinia(pinia);
  return pinia;
};

describe('usePageTitle — brand fallback (A4 branding leak)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset the jsdom title between cases so assertions are deterministic.
    document.title = '';
  });

  describe('getAppName fallback chain via formatTitle', () => {
    it('uses the display domain when it is set', () => {
      setupPinia({ display_domain: 'secrets.acme.com', brand_product_name: 'Acme Vault' });
      const { formatTitle } = usePageTitle();

      // The active domain wins over both the product name and the neutral default.
      expect(formatTitle('Dashboard')).toBe('Dashboard - secrets.acme.com');
    });

    it('falls back to brand_product_name when display_domain is empty', () => {
      setupPinia({ display_domain: '', brand_product_name: 'Acme Vault' });
      const { formatTitle } = usePageTitle();

      const title = formatTitle('Dashboard');
      expect(title).toBe('Dashboard - Acme Vault');
      expect(title).not.toContain('Onetime Secret');
    });

    it('falls back to the neutral default when both domain and product name are unset', () => {
      setupPinia({ display_domain: '', brand_product_name: null });
      const { formatTitle } = usePageTitle();

      const title = formatTitle('Dashboard');
      expect(title).toBe(`Dashboard - ${NEUTRAL_BRAND_DEFAULTS.product_name}`);
      expect(title).toContain('My App');
      // The core A4 guarantee: never emit OTS branding.
      expect(title).not.toContain('Onetime Secret');
    });

    it('falls back to the neutral default when brand_product_name is an empty string', () => {
      // An empty string is falsy and must fall through to the neutral default,
      // not produce a dangling separator or a blank app name.
      setupPinia({ display_domain: '', brand_product_name: '' });
      const { formatTitle } = usePageTitle();

      expect(formatTitle('Dashboard')).toBe(`Dashboard - ${NEUTRAL_BRAND_DEFAULTS.product_name}`);
    });
  });

  describe('setTitle updates document.title with the resolved app name', () => {
    it('sets "Page - <displayDomain>" when a page title is given', () => {
      setupPinia({ display_domain: 'secrets.acme.com', brand_product_name: null });
      const { setTitle } = usePageTitle();

      setTitle('Some Page');
      expect(document.title).toBe('Some Page - secrets.acme.com');
    });

    it('setTitle(null) yields just the app name (brand_product_name fallback)', () => {
      setupPinia({ display_domain: '', brand_product_name: 'Acme Vault' });
      const { setTitle } = usePageTitle();

      setTitle(null);
      expect(document.title).toBe('Acme Vault');
      expect(document.title).not.toContain('Onetime Secret');
    });

    it('setTitle(undefined) yields the neutral default when nothing is configured', () => {
      setupPinia({ display_domain: '', brand_product_name: null });
      const { setTitle } = usePageTitle();

      setTitle(undefined);
      expect(document.title).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
      expect(document.title).not.toContain('Onetime Secret');
    });
  });

  describe('formatTitle app-name-only collapsing', () => {
    it('returns just the app name when the page title equals the app name', () => {
      setupPinia({ display_domain: 'secrets.acme.com', brand_product_name: null });
      const { formatTitle } = usePageTitle();

      // Avoids "secrets.acme.com - secrets.acme.com" duplication.
      expect(formatTitle('secrets.acme.com')).toBe('secrets.acme.com');
    });
  });
});
