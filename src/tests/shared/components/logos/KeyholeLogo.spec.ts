// src/tests/shared/components/logos/KeyholeLogo.spec.ts

import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import KeyholeLogo from '@/shared/components/logos/KeyholeLogo.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        homepage: {
          one_time_secret_literal: 'VaultShare',
        },
        COMMON: {
          tagline: 'Keep sensitive info out of chat logs & email',
        },
        branding: {
          keyhole_logo_icon: 'Keyhole secure sharing icon',
        },
      },
    },
  },
});

describe('KeyholeLogo', () => {
  const mountComponent = (props = {}) => {
    const pinia = createTestingPinia({
      initialState: {
        bootstrap: {
          brand_product_name: 'VaultShare',
        },
      },
    });

    return mount(KeyholeLogo, {
      props: {
        size: 64,
        href: '/',
        ...props,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  it('renders keyhole icon with correct size', () => {
    const wrapper = mountComponent({ size: 48 });
    const svg = wrapper.find('svg');

    expect(svg.exists()).toBe(true);
    expect(svg.attributes('width')).toBe('48');
    expect(svg.attributes('height')).toBe('48');
  });

  it('applies brand color classes to icon', () => {
    const wrapper = mountComponent();
    const svg = wrapper.find('svg');

    expect(svg.classes()).toContain('text-brand-500');
    expect(svg.classes()).toContain('dark:text-white');
  });

  it('shows site name when showSiteName is true', () => {
    const wrapper = mountComponent({
      showSiteName: true,
      siteName: 'VaultShare',
    });

    expect(wrapper.text()).toContain('VaultShare');
  });

  it('hides site name when showSiteName is false', () => {
    const wrapper = mountComponent({
      showSiteName: false,
      siteName: 'VaultShare',
    });

    expect(wrapper.text()).not.toContain('VaultShare');
  });

  it('renders with correct href', () => {
    const wrapper = mountComponent({ href: '/dashboard' });
    const link = wrapper.find('a');

    expect(link.attributes('href')).toBe('/dashboard');
  });

  it('has proper accessibility attributes', () => {
    const wrapper = mountComponent({
      ariaLabel: 'VaultShare Logo',
    });
    const svg = wrapper.find('svg');

    expect(svg.attributes('aria-label')).toBe('VaultShare Logo');
    expect(svg.attributes('role')).toBe('img');
  });

  it('defaults to 64px size when not specified', () => {
    const wrapper = mountComponent();
    const svg = wrapper.find('svg');

    expect(svg.attributes('width')).toBe('64');
    expect(svg.attributes('height')).toBe('64');
  });

  it('renders tagline when showSiteName is true', () => {
    const wrapper = mountComponent({
      showSiteName: true,
      siteName: 'VaultShare',
    });

    expect(wrapper.text()).toContain('Keep sensitive info out of chat logs & email');
  });
});
