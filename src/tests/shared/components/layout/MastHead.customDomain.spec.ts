// src/tests/shared/components/layout/MastHead.customDomain.spec.ts
//
// Tests for MastHead logo/brand behavior on custom domains.
// Covers the interaction between domain_strategy, domain_logo,
// and how the component decides which logo to render.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import MastHead from '@/shared/components/layout/MastHead.vue';
import { nextTick } from 'vue';
import { useAuthStore } from '@/shared/stores/authStore';

// Mock DefaultLogo component
vi.mock('@/shared/components/logos/DefaultLogo.vue', () => ({
  default: {
    name: 'DefaultLogo',
    template: `<div class="default-logo" :data-size="size" :data-show-site-name="showSiteName">
      <span class="logo-icon" />
      <span v-if="showSiteName" class="site-name">{{ siteName }}</span>
    </div>`,
    props: ['url', 'alt', 'href', 'size', 'showSiteName', 'siteName', 'ariaLabel', 'isColonelArea', 'isUserPresent'],
  },
}));

// Mock UserMenu component
vi.mock('@/shared/components/navigation/UserMenu.vue', () => ({
  default: {
    name: 'UserMenu',
    template: '<div class="user-menu" :data-email="email" />',
    props: ['cust', 'email', 'colonel', 'awaitingMfa'],
  },
}));

// Mock router
vi.mock('vue-router', () => ({
  RouterLink: {
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
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
          signup_individual_and_business_plans: 'Sign up',
          log_in_to_onetime_secret: 'Log in',
        },
        layout: {
          main_navigation: 'Main Navigation',
        },
        COMMON: {
          header_create_account: 'Create Account',
          header_sign_in: 'Sign In',
        },
      },
    },
  },
});

describe('MastHead — Custom Domain Logo Behavior', () => {
  let wrapper: VueWrapper;

  const mockCustomer = {
    custid: '123',
    email: 'test@example.com',
    extid: 'ext_123',
    objid: 'obj_123',
    role: 'customer',
  };

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
      authenticated?: boolean;
      awaiting_mfa?: boolean;
      email?: string | null;
      cust?: typeof mockCustomer | null;
      domain_logo?: string | null;
      domain_strategy?: string;
      display_domain?: string;
      domain_id?: string;
    } = {}
  ) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
      initialState: {
        bootstrap: {
          authenticated: storeState.authenticated ?? false,
          awaiting_mfa: storeState.awaiting_mfa ?? false,
          email: storeState.email ?? null,
          cust: storeState.cust ?? null,
          domain_logo: storeState.domain_logo ?? null,
          domain_strategy: storeState.domain_strategy ?? 'canonical',
          display_domain: storeState.display_domain ?? 'onetimesecret.com',
          domain_id: storeState.domain_id ?? '',
          ui: {
            header: {
              navigation: { enabled: true },
              branding: {
                logo: { url: 'DefaultLogo.vue', alt: 'Onetime Secret' },
                site_name: 'Onetime Secret',
              },
            },
          },
          authentication: {
            enabled: true,
            signin: true,
            signup: true,
          },
        },
      },
    });

    const authStore = useAuthStore(pinia);
    const hasAuthenticatedCustomer = storeState.authenticated && storeState.cust;
    const hasMfaPendingEmail = storeState.awaiting_mfa && storeState.email;
    (authStore as unknown as { isUserPresent: boolean }).isUserPresent =
      !!(hasAuthenticatedCustomer || hasMfaPendingEmail);

    return mount(MastHead, {
      props: {
        displayMasthead: true,
        displayNavigation: true,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // CANONICAL DOMAIN — Default OTS Logo
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Canonical domain (domain_strategy="canonical")', () => {
    it('renders DefaultLogo component when no custom domain logo', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'canonical',
        domain_logo: null,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
    });

    it('shows site name on canonical domain', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'canonical',
        domain_logo: null,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-show-site-name')).toBe('true');
    });

    it('uses 64px logo for unauthenticated users on canonical domain', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'canonical',
        domain_logo: null,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('64');
    });

    it('uses 40px logo for authenticated users on canonical domain', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
        domain_strategy: 'canonical',
        domain_logo: null,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('40');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOM DOMAIN WITH LOGO — Custom brand logo
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Custom domain with logo (domain_strategy="custom", domain_logo set)', () => {
    const customLogoUrl = 'https://cdn.example.com/logos/acme-logo.png';

    it('renders img element instead of DefaultLogo when domain_logo is set', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: customLogoUrl,
        display_domain: 'secrets.acme.com',
        domain_id: 'cd_acme',
      });

      await nextTick();
      // Should NOT render DefaultLogo component
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(false);

      // Should render img element with custom logo
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe(customLogoUrl);
    });

    it('uses 80px size for custom domain logo', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: customLogoUrl,
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('height')).toBe('80');
      expect(img.attributes('width')).toBe('80');
    });

    it('applies size-20 class to custom domain logo', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: customLogoUrl,
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.classes()).toContain('size-20');
    });

    it('hides site name when custom domain logo is present', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: customLogoUrl,
      });

      await nextTick();
      // Site name should not appear next to custom domain logo by default
      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('uses 80px size regardless of auth state for custom domain', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
        domain_strategy: 'custom',
        domain_logo: customLogoUrl,
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('height')).toBe('80');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOM DOMAIN WITHOUT LOGO — The bug scenario
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Custom domain without logo (domain_strategy="custom", domain_logo=null)', () => {
    it('falls back to DefaultLogo when custom domain has no uploaded logo', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: null,
        display_domain: 'secrets.acme.com',
        domain_id: 'cd_acme',
      });

      await nextTick();
      // When domain_logo is null, MastHead falls back to the configured logo URL
      // which defaults to 'DefaultLogo.vue' — this renders the OTS logo
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(true);
    });

    it('shows OTS site name when custom domain has no logo', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: null,
        display_domain: 'secrets.acme.com',
      });

      await nextTick();
      // Without domain_logo, the site name logic does NOT suppress the name
      // This means the OTS site name "Onetime Secret" appears on a custom domain
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      expect(logo.attributes('data-show-site-name')).toBe('true');
    });

    it('uses standard sizing (not 80px) when no custom logo is set', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: null,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      // Should use 64px (unauthenticated default), NOT 80px (custom domain logo size)
      expect(logo.attributes('data-size')).toBe('64');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGO CONFIGURATION PRIORITY
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Logo configuration priority: props > domain_logo > config > default', () => {
    it('props override domain_logo when both are provided', async () => {
      wrapper = mountComponent({
        logo: {
          url: '/custom-override.png',
          alt: 'Override Logo',
          size: 48,
          isUserPresent: false,
        },
      }, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/domain-logo.png',
      });

      await nextTick();
      // The img should use the prop override URL, not the domain_logo
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('/custom-override.png');
      expect(img.attributes('height')).toBe('48');
    });

    it('domain_logo takes priority over header config logo URL', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/domain-logo.png',
      });

      await nextTick();
      // Should use domain_logo, not the header config default
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('https://cdn.example.com/domain-logo.png');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCESSIBILITY ON CUSTOM DOMAINS
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Accessibility on custom domains', () => {
    it('custom domain logo has alt text', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/logo.png',
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('alt')).toBeTruthy();
    });

    it('custom domain logo link has aria-label', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/logo.png',
      });

      await nextTick();
      const logoLink = wrapper.find('a[aria-label]');
      expect(logoLink.exists()).toBe(true);
    });

    it('navigation has proper aria-label on custom domains', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
        domain_strategy: 'custom',
        domain_logo: 'https://cdn.example.com/logo.png',
      });

      await nextTick();
      const nav = wrapper.find('nav[role="navigation"]');
      expect(nav.attributes('aria-label')).toBe('Main Navigation');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BUG DOCUMENTATION: Default logo leaks on custom domains
  //
  // MastHead's logo logic is driven by `domain_logo` (URL or null), not
  // `domain_strategy`. When domain_strategy='custom' but domain_logo is null
  // (e.g., customer hasn't uploaded a logo), MastHead renders the OTS default
  // logo with "Onetime Secret" branding — which is wrong for custom domains.
  //
  // Leak routes: /incoming, /feedback, /help, /pricing — these use
  // TransactionalHeader → MastHead directly, with no domain-aware switching.
  //
  // Non-leaking routes: homepage (BrandedHeader switches), reveal (hides
  // masthead entirely), receipt (beforeEnter guard patches props).
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Bug: MastHead ignores domain_strategy when domain_logo is null', () => {
    it('shows OTS default logo on custom domain when no logo uploaded (current behavior)', async () => {
      // This documents the bug: a customer on secrets.acme.com sees the
      // Onetime Secret logo because MastHead only checks domain_logo, not domain_strategy
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: null,
        display_domain: 'secrets.acme.com',
        domain_id: 'cd_acme',
      });

      await nextTick();

      // BUG: DefaultLogo renders even though we're on a custom domain
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(true);

      // BUG: "Onetime Secret" site name shows on another company's domain
      expect(defaultLogo.attributes('data-show-site-name')).toBe('true');
    });

    it('does not suppress auth navigation on custom domain (correct: auth nav should remain)', async () => {
      // Even on custom domains, sign in/sign up links should still appear
      // if authentication is enabled — this is NOT a bug
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_strategy: 'custom',
        domain_logo: null,
      });

      await nextTick();
      const html = wrapper.html();
      expect(html).toContain('Sign In');
      expect(html).toContain('Create Account');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPECTED BEHAVIOR AFTER FIX (these should pass once the fix lands)
  // ═══════════════════════════════════════════════════════════════════════════

  describe.todo('Expected: MastHead should be domain_strategy-aware', () => {
    // Once fixed, MastHead should check domain_strategy='custom' and:
    // 1. If domain_logo is set → show custom logo (already works)
    // 2. If domain_logo is null → hide logo entirely or show a neutral placeholder
    //    (NOT the OTS default logo with "Onetime Secret" branding)
    //
    // Test stubs for when the fix is implemented:

    // it('hides DefaultLogo when domain_strategy=custom and no domain_logo', ...)
    // it('does not show "Onetime Secret" site name on custom domain', ...)
    // it('shows neutral placeholder when custom domain has no logo', ...)
  });
});
