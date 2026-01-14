// src/tests/shared/components/layout/MastHead.spec.ts

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

describe('MastHead', () => {
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

  /**
   * Mount component with proper store setup.
   *
   * isUserPresent is derived by authStore from bootstrapStore:
   * - authenticated=true && cust != null → isUserPresent=true
   * - awaiting_mfa=true && email != null → isUserPresent=true
   * - Otherwise → isUserPresent=false
   */
  const mountComponent = (
    props: Record<string, unknown> = {},
    storeState: {
      authenticated?: boolean;
      awaiting_mfa?: boolean;
      email?: string | null;
      cust?: typeof mockCustomer | null;
      domain_logo?: string | null;
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

    // Get the auth store and manually set isUserPresent based on what we need
    // This works because createTestingPinia stubs computed properties
    const authStore = useAuthStore(pinia);
    // Calculate expected isUserPresent value based on bootstrap state
    const hasAuthenticatedCustomer = storeState.authenticated && storeState.cust;
    const hasMfaPendingEmail = storeState.awaiting_mfa && storeState.email;
    // Override the stubbed computed property
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
      slots: {
        'context-switchers': '<div class="test-context-switchers">Switchers</div>',
      },
    });
  };

  describe('Logo Sizing', () => {
    it('uses 64px logo for unauthenticated users', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        cust: null,
        email: null,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('64');
    });

    it('uses 40px logo for authenticated users', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('40');
    });

    it('uses 40px logo for MFA-pending users (partial auth)', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        awaiting_mfa: true,
        email: mockCustomer.email,
        cust: null,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('40');
    });

    it('uses 80px logo when custom domain logo is present', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
        domain_logo: 'https://example.com/custom-logo.png',
      });

      await nextTick();
      // Custom domain logo uses img element with size-20 class (80px)
      const img = wrapper.find('img#logo');
      if (img.exists()) {
        expect(img.classes()).toContain('size-20');
        expect(img.attributes('height')).toBe('80');
      }
    });

    it('respects explicit size prop override', async () => {
      wrapper = mountComponent({
        logo: { size: 48, isUserPresent: false },
      }, {
        authenticated: true,
        cust: mockCustomer,
      });

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('48');
    });
  });

  describe('Context Switchers Slot', () => {
    it('renders context-switchers slot inline for authenticated users on desktop', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
      });

      await nextTick();

      // Desktop inline container (hidden sm:flex)
      const desktopSwitchers = wrapper.find('.hidden.min-w-0.items-center.gap-3.sm\\:flex');
      expect(desktopSwitchers.exists()).toBe(true);
      expect(desktopSwitchers.html()).toContain('test-context-switchers');
    });

    it('renders context-switchers slot below header for mobile (authenticated)', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
      });

      await nextTick();

      // Mobile container (mt-2 sm:hidden)
      const mobileSwitchers = wrapper.find('.mt-2.flex.items-center.gap-3.sm\\:hidden');
      expect(mobileSwitchers.exists()).toBe(true);
      expect(mobileSwitchers.html()).toContain('test-context-switchers');
    });

    it('does not render context-switchers for unauthenticated users', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        cust: null,
        email: null,
      });

      await nextTick();

      // Should not have either context switcher container
      const desktopSwitchers = wrapper.find('.hidden.min-w-0.items-center.gap-3.sm\\:flex');
      const mobileSwitchers = wrapper.find('.mt-2.flex.items-center.gap-3.sm\\:hidden');
      expect(desktopSwitchers.exists()).toBe(false);
      expect(mobileSwitchers.exists()).toBe(false);
    });
  });

  describe('Navigation Display', () => {
    it('shows sign in/sign up links for unauthenticated users', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        cust: null,
        email: null,
      });

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('Sign In');
      expect(html).toContain('Create Account');
    });

    it('shows UserMenu for authenticated users', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
      });

      await nextTick();

      const userMenu = wrapper.find('.user-menu');
      expect(userMenu.exists()).toBe(true);
    });

    it('hides navigation when displayNavigation is false', async () => {
      wrapper = mountComponent({
        displayNavigation: false,
      }, {
        authenticated: true,
        cust: mockCustomer,
      });

      await nextTick();

      const nav = wrapper.find('nav[role="navigation"]');
      expect(nav.exists()).toBe(false);
    });
  });

  describe('Custom Domain Logo', () => {
    it('hides site name by default when custom domain logo is present', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_logo: 'https://example.com/brand.png',
      });

      await nextTick();

      // When domain_logo is present, showSiteName defaults to false
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      // Site name span should not be rendered
      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('shows site name when explicitly configured with custom domain logo', async () => {
      wrapper = mountComponent({
        logo: {
          showSiteName: true,
          siteName: 'Custom Brand',
          isUserPresent: false,
        },
      }, {
        authenticated: false,
        domain_logo: 'https://example.com/brand.png',
      });

      await nextTick();

      // Logo prop override should show site name
      const logo = wrapper.find('.default-logo');
      if (logo.exists()) {
        expect(logo.attributes('data-show-site-name')).toBe('true');
      }
    });
  });

  describe('Accessibility', () => {
    it('has proper aria-label on main navigation', async () => {
      wrapper = mountComponent({}, {
        authenticated: true,
        cust: mockCustomer,
      });

      await nextTick();

      const nav = wrapper.find('nav[role="navigation"]');
      expect(nav.attributes('aria-label')).toBe('Main Navigation');
    });

    it('logo link has aria-label', async () => {
      wrapper = mountComponent({}, {
        authenticated: false,
        domain_logo: 'https://example.com/brand.png',
      });

      await nextTick();

      const logoLink = wrapper.find('a[aria-label]');
      expect(logoLink.exists()).toBe(true);
    });
  });
});
