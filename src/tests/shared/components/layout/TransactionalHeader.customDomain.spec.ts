// src/tests/shared/components/layout/TransactionalHeader.customDomain.spec.ts
//
// Tests documenting that TransactionalHeader has no domain-aware branching.
// It always renders MastHead directly, which means on custom domains it
// will show the default OTS logo when domain_logo is null.
//
// Contrast with BrandedHeader.vue which switches between BrandedMastHead
// (custom) and MastHead (canonical) based on productIdentity.isCustom.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import TransactionalHeader from '@/shared/components/layout/TransactionalHeader.vue';
import { nextTick } from 'vue';

// Mock MastHead to track rendering and capture props
const mastHeadProps = vi.fn();
vi.mock('@/shared/components/layout/MastHead.vue', () => ({
  default: {
    name: 'MastHead',
    template: '<div class="masthead" :data-display-masthead="displayMasthead" />',
    props: ['displayMasthead', 'displayNavigation', 'colonel', 'logo'],
    setup(props: Record<string, unknown>) {
      mastHeadProps(props);
    },
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: {} },
});

describe('TransactionalHeader — Custom Domain Leak Vector', () => {
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
    storeState: {
      domain_strategy?: string;
      domain_logo?: string | null;
    } = {}
  ) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
      initialState: {
        bootstrap: {
          authenticated: false,
          domain_strategy: storeState.domain_strategy ?? 'canonical',
          domain_logo: storeState.domain_logo ?? null,
          ui: {
            header: {
              navigation: { enabled: true },
              branding: {
                logo: { url: 'DefaultLogo.vue', alt: 'Onetime Secret' },
                site_name: 'Onetime Secret',
              },
            },
          },
          authentication: { enabled: true, signin: true, signup: true },
        },
      },
    });

    return mount(TransactionalHeader, {
      props: {
        displayMasthead: true,
        displayNavigation: true,
        ...props,
      },
      global: {
        plugins: [i18n, pinia],
      },
    });
  };

  it('always renders MastHead regardless of domain_strategy', async () => {
    // TransactionalHeader has no domain-aware branching — it always uses MastHead
    wrapper = mountComponent({}, {
      domain_strategy: 'custom',
      domain_logo: null,
    });

    await nextTick();
    expect(wrapper.find('.masthead').exists()).toBe(true);
    expect(mastHeadProps).toHaveBeenCalled();
  });

  it('renders MastHead on canonical domain (expected behavior)', async () => {
    wrapper = mountComponent({}, {
      domain_strategy: 'canonical',
      domain_logo: null,
    });

    await nextTick();
    expect(wrapper.find('.masthead').exists()).toBe(true);
  });

  it('renders MastHead on custom domain with logo (works but shows default OTS chrome)', async () => {
    // When domain_logo is set, MastHead renders the custom logo correctly.
    // But the surrounding TransactionalHeader still uses the OTS layout/style.
    wrapper = mountComponent({}, {
      domain_strategy: 'custom',
      domain_logo: 'https://cdn.example.com/acme-logo.png',
    });

    await nextTick();
    expect(wrapper.find('.masthead').exists()).toBe(true);
  });

  it('does not pass domain-aware props to MastHead', async () => {
    // TransactionalHeader passes layout props but NOT domain context.
    // MastHead has to derive domain awareness from bootstrap store directly.
    wrapper = mountComponent({
      displayMasthead: true,
      displayNavigation: false,
    }, {
      domain_strategy: 'custom',
    });

    await nextTick();
    // MastHead receives layout props, but nothing domain-specific
    const lastCall = mastHeadProps.mock.calls[0]?.[0];
    expect(lastCall).toBeDefined();
    expect(lastCall.displayNavigation).toBe(false);
    // No logo prop override — MastHead uses its own fallback chain
    expect(lastCall.logo).toBeUndefined();
  });

  it('hides MastHead when displayMasthead is false', async () => {
    wrapper = mountComponent({
      displayMasthead: false,
    }, {
      domain_strategy: 'custom',
    });

    await nextTick();
    // v-if="displayMasthead" prevents MastHead from rendering
    expect(wrapper.find('.masthead').exists()).toBe(false);
  });

  // This documents the leak: routes using TransactionalHeader on custom domains
  // include /incoming, /feedback, /help, /pricing — they all show the OTS logo
  // because TransactionalHeader → MastHead → DefaultLogo fallback chain
  // doesn't check domain_strategy.
  describe('Leak documentation: routes affected', () => {
    it('would show default OTS logo on /incoming for custom domain guests', async () => {
      // SecretLayout uses TransactionalHeader for unauthenticated users
      // On a custom domain with no logo, this shows the OTS default logo
      wrapper = mountComponent({}, {
        domain_strategy: 'custom',
        domain_logo: null,
      });

      await nextTick();
      // MastHead renders — it will show DefaultLogo via its internal fallback
      expect(wrapper.find('.masthead').exists()).toBe(true);
      // The only way to prevent this is either:
      // 1. Make TransactionalHeader domain-aware (like BrandedHeader)
      // 2. Make MastHead check domain_strategy and suppress default logo
      // 3. Use route beforeEnter guards to set displayMasthead=false
    });
  });
});
