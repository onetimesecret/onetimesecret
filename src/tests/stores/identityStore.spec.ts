// src/tests/stores/identityStore.spec.ts
//
// Tests the partial-override fallback chain in identityStore.
// Verifies that when a domain sets some brand properties but not others,
// the ?? coalescing correctly falls through to install config or defaults.

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import * as bootstrapService from '@/services/bootstrap.service';
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
import { setupTestPinia } from '../setup';
import { baseBootstrap } from '../setup-bootstrap';
import type { BootstrapPayload } from '@/types/declarations/bootstrap';

// Mock vue-i18n before importing identityStore (which calls useI18n)
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
    locale: { value: 'en' },
  }),
  createI18n: vi.fn(() => ({
    global: { t: (key: string) => key, locale: 'en' },
    install: vi.fn(),
  })),
}));

// Mock the bootstrap service
vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapSnapshot: vi.fn(),
  _resetForTesting: vi.fn(),
}));

// Import identityStore after mocks are in place
import { useProductIdentity } from '@/shared/stores/identityStore';

describe('identityStore - partial-override fallback chain', () => {
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;
  let mockGetBootstrapSnapshot: Mock;

  beforeEach(async () => {
    vi.clearAllMocks();
    mockGetBootstrapSnapshot = vi.mocked(bootstrapService.getBootstrapSnapshot);
    await setupTestPinia();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('primary_color fallback chain', () => {
    it('resolves domain color when domain sets color but not font', () => {
      // Scenario: domain sets primary_color only, install config sets font_family
      const partialDomainBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          primary_color: '#0d9488',
          // font_family intentionally omitted -- should fall to Zod default
        },
        brand_font_family: 'serif',
        brand_primary_color: undefined,
      };

      mockGetBootstrapSnapshot.mockReturnValue(partialDomainBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      // Domain color should be used (step 1 of fallback chain)
      expect(identityStore.primaryColor).toBe('#0d9488');
    });

    it('falls back to install config color when domain omits color', () => {
      // Scenario: domain has no primary_color, install config provides one
      const noColorBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          font_family: 'mono',
          // primary_color intentionally omitted
        },
        brand_primary_color: '#6366f1',
      };

      mockGetBootstrapSnapshot.mockReturnValue(noColorBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      // Install config color should be used (step 2 of fallback chain)
      expect(identityStore.primaryColor).toBe('#6366f1');
    });

    it('falls back to hardcoded default when both domain and install omit color', () => {
      const noBrandingBootstrap: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          font_family: 'sans',
          // primary_color intentionally omitted
        },
        brand_primary_color: undefined,
      };

      mockGetBootstrapSnapshot.mockReturnValue(noBrandingBootstrap);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      // Should fall through to NEUTRAL_BRAND_DEFAULTS (blue #3B82F6, not OTS orange)
      expect(identityStore.primaryColor).toBe('#3B82F6');
    });
  });

  describe('font_family resolution', () => {
    it('uses Zod default when domain omits font_family', () => {
      // font_family has .default('sans') in the Zod schema, so it always resolves.
      // The install-level brand_font_family is NOT in the identityStore fallback
      // chain for font -- only color and allow_public_homepage have multi-step chains.
      const partialBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          primary_color: '#0d9488',
          // font_family omitted -- Zod default 'sans' will apply
        },
        brand_font_family: 'serif', // install config says serif, but won't be consulted
      };

      mockGetBootstrapSnapshot.mockReturnValue(partialBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      // fontFamilyClass resolves from Zod default ('sans'), not install config ('serif')
      expect(identityStore.fontFamilyClass).toBe('font-sans');
    });

    it('uses domain font_family when explicitly set', () => {
      const explicitFontBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          primary_color: '#0d9488',
          font_family: 'mono',
        },
      };

      mockGetBootstrapSnapshot.mockReturnValue(explicitFontBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      expect(identityStore.fontFamilyClass).toBe('font-mono');
    });
  });

  describe('corner_style resolution', () => {
    it('uses Zod default when domain omits corner_style', () => {
      const partialBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          primary_color: '#0d9488',
          // corner_style omitted -- Zod default 'rounded' will apply
        },
      };

      mockGetBootstrapSnapshot.mockReturnValue(partialBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      // cornerClass resolves from Zod default 'rounded' -> 'rounded-md'
      expect(identityStore.cornerClass).toBe('rounded-md');
    });

    it('uses domain corner_style when explicitly set to pill', () => {
      const pillBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          primary_color: '#0d9488',
          corner_style: 'pill',
        },
      };

      mockGetBootstrapSnapshot.mockReturnValue(pillBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      expect(identityStore.cornerClass).toBe('rounded-xl');
    });
  });

  describe('null vs undefined coalescing for primary_color', () => {
    it('treats null primary_color as absent (falls through ??)', () => {
      const nullColorBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          primary_color: null,
        },
        brand_primary_color: '#e11d48',
      };

      mockGetBootstrapSnapshot.mockReturnValue(nullColorBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      // null should fall through ?? to install config
      expect(identityStore.primaryColor).toBe('#e11d48');
    });

    it('treats undefined primary_color as absent (falls through ??)', () => {
      const undefinedColorBranding: BootstrapPayload = {
        ...baseBootstrap,
        domain_branding: {
          // primary_color not set at all (undefined)
        },
        brand_primary_color: '#e11d48',
      };

      mockGetBootstrapSnapshot.mockReturnValue(undefinedColorBranding);
      bootstrapStore = useBootstrapStore();
      bootstrapStore.init();

      const identityStore = useProductIdentity();

      // undefined should fall through ?? to install config
      expect(identityStore.primaryColor).toBe('#e11d48');
    });
  });
});
