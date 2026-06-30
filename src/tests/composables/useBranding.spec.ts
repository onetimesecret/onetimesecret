// src/tests/composables/useBranding.spec.ts

import {
  mockCustomBrandingRed,
  mockDefaultBranding,
} from '@/tests/fixtures/domainBranding.fixture';
import { useBranding } from '@/shared/composables/useBranding';
import { DEFAULT_BUTTON_TEXT_LIGHT } from '@/shared/constants/brand';
import { createPinia, setActivePinia } from 'pinia';
import { nextTick } from 'vue';
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

vi.mock('@/shared/stores/brandStore', () => ({
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

// The composable calls useI18n() directly from vue-i18n, which requires
// an active Vue component setup context. Mock it to avoid the
// "Must be called at the top of a setup function" error.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/shared/composables/useAsyncHandler', () => ({
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

  describe('button_text_light auto-contrast watcher', () => {
    it('recomputes on color change and resets to the default when the color is cleared', async () => {
      const { brandSettings, isInitialized } = useBranding('domain-1');
      // primaryColor only tracks brand settings once initialized.
      isInitialized.value = true;
      await nextTick();

      // A light primary color implies dark button text.
      brandSettings.value = { ...brandSettings.value, primary_color: '#ffffff' };
      await nextTick();
      expect(brandSettings.value.button_text_light).toBe(false);

      // Clearing the color must reset to the default rather than leaving the
      // stale "dark text" decision from the previous color.
      brandSettings.value = { ...brandSettings.value, primary_color: '' };
      await nextTick();
      expect(brandSettings.value.button_text_light).toBe(DEFAULT_BUTTON_TEXT_LIGHT);
    });

    it('handles a partial hex value mid-keystroke without throwing', async () => {
      const { brandSettings, isInitialized } = useBranding('domain-1');
      isInitialized.value = true;
      await nextTick();

      // The watcher fires on every keystroke; a half-typed "#f" must resolve to
      // the graceful default (false) rather than throwing on NaN luminance.
      brandSettings.value = { ...brandSettings.value, primary_color: '#f' };
      await nextTick();
      expect(brandSettings.value.button_text_light).toBe(false);
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
