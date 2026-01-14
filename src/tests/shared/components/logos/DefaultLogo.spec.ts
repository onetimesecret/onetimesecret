// src/tests/shared/components/logos/DefaultLogo.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import DefaultLogo from '@/shared/components/logos/DefaultLogo.vue';

// Mock MonotoneJapaneseSecretButton icon component
vi.mock('@/shared/components/icons/MonotoneJapaneseSecretButtonIcon.vue', () => ({
  default: {
    name: 'MonotoneJapaneseSecretButton',
    template: '<svg class="logo-icon" :width="size" :height="size" :aria-label="ariaLabel" :title="title" />',
    props: ['size', 'ariaLabel', 'title', 'class'],
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        homepage: {
          one_time_secret_literal: 'Onetime Secret',
        },
        branding: {
          default_logo_icon: 'Onetime Secret Logo',
        },
        COMMON: {
          tagline: 'Keep passwords out of your email & chat logs',
        },
      },
    },
  },
});

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

  const mountComponent = (props: Record<string, unknown> = {}) => {
    return mount(DefaultLogo, {
      props: {
        isUserPresent: false,
        ...props,
      },
      global: {
        plugins: [i18n],
      },
    });
  };

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
      expect(html).toContain('Keep passwords out of your email');
    });
  });

  describe('Colonel Area Overlay', () => {
    it('shows "Colonels Only" overlay when isColonelArea is true', () => {
      wrapper = mountComponent({
        showSiteName: true,
        siteName: 'Test',
        isColonelArea: true,
      });

      const overlay = wrapper.find('.pointer-events-none');
      expect(overlay.exists()).toBe(true);
      expect(overlay.text()).toContain('Colonels Only');
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

    it('falls back to i18n aria-label when no prop', () => {
      wrapper = mountComponent({});

      const container = wrapper.find('[aria-label="Onetime Secret"]');
      expect(container.exists()).toBe(true);
    });

    it('passes aria-label to icon component', () => {
      wrapper = mountComponent({ ariaLabel: 'Custom Icon Label' });

      // The icon receives the computed ariaLabel
      const icon = wrapper.find('.logo-icon');
      expect(icon.attributes('aria-label')).toBe('Custom Icon Label');
    });
  });
});
