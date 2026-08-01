// src/tests/shared/components/logos/BrandMark.spec.ts
//
// BrandMark — the shared light/dark logo pair with fallback-slot behavior.
// Guards the contract consumed by MastHead and the disabled-homepage variants:
//   - light img always renders when logoUri is usable
//   - dark img renders ONLY when logoDarkUri is set (data-testid="logo-dark",
//     `hidden dark:block`), with the light img gaining `dark:hidden`
//   - the fallback slot renders when logoUri is null/empty AND after @error,
//     and NEVER co-renders with a logo
//   - the internal error flag resets when logoUri changes

import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import BrandMark from '@/shared/components/logos/BrandMark.vue';

const mountMark = (props: Record<string, unknown> = {}, slots: Record<string, string> = {}) =>
  mount(BrandMark, {
    props: {
      logoUri: '/imagine/cd123/logo.png',
      alt: 'Acme logo',
      ...props,
    },
    slots,
  });

const fallbackSlot = { fallback: '<div data-testid="fallback-mark" />' };

describe('BrandMark', () => {
  describe('light img', () => {
    it('renders the light img with src and alt', () => {
      const wrapper = mountMark();

      const imgs = wrapper.findAll('img');
      expect(imgs).toHaveLength(1);
      expect(imgs[0].attributes('src')).toBe('/imagine/cd123/logo.png');
      expect(imgs[0].attributes('alt')).toBe('Acme logo');
    });

    it('does not apply dark:hidden to the light img when no dark variant is set', () => {
      const wrapper = mountMark();

      expect(wrapper.find('img').classes()).not.toContain('dark:hidden');
    });
  });

  describe('dark img', () => {
    it('does not render the dark img when logoDarkUri is null', () => {
      const wrapper = mountMark({ logoDarkUri: null });

      expect(wrapper.find('[data-testid="logo-dark"]').exists()).toBe(false);
    });

    it('renders the dark img with hidden dark:block classes when logoDarkUri is set', () => {
      const wrapper = mountMark({ logoDarkUri: '/imagine/cd123/logo-dark.png' });

      const dark = wrapper.find('[data-testid="logo-dark"]');
      expect(dark.exists()).toBe(true);
      expect(dark.attributes('src')).toBe('/imagine/cd123/logo-dark.png');
      expect(dark.classes()).toContain('hidden');
      expect(dark.classes()).toContain('dark:block');
    });

    it('hides the light img in dark mode (dark:hidden) when a dark variant exists', () => {
      const wrapper = mountMark({ logoDarkUri: '/imagine/cd123/logo-dark.png' });

      const light = wrapper.findAll('img')[0];
      expect(light.classes()).toContain('dark:hidden');
    });

    it('applies the same alt to both imgs', () => {
      const wrapper = mountMark({ logoDarkUri: '/imagine/cd123/logo-dark.png' });

      const imgs = wrapper.findAll('img');
      expect(imgs).toHaveLength(2);
      expect(imgs[0].attributes('alt')).toBe('Acme logo');
      expect(imgs[1].attributes('alt')).toBe('Acme logo');
    });

    it('applies imgClass to both imgs so the pair matches', () => {
      const wrapper = mountMark({
        logoDarkUri: '/imagine/cd123/logo-dark.png',
        imgClass: 'h-12 w-auto',
      });

      for (const img of wrapper.findAll('img')) {
        expect(img.classes()).toContain('h-12');
        expect(img.classes()).toContain('w-auto');
      }
    });
  });

  describe('fallback slot', () => {
    it('renders the fallback slot when logoUri is null', () => {
      const wrapper = mountMark({ logoUri: null }, fallbackSlot);

      expect(wrapper.find('[data-testid="fallback-mark"]').exists()).toBe(true);
      expect(wrapper.find('img').exists()).toBe(false);
    });

    it('renders the fallback slot when logoUri is an empty string', () => {
      const wrapper = mountMark({ logoUri: '' }, fallbackSlot);

      expect(wrapper.find('[data-testid="fallback-mark"]').exists()).toBe(true);
      expect(wrapper.find('img').exists()).toBe(false);
    });

    it('does not render the fallback slot alongside a usable logo', () => {
      const wrapper = mountMark({}, fallbackSlot);

      expect(wrapper.find('img').exists()).toBe(true);
      expect(wrapper.find('[data-testid="fallback-mark"]').exists()).toBe(false);
    });

    it('renders the fallback slot after the img fires @error', async () => {
      const wrapper = mountMark({}, fallbackSlot);

      await wrapper.find('img').trigger('error');

      expect(wrapper.find('img').exists()).toBe(false);
      expect(wrapper.find('[data-testid="fallback-mark"]').exists()).toBe(true);
    });

    it('resets the error state when logoUri changes, giving the new URL a chance', async () => {
      const wrapper = mountMark({}, fallbackSlot);

      await wrapper.find('img').trigger('error');
      expect(wrapper.find('[data-testid="fallback-mark"]').exists()).toBe(true);

      await wrapper.setProps({ logoUri: '/imagine/cd123/logo-v2.png' });

      const img = wrapper.find('img');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('/imagine/cd123/logo-v2.png');
      expect(wrapper.find('[data-testid="fallback-mark"]').exists()).toBe(false);
    });
  });
});
