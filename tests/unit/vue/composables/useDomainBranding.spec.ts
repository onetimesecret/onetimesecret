// tests/unit/vue/composables/useDomainBranding.spec.ts
import {
  mockCustomBranding,
  mockDefaultBranding,
  mockDomains,
} from '@/../tests/unit/vue/fixtures/domainBranding';
import { useDomainBranding } from '@/composables/useDomainBranding';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/stores/domainsStore', () => ({
  useDomainsStore: vi.fn(() => ({
    defaultBranding: mockDefaultBranding,
    getDomainById: (id: string) => mockDomains[id],
  })),
}));

describe('useDomainBranding', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  describe('without domain ID', () => {
    it('returns default branding settings', () => {
      const { brandSettings, hasCustomBranding } = useDomainBranding();

      expect(brandSettings.value).toEqual(mockDefaultBranding);
      expect(hasCustomBranding.value).toBe(false);
    });
  });

  describe('with domain ID', () => {
    it('returns custom branding for domain with custom settings', () => {
      const { brandSettings, primaryColor, fontFamily, cornerStyle, hasCustomBranding } =
        useDomainBranding('domain-1');

      expect(brandSettings.value).toEqual(mockCustomBranding);
      expect(primaryColor.value).toBe(mockCustomBranding.primary_color);
      expect(fontFamily.value).toBe(mockCustomBranding.font_family);
      expect(cornerStyle.value).toBe(mockCustomBranding.corner_style);
      expect(hasCustomBranding.value).toBe(true);
    });

    it('returns default branding for domain without custom settings', () => {
      const { brandSettings, hasCustomBranding } = useDomainBranding('non-existent');

      expect(brandSettings.value).toEqual(mockDefaultBranding);
      expect(hasCustomBranding.value).toBe(false);
    });
  });

  describe('UI helpers', () => {
    it('generates correct button classes based on branding', () => {
      const { getButtonClass } = useDomainBranding('domain-1');

      expect(getButtonClass.value).toEqual({
        'text-light': false,
        'corner-sharp': true,
      });
    });

    it('generates default button classes when no domain specified', () => {
      const { getButtonClass } = useDomainBranding();

      expect(getButtonClass.value).toEqual({
        'text-light': true,
        'corner-rounded': true,
      });
    });
  });
});
