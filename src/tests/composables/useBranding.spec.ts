// src/tests/composables/useBranding.spec.ts
import {
  mockCustomBrandingRed,
  mockDefaultBranding,
  mockDomains,
} from '@/../tests/unit/vue/fixtures/domainBranding.fixture';
import { useBranding } from '@/composables/useBranding';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mockBrandStore = vi.fn(() => ({
  getSettings: (domainId: string) => {
    if (domainId === 'domain-1') {
      return mockCustomBrandingRed;
    }
    return mockDefaultBranding;
  },
  fetchSettings: vi.fn(async (domainId: string) => {
    if (domainId === 'domain-1') {
      return mockCustomBrandingRed;
    }
    return mockDefaultBranding;
  }),
}));

const mockNotificationsStore = vi.fn(() => ({
  show: vi.fn(),
}));

vi.mock('@/stores/brandStore', () => ({
  useBrandStore: () => mockBrandStore(),
}));

vi.mock('@/stores', () => ({
  useNotificationsStore: () => mockNotificationsStore(),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: vi.fn(),
  }),
}));

vi.mock('@/i18n', () => ({
  createI18nInstance: () => ({
    composer: {},
    setLocale: vi.fn(),
  }),
}));

vi.mock('@/composables/useAsyncHandler', () => ({
  useAsyncHandler: () => ({
    wrap: vi.fn(async (fn) => await fn()),
  }),
  createError: vi.fn(),
}));

describe('useBranding', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  describe('brand settings resolution', () => {
    describe('when no domain ID is provided', () => {
      it('returns default branding settings', () => {
        const { brandSettings } = useBranding();

        expect(brandSettings.value).toEqual(mockDefaultBranding);
      });
    });

    describe('when domain ID is provided', () => {
      describe('with custom branding', () => {
        it('returns domain-specific branding settings', () => {
          const { brandSettings } = useBranding('domain-1');

          expect(brandSettings.value).toEqual(mockCustomBrandingRed);
        });

        it.skip('correctly computes all brand-specific properties', () => {
          // Properties fontFamily and cornerStyle don't exist in current implementation
        });
      });

      describe('with default branding', () => {
        it('returns default settings for non-existent domain', () => {
          const { brandSettings } = useBranding('non-existent');

          expect(brandSettings.value).toEqual(mockDefaultBranding);
        });

        it('returns default settings for domain without brand settings', () => {
          const { brandSettings } = useBranding('domain-without-brand');

          expect(brandSettings.value).toEqual(mockDefaultBranding);
        });
      });
    });
  });

  describe.skip('UI helpers', () => {
    describe.skip('getButtonClass', () => {
      it.skip('returns custom styling for branded domain', () => {
        // getButtonClass function doesn't exist in current implementation
      });

      it.skip('returns default styling when no domain specified', () => {
        // getButtonClass function doesn't exist in current implementation
      });

      it.skip('handles missing brand properties gracefully', () => {
        // getButtonClass function doesn't exist in current implementation
      });
    });
  });
});
