// src/tests/shared/composables/usePageTitle.spec.ts

import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

/**
 * Mocked refs that simulate bootstrapStore's reactive state.
 * Declared at module scope so vi.mock closures can reference them.
 */
const mockDisplayDomain = ref('');
const mockBrandProductName = ref('');

vi.mock('@/i18n', () => ({
  globalComposer: {
    t: (key: string) => `translated:${key}`,
    te: (key: string) => key.startsWith('i18n.'),
  },
}));

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    display_domain: mockDisplayDomain,
    brand_product_name: mockBrandProductName,
  }),
}));

// Must import after vi.mock declarations so hoisting applies correctly
import { usePageTitle } from '@/shared/composables/usePageTitle';

describe('usePageTitle', () => {
  beforeEach(() => {
    mockDisplayDomain.value = '';
    mockBrandProductName.value = '';
    document.title = '';
  });

  describe('DEFAULT_APP_NAME constant', () => {
    it('uses NEUTRAL_BRAND_DEFAULTS.product_name as the default app name', () => {
      const { formatTitle } = usePageTitle();

      // With no store values set, formatTitle should use the neutral default
      const result = formatTitle('Some Page');
      expect(result).toContain(NEUTRAL_BRAND_DEFAULTS.product_name);
      expect(result).toBe(`Some Page - ${NEUTRAL_BRAND_DEFAULTS.product_name}`);
    });

    it('does not use the legacy OTS string as default', () => {
      const { formatTitle } = usePageTitle();
      const result = formatTitle('Page');
      expect(result).not.toContain('OTS');
    });
  });

  describe('getAppName resolution (via formatTitle)', () => {
    it('falls back to NEUTRAL_BRAND_DEFAULTS.product_name when bootstrap is empty', () => {
      const { formatTitle } = usePageTitle();
      const result = formatTitle('Dashboard');
      expect(result).toBe(`Dashboard - ${NEUTRAL_BRAND_DEFAULTS.product_name}`);
    });

    it('uses brand_product_name from store when available', () => {
      mockBrandProductName.value = 'Acme Secrets';

      const { formatTitle } = usePageTitle();
      const result = formatTitle('Dashboard');
      expect(result).toBe('Dashboard - Acme Secrets');
    });

    it('uses display_domain when available, taking precedence over brand_product_name', () => {
      mockBrandProductName.value = 'Acme Secrets';
      mockDisplayDomain.value = 'secrets.acme.com';

      const { formatTitle } = usePageTitle();
      const result = formatTitle('Dashboard');
      expect(result).toBe('Dashboard - secrets.acme.com');
    });

    it('uses display_domain even when brand_product_name is empty', () => {
      mockDisplayDomain.value = 'my.domain.io';

      const { formatTitle } = usePageTitle();
      const result = formatTitle('Settings');
      expect(result).toBe('Settings - my.domain.io');
    });
  });

  describe('formatTitle', () => {
    it('returns "{pageTitle} - {appName}" format', () => {
      const { formatTitle } = usePageTitle();
      const result = formatTitle('Account');
      expect(result).toMatch(/^Account - .+$/);
    });

    it('returns just the app name when page title is empty', () => {
      const { formatTitle } = usePageTitle();
      const result = formatTitle('');
      expect(result).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
    });

    it('returns just the app name when page title matches app name', () => {
      mockBrandProductName.value = 'Acme';

      const { formatTitle } = usePageTitle();
      const result = formatTitle('Acme');
      expect(result).toBe('Acme');
    });

    it('translates i18n keys before formatting', () => {
      const { formatTitle } = usePageTitle();
      // Our mock te() returns true for keys starting with "i18n."
      // and mock t() returns "translated:{key}"
      const result = formatTitle('i18n.dashboard.title');
      expect(result).toBe(
        `translated:i18n.dashboard.title - ${NEUTRAL_BRAND_DEFAULTS.product_name}`
      );
    });

    it('passes through plain strings without translation', () => {
      const { formatTitle } = usePageTitle();
      const result = formatTitle('Plain Title');
      expect(result).toBe(`Plain Title - ${NEUTRAL_BRAND_DEFAULTS.product_name}`);
    });
  });

  describe('setTitle', () => {
    it('updates document.title with formatted title', () => {
      const { setTitle } = usePageTitle();
      setTitle('My Page');
      expect(document.title).toBe(`My Page - ${NEUTRAL_BRAND_DEFAULTS.product_name}`);
    });

    it('sets document.title to app name when called with null', () => {
      const { setTitle } = usePageTitle();
      setTitle(null);
      expect(document.title).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
    });

    it('sets document.title to app name when called with undefined', () => {
      const { setTitle } = usePageTitle();
      setTitle(undefined);
      expect(document.title).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
    });

    it('updates og:title meta tag when present', () => {
      const meta = document.createElement('meta');
      meta.setAttribute('property', 'og:title');
      document.head.appendChild(meta);

      const { setTitle } = usePageTitle();
      setTitle('OG Test');

      expect(meta.getAttribute('content')).toBe(
        `OG Test - ${NEUTRAL_BRAND_DEFAULTS.product_name}`
      );

      document.head.removeChild(meta);
    });

    it('updates twitter:title meta tag when present', () => {
      const meta = document.createElement('meta');
      meta.setAttribute('name', 'twitter:title');
      document.head.appendChild(meta);

      const { setTitle } = usePageTitle();
      setTitle('Twitter Test');

      expect(meta.getAttribute('content')).toBe(
        `Twitter Test - ${NEUTRAL_BRAND_DEFAULTS.product_name}`
      );

      document.head.removeChild(meta);
    });

    it('reflects brand_product_name changes in subsequent calls', () => {
      const { setTitle } = usePageTitle();

      setTitle('Page');
      expect(document.title).toBe(`Page - ${NEUTRAL_BRAND_DEFAULTS.product_name}`);

      mockBrandProductName.value = 'New Brand';
      setTitle('Page');
      expect(document.title).toBe('Page - New Brand');
    });
  });
});
