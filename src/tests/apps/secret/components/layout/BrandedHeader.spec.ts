// src/tests/apps/secret/components/layout/BrandedHeader.spec.ts
//
// Tests for BrandedHeader — the component that switches between
// BrandedMastHead (custom domains) and MastHead (canonical domain)
// based on productIdentity.isCustom.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import BrandedHeader from '@/apps/secret/components/layout/BrandedHeader.vue';
import { nextTick } from 'vue';

// Track which component renders
const brandedMastHeadSpy = vi.fn();
const mastHeadSpy = vi.fn();

// Mock BrandedMastHead
vi.mock('@/apps/secret/components/layout/BrandedMastHead.vue', () => ({
  default: {
    name: 'BrandedMastHead',
    template: '<div class="branded-masthead" :data-headertext="headertext" :data-subtext="subtext" />',
    props: ['headertext', 'subtext', 'displayMasthead', 'displayNavigation'],
    setup() {
      brandedMastHeadSpy();
    },
  },
}));

// Mock MastHead
vi.mock('@/shared/components/layout/MastHead.vue', () => ({
  default: {
    name: 'MastHead',
    template: '<div class="standard-masthead" />',
    props: ['displayMasthead', 'displayNavigation', 'colonel'],
    setup() {
      mastHeadSpy();
    },
  },
}));

// Mock vue-router
vi.mock('vue-router', () => ({
  RouterLink: {
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
  useRoute: vi.fn(() => ({ path: '/', query: {}, params: {} })),
  useRouter: vi.fn(() => ({ push: vi.fn() })),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        homepage: {
          create_a_secure_link: 'Create a Secure Link',
          secure_links: 'Secure Links',
          send_sensitive_information_that_can_only_be_viewed_once:
            'Send sensitive information that can only be viewed once',
          a_trusted_way_to_share_sensitive_information_etc:
            'A trusted way to share sensitive information',
          one_time_secret_literal: 'Onetime Secret',
        },
        layout: {
          brand_logo: 'Brand Logo',
        },
        shared: {
          pre_reveal_default: 'Click to reveal',
          post_reveal_default: 'Secret has been revealed',
        },
        COMMON: {
          tagline: 'Keep passwords out of your email & chat logs',
        },
      },
    },
  },
});

describe('BrandedHeader', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (
    props: Record<string, unknown> = {},
    storeOverrides: {
      domain_strategy?: string;
      domain_logo?: string | null;
      domain_branding?: Record<string, unknown>;
    } = {}
  ) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
      initialState: {
        bootstrap: {
          domain_strategy: storeOverrides.domain_strategy ?? 'canonical',
          domain_logo: storeOverrides.domain_logo ?? null,
          domains_enabled: storeOverrides.domain_strategy === 'custom',
          display_domain: storeOverrides.domain_strategy === 'custom'
            ? 'secrets.acme.com'
            : 'onetimesecret.com',
          site_host: 'onetimesecret.com',
          canonical_domain: 'onetimesecret.com',
          domain_id: storeOverrides.domain_strategy === 'custom' ? 'cd_acme' : '',
          domain_branding: storeOverrides.domain_branding ?? {
            primary_color: '#36454F',
            corner_style: 'rounded',
            font_family: 'sans',
            button_text_light: true,
            allow_public_homepage: false,
          },
          ui: {
            header: {
              navigation: { enabled: true },
              branding: {
                logo: { url: 'DefaultLogo.vue', alt: 'Onetime Secret' },
                site_name: 'Onetime Secret',
              },
            },
          },
        },
      },
    });

    return mount(BrandedHeader, {
      props: {
        displayMasthead: true,
        displayNavigation: false,
        ...props,
      },
      global: {
        plugins: [i18n, pinia],
        stubs: {
          RouterLink: {
            template: '<a :href="to"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });
  };

  describe('Component switching based on domain strategy', () => {
    it('renders MastHead on canonical domain', async () => {
      wrapper = mountComponent({}, {
        domain_strategy: 'canonical',
        domain_logo: null,
      });

      await nextTick();
      expect(wrapper.find('.standard-masthead').exists()).toBe(true);
      expect(wrapper.find('.branded-masthead').exists()).toBe(false);
      expect(mastHeadSpy).toHaveBeenCalled();
      expect(brandedMastHeadSpy).not.toHaveBeenCalled();
    });

    it('renders BrandedMastHead on custom domain', async () => {
      wrapper = mountComponent({}, {
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/logo.png',
      });

      await nextTick();
      expect(wrapper.find('.branded-masthead').exists()).toBe(true);
      expect(wrapper.find('.standard-masthead').exists()).toBe(false);
      expect(brandedMastHeadSpy).toHaveBeenCalled();
      expect(mastHeadSpy).not.toHaveBeenCalled();
    });

    it('renders BrandedMastHead on custom domain even without logo', async () => {
      // Key scenario: custom domain with no uploaded logo
      // BrandedHeader should still use BrandedMastHead (NOT MastHead)
      // because the switching is based on domain_strategy, not domain_logo
      wrapper = mountComponent({}, {
        domain_strategy: 'custom',
        domain_logo: null,
      });

      await nextTick();
      expect(wrapper.find('.branded-masthead').exists()).toBe(true);
      expect(wrapper.find('.standard-masthead').exists()).toBe(false);
    });
  });

  describe('Header text on custom domains', () => {
    it('shows "Secure Links" when allow_public_homepage is false', async () => {
      wrapper = mountComponent({}, {
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/logo.png',
        domain_branding: {
          primary_color: '#ff4400',
          corner_style: 'square',
          font_family: 'sans',
          button_text_light: false,
          allow_public_homepage: false,
        },
      });

      await nextTick();
      const branded = wrapper.find('.branded-masthead');
      expect(branded.attributes('data-headertext')).toBe('Secure Links');
      expect(branded.attributes('data-subtext')).toBe(
        'A trusted way to share sensitive information'
      );
    });

    it('shows "Create a Secure Link" when allow_public_homepage is true', async () => {
      wrapper = mountComponent({}, {
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/logo.png',
        domain_branding: {
          primary_color: '#ff4400',
          corner_style: 'square',
          font_family: 'sans',
          button_text_light: false,
          allow_public_homepage: true,
        },
      });

      await nextTick();
      const branded = wrapper.find('.branded-masthead');
      expect(branded.attributes('data-headertext')).toBe('Create a Secure Link');
    });
  });

  describe('Masthead visibility', () => {
    it('hides header content when displayMasthead is false', async () => {
      wrapper = mountComponent({
        displayMasthead: false,
      }, {
        domain_strategy: 'canonical',
      });

      await nextTick();
      // The outer header exists but inner content is hidden via v-if
      expect(wrapper.find('.standard-masthead').exists()).toBe(false);
      expect(wrapper.find('.branded-masthead').exists()).toBe(false);
    });
  });
});
