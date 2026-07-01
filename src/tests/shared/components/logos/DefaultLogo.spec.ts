// src/tests/shared/components/logos/DefaultLogo.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestI18n } from '@tests/setup';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import DefaultLogo from '@/shared/components/logos/DefaultLogo.vue';

// Mock KeyholeIcon component (the neutral default mark; the maruhi 秘 mark is
// OTS-company-only and must not be the default — see DefaultLogo.vue).
vi.mock('@/shared/components/icons/KeyholeIcon.vue', () => ({
  default: {
    name: 'KeyholeIcon',
    template: '<svg class="logo-icon" :width="size" :height="size" :aria-label="ariaLabel" :title="title" />',
    props: ['size', 'ariaLabel', 'title', 'class'],
  },
}));

const i18n = createTestI18n();

describe('DefaultLogo', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (props: Record<string, unknown> = {}) => mount(DefaultLogo, {
      props: {
        isUserPresent: false,
        ...props,
      },
      global: {
        plugins: [i18n],
      },
    });

  describe('Text Size Tiers', () => {
    it('uses text-xs for size <= 32', () => {
      wrapper = mountComponent({ size: 32, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-xs');
    });

    it('uses text-xs for size 24 (edge case below 32)', () => {
      wrapper = mountComponent({ size: 24, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-xs');
    });

    it('uses text-sm for size 33-40', () => {
      wrapper = mountComponent({ size: 40, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-sm');
    });

    it('uses text-sm for size 36 (middle of 33-40 range)', () => {
      wrapper = mountComponent({ size: 36, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-sm');
    });

    it('uses text-base for size 41-48', () => {
      wrapper = mountComponent({ size: 48, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-base');
    });

    it('uses text-base for size 44 (middle of 41-48 range)', () => {
      wrapper = mountComponent({ size: 44, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-base');
    });

    it('uses text-lg for size 49-64', () => {
      wrapper = mountComponent({ size: 64, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-lg');
    });

    it('uses text-lg for size 56 (middle of 49-64 range)', () => {
      wrapper = mountComponent({ size: 56, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-lg');
    });

    it('uses text-xl for size > 64', () => {
      wrapper = mountComponent({ size: 80, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-xl');
    });

    it('uses text-xl for size 100 (well above 64)', () => {
      wrapper = mountComponent({ size: 100, showSiteName: true, siteName: 'Test' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.classes()).toContain('text-xl');
    });
  });

  describe('SVG Size', () => {
    it('passes size prop to icon component', () => {
      wrapper = mountComponent({ size: 48 });

      const icon = wrapper.find('.logo-icon');
      expect(icon.attributes('width')).toBe('48');
      expect(icon.attributes('height')).toBe('48');
    });

    it('defaults to 64 when no size prop provided', () => {
      wrapper = mountComponent({});

      const icon = wrapper.find('.logo-icon');
      expect(icon.attributes('width')).toBe('64');
    });

    it('defaults to 64 for invalid size (0)', () => {
      wrapper = mountComponent({ size: 0 });

      const icon = wrapper.find('.logo-icon');
      expect(icon.attributes('width')).toBe('64');
    });

    it('defaults to 64 for negative size', () => {
      wrapper = mountComponent({ size: -10 });

      const icon = wrapper.find('.logo-icon');
      expect(icon.attributes('width')).toBe('64');
    });
  });

  describe('Site Name Display', () => {
    it('shows site name when showSiteName is true', () => {
      wrapper = mountComponent({ showSiteName: true, siteName: 'My Brand' });

      const html = wrapper.html();
      expect(html).toContain('My Brand');
    });

    it('hides site name when showSiteName is false', () => {
      wrapper = mountComponent({ showSiteName: false, siteName: 'My Brand' });

      const textContainer = wrapper.find('.font-brand.font-bold');
      expect(textContainer.exists()).toBe(false);
    });

    it('hides site name when siteName is empty', () => {
      wrapper = mountComponent({ showSiteName: true, siteName: '' });

      // The v-if checks both showSiteName AND siteName
      const textContainer = wrapper.find('.flex.flex-col');
      expect(textContainer.exists()).toBe(false);
    });
  });

  describe('Tagline', () => {
    it('shows tagline from props when site name is visible', () => {
      wrapper = mountComponent({
        showSiteName: true,
        siteName: 'Test',
        tagLine: 'Custom Tagline',
      });

      const html = wrapper.html();
      expect(html).toContain('Custom Tagline');
    });

    it('shows default tagline from i18n when no tagLine prop', () => {
      wrapper = mountComponent({ showSiteName: true, siteName: 'Test' });

      const html = wrapper.html();
      expect(html).toContain('web.COMMON.tagline');
    });
  });

  describe('Colonel Area Overlay', () => {
    it('shows colonel-only overlay (i18n key) when isColonelArea is true', () => {
      wrapper = mountComponent({
        showSiteName: true,
        siteName: 'Test',
        isColonelArea: true,
      });

      const overlay = wrapper.find('.pointer-events-none');
      expect(overlay.exists()).toBe(true);
      // Test i18n returns the key for missing messages, so assert on the key
      // rather than the resolved "Colonels Only" string.
      expect(overlay.text()).toContain('web.layout.colonels_only_badge');
    });

    it('hides overlay when isColonelArea is false', () => {
      wrapper = mountComponent({
        showSiteName: true,
        siteName: 'Test',
        isColonelArea: false,
      });

      const overlay = wrapper.find('.pointer-events-none');
      expect(overlay.exists()).toBe(false);
    });
  });

  describe('Link Behavior', () => {
    it('uses default href "/" when not specified', () => {
      wrapper = mountComponent({});

      const link = wrapper.find('a');
      expect(link.attributes('href')).toBe('/');
    });

    it('uses custom href when provided', () => {
      wrapper = mountComponent({ href: '/dashboard' });

      const link = wrapper.find('a');
      expect(link.attributes('href')).toBe('/dashboard');
    });
  });

  describe('Accessibility', () => {
    it('sets aria-label from prop', () => {
      wrapper = mountComponent({ ariaLabel: 'Custom Label' });

      const container = wrapper.find('[aria-label="Custom Label"]');
      expect(container.exists()).toBe(true);
    });

    it('falls back to neutral brand aria-label when no prop', () => {
      wrapper = mountComponent({});

      // Falls back to NEUTRAL_BRAND_DEFAULTS.product_name ("Secure Links")
      const container = wrapper.find('[aria-label="Secure Links"]');
      expect(container.exists()).toBe(true);
    });

    it('passes aria-label to icon component', () => {
      wrapper = mountComponent({ ariaLabel: 'Custom Icon Label' });

      // The icon receives the computed ariaLabel
      const icon = wrapper.find('.logo-icon');
      expect(icon.attributes('aria-label')).toBe('Custom Icon Label');
    });

    it('does not duplicate aria-label on the non-interactive wrapper div', () => {
      // The accessible name comes from the icon inside the <a>; labelling the
      // outer layout <div> too would announce the name twice (#3553 review).
      wrapper = mountComponent({ ariaLabel: 'Custom Label' });

      expect(wrapper.attributes('aria-label')).toBeUndefined();
      // The label still reaches the icon, so the link is still named.
      expect(wrapper.find('.logo-icon').attributes('aria-label')).toBe('Custom Label');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Brand-aware aria-label via the shared resolveProductName helper (A1)
  //
  // The aria-label fallback resolves through the shared resolveProductName
  // helper (the single source of truth for the neutral product-name fallback),
  // so DefaultLogo stays neutral-safe and in lockstep with every other surface
  // while remaining lightweight — the app-wide fallback mark does not pull in
  // the identity store. (These rely on the global testing Pinia from
  // setup-stores.ts.)
  // ═══════════════════════════════════════════════════════════════════════════

  describe('productName fallback via resolveProductName', () => {
    it('uses the configured brand_product_name when no ariaLabel prop is given', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({ brand_product_name: 'Acme Vault' });

      wrapper = mountComponent({});

      expect(wrapper.find('[aria-label="Acme Vault"]').exists()).toBe(true);
    });

    it('never leaks OTS branding when unbranded — degrades to the neutral default', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({ brand_product_name: null });

      wrapper = mountComponent({});

      expect(wrapper.find('[aria-label="Onetime Secret"]').exists()).toBe(false);
      expect(
        wrapper.find(`[aria-label="${NEUTRAL_BRAND_DEFAULTS.product_name}"]`).exists()
      ).toBe(true);
    });

    it('an explicit ariaLabel prop still wins over the resolved fallback', () => {
      const bootstrap = useBootstrapStore();
      bootstrap.$patch({ brand_product_name: 'Acme Vault' });

      wrapper = mountComponent({ ariaLabel: 'Explicit Label' });

      expect(wrapper.find('[aria-label="Explicit Label"]').exists()).toBe(true);
    });
  });
});
