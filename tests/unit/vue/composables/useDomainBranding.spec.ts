// tests/unit/vue/composables/useDomainBranding.spec.ts
import {
    mockCustomBranding,
    mockDefaultBranding,
    mockDomains,
} from '@/../tests/unit/vue/fixtures/domainBranding';
import { useDomainBranding } from '@/composables/useDomainBranding';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mockDomainsStore = vi.fn(() => ({
  defaultBranding: mockDefaultBranding,
  getDomainById: (id: string) => mockDomains[id],
}));

vi.mock('@/stores/domainsStore', () => ({
  useDomainsStore: () => mockDomainsStore(),
}));

describe('useDomainBranding', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  describe('brand settings resolution', () => {
    describe('when no domain ID is provided', () => {
      it('returns default branding settings', () => {
        const { brandSettings, hasCustomBranding } = useDomainBranding();

        expect(brandSettings.value).toEqual(mockDefaultBranding);
        expect(hasCustomBranding.value).toBe(false);
      });
    });

    describe('when domain ID is provided', () => {
      describe('with custom branding', () => {
        it('returns domain-specific branding settings', () => {
          const { brandSettings, hasCustomBranding } = useDomainBranding('domain-1');

          expect(brandSettings.value).toEqual(mockCustomBranding);
          expect(hasCustomBranding.value).toBe(true);
        });

        it('correctly computes all brand-specific properties', () => {
          const { primaryColor, fontFamily, cornerStyle } = useDomainBranding('domain-1');

          expect(primaryColor.value).toBe(mockCustomBranding.primary_color);
          expect(fontFamily.value).toBe(mockCustomBranding.font_family);
          expect(cornerStyle.value).toBe(mockCustomBranding.corner_style);
        });
      });

      describe('with default branding', () => {
        it('returns default settings for non-existent domain', () => {
          const { brandSettings, hasCustomBranding } = useDomainBranding('non-existent');

          expect(brandSettings.value).toEqual(mockDefaultBranding);
          expect(hasCustomBranding.value).toBe(false);
        });

        it('returns default settings for domain without brand settings', () => {
          const { brandSettings } = useDomainBranding('domain-without-brand');

          expect(brandSettings.value).toEqual(mockDefaultBranding);
        });
      });
    });
  });

  describe('UI helpers', () => {
    describe('getButtonClass', () => {
      it('returns custom styling for branded domain', () => {
        const { getButtonClass } = useDomainBranding('domain-1');

        expect(getButtonClass.value).toEqual({
          'text-light': false,
          'corner-sharp': true,
        });
      });

      it('returns default styling when no domain specified', () => {
        const { getButtonClass } = useDomainBranding();

        expect(getButtonClass.value).toEqual({
          'text-light': true,
          'corner-rounded': true,
        });
      });

      it('handles missing brand properties gracefully', () => {
        mockDomainsStore.mockImplementationOnce(() => ({
          defaultBranding: {},
          getDomainById: () => ({ brand: {} }),
        }));

        const { getButtonClass } = useDomainBranding('domain-1');

        expect(getButtonClass.value).toBeDefined();
      });
    });
  });
});
