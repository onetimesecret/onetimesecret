// src/tests/shared/components/layout/MastHead.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import MastHead from '@/shared/components/layout/MastHead.vue';
import { nextTick } from 'vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import { createTestI18n } from '@tests/setup';
import { createI18n } from 'vue-i18n';

// Mock DefaultLogo component
vi.mock('@/shared/components/logos/DefaultLogo.vue', () => ({
  default: {
    name: 'DefaultLogo',
    template: `<div class="default-logo" :data-size="size" :data-show-site-name="showSiteName">
      <span class="logo-icon" />
      <span v-if="showSiteName" class="site-name">{{ siteName }}</span>
    </div>`,
    props: [
      'url',
      'alt',
      'href',
      'size',
      'showSiteName',
      'siteName',
      'ariaLabel',
      'isColonelArea',
      'isUserPresent',
    ],
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

const i18n = createTestI18n();

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
    (authStore as unknown as { isUserPresent: boolean }).isUserPresent = !!(
      hasAuthenticatedCustomer || hasMfaPendingEmail
    );

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
    it('uses 48px logo for unauthenticated users', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          cust: null,
          email: null,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('48');
    });

    it('uses 40px logo for authenticated users', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('40');
    });

    it('uses 40px logo for MFA-pending users (partial auth)', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          awaiting_mfa: true,
          email: mockCustomer.email,
          cust: null,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('40');
    });

    it('uses compact sizing (h-10/40px) for authenticated users with a custom domain logo so context switchers fit on the same row', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
          domain_logo: 'https://example.com/custom-logo.png',
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Authenticated rows must keep room for the org/domain dropdowns;
      // the prominent h-24/sm:h-40 treatment is reserved for unauthenticated views.
      expect(img.classes()).toContain('h-10');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.classes()).toContain('w-auto');
      expect(img.classes()).toContain('object-contain');
      expect(img.attributes('height')).toBe('40');
    });

    it('respects explicit size prop override', async () => {
      wrapper = mountComponent(
        {
          logo: { size: 48, isUserPresent: false },
        },
        {
          authenticated: true,
          cust: mockCustomer,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('48');
    });
  });

  describe('Image logo sizing (non-Vue URL)', () => {
    it('uses default sizing for image URLs when prominent is not set', async () => {
      wrapper = mountComponent(
        {
          logo: { url: '/static/brand.png' },
        },
        {
          authenticated: false,
          cust: null,
          email: null,
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Without prominent=true, unauthenticated users get default 48px (h-12)
      expect(img.classes()).toContain('h-12');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.classes()).toContain('w-auto');
      expect(img.classes()).toContain('object-contain');
      expect(img.attributes('height')).toBe('48');
    });

    it('uses compact sizing for authenticated users even with prop-supplied custom logo', async () => {
      wrapper = mountComponent(
        {
          logo: { url: '/static/brand.png' },
        },
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Authenticated users always get compact sizing regardless of custom logo
      expect(img.classes()).toContain('h-10');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.classes()).toContain('w-auto');
      expect(img.classes()).toContain('object-contain');
      expect(img.attributes('height')).toBe('40');
      expect(img.attributes('width')).toBeUndefined();
      // Regression: old square class should not be present
      expect(img.classes()).not.toContain('size-10');
    });

    it('honors an explicit prop size override: omits h-* classes and sets inline height style', async () => {
      wrapper = mountComponent(
        {
          logo: { url: '/static/brand.png', size: 56 },
        },
        {
          authenticated: false,
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Prop size wins visually: no Tailwind height class is applied
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.classes()).not.toContain('h-40');
      expect(img.classes()).not.toContain('h-10');
      expect(img.classes()).not.toContain('h-12');
      // Inline style enforces the exact pixel size
      expect(img.attributes('style')).toContain('height: 56px');
      // Height attribute also reflects the override for pre-load layout reservation
      expect(img.attributes('height')).toBe('56');
      // Static classes are still present
      expect(img.classes()).toContain('w-auto');
      expect(img.classes()).toContain('object-contain');
    });
  });

  describe('Static config logo (ui.header.branding.logo.url)', () => {
    const mountWithStaticLogoUrl = (
      logoUrl: string,
      storeState: Parameters<typeof mountComponent>[1] = {}
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
                  logo: { url: logoUrl, alt: 'Brand' },
                  site_name: 'Brand',
                },
              },
            },
            authentication: { enabled: true, signin: true, signup: true },
          },
        },
      });

      const authStore = useAuthStore(pinia);
      const hasAuthenticatedCustomer = storeState.authenticated && storeState.cust;
      const hasMfaPendingEmail = storeState.awaiting_mfa && storeState.email;
      (authStore as unknown as { isUserPresent: boolean }).isUserPresent = !!(
        hasAuthenticatedCustomer || hasMfaPendingEmail
      );

      return mount(MastHead, {
        props: { displayMasthead: true, displayNavigation: true },
        global: {
          plugins: [i18n, pinia],
          stubs: {
            RouterLink: { template: '<a :href="to"><slot /></a>', props: ['to'] },
          },
        },
      });
    };

    it('uses default sizing for static image URL when prominent is not set', async () => {
      wrapper = mountWithStaticLogoUrl('/img/brand.svg', {
        authenticated: false,
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Without prominent=true, unauthenticated users get default 48px (h-12)
      expect(img.classes()).toContain('h-12');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.classes()).toContain('w-auto');
      expect(img.classes()).toContain('object-contain');
      expect(img.attributes('height')).toBe('48');
    });

    it('hides the site name by default for non-default static config logos', async () => {
      // Static-config custom branding typically embeds the wordmark in the image,
      // so the site name text mark should not appear next to it (matches the
      // long-standing behavior for per-domain uploaded logos).
      wrapper = mountWithStaticLogoUrl('/img/brand.svg', {
        authenticated: false,
      });

      await nextTick();
      // Site name span should not be rendered for a static custom image URL
      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('does NOT treat the default DefaultLogo.vue config as a custom logo (regression)', async () => {
      // Stock install: config.defaults.yaml ships branding.logo.url = 'DefaultLogo.vue'.
      // This must continue to use the regular guest size (48px), not the 160px custom size.
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          cust: null,
          email: null,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      expect(logo.attributes('data-size')).toBe('48');
    });
  });

  describe('Prominent logo config (logo.prominent)', () => {
    const mountWithProminentLogo = (
      prominent: boolean,
      storeState: Parameters<typeof mountComponent>[1] = {}
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
                  logo: {
                    url: storeState.domain_logo ?? 'DefaultLogo.vue',
                    alt: 'Brand',
                    prominent,
                  },
                  site_name: 'Brand',
                },
              },
            },
            authentication: { enabled: true, signin: true, signup: true },
          },
        },
      });

      // Manually set isUserPresent based on bootstrap state (same as mountComponent)
      const authStore = useAuthStore(pinia);
      const hasAuthenticatedCustomer = storeState.authenticated && storeState.cust;
      const hasMfaPendingEmail = storeState.awaiting_mfa && storeState.email;
      (authStore as unknown as { isUserPresent: boolean }).isUserPresent = !!(
        hasAuthenticatedCustomer || hasMfaPendingEmail
      );

      return mount(MastHead, {
        global: {
          plugins: [pinia, i18n],
          stubs: { Teleport: true },
        },
        props: {},
        slots: {
          'context-switchers': '<span>test-context-switchers</span>',
        },
      });
    };

    it('uses intermediate 80px sizing for authenticated users when prominent is true', async () => {
      wrapper = mountWithProminentLogo(true, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
        domain_logo: 'https://example.com/custom-logo.png',
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('height')).toBe('80');
      expect(img.classes()).toContain('h-20');
      expect(img.classes()).not.toContain('h-10');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
    });

    it('uses compact 40px sizing for authenticated users when prominent is false', async () => {
      wrapper = mountWithProminentLogo(false, {
        authenticated: true,
        cust: mockCustomer,
        email: mockCustomer.email,
        domain_logo: 'https://example.com/custom-logo.png',
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('height')).toBe('40');
      expect(img.classes()).toContain('h-10');
      expect(img.classes()).not.toContain('h-20');
    });

    it('uses 160px for unauthenticated users when prominent is true', async () => {
      wrapper = mountWithProminentLogo(true, {
        authenticated: false,
        cust: null,
        email: null,
        domain_logo: 'https://example.com/custom-logo.png',
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('height')).toBe('160');
      expect(img.classes()).toContain('h-24');
      expect(img.classes()).toContain('sm:h-40');
      expect(img.classes()).not.toContain('h-20');
    });

    it('uses default 48px for unauthenticated users when prominent is false', async () => {
      wrapper = mountWithProminentLogo(false, {
        authenticated: false,
        cust: null,
        email: null,
        domain_logo: 'https://example.com/custom-logo.png',
      });

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('height')).toBe('48');
      expect(img.classes()).toContain('h-12');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
    });
  });

  describe('Context Switchers Slot', () => {
    it('renders context-switchers slot for authenticated users', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
        }
      );

      await nextTick();

      // Context switchers container (unified for all screen sizes)
      const contextSwitchers = wrapper.find('.flex.min-w-0.items-center.gap-2');
      expect(contextSwitchers.exists()).toBe(true);
      expect(contextSwitchers.html()).toContain('test-context-switchers');
    });

    it('renders context-switchers slot with responsive gap', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
        }
      );

      await nextTick();

      // Verify responsive gap classes are present
      const contextSwitchers = wrapper.find('.flex.min-w-0.items-center.gap-2');
      expect(contextSwitchers.exists()).toBe(true);
      expect(contextSwitchers.classes()).toContain('sm:gap-3');
    });

    it('does not render context-switchers for unauthenticated users', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          cust: null,
          email: null,
        }
      );

      await nextTick();

      // Should not have context switcher container when not authenticated
      const html = wrapper.html();
      expect(html).not.toContain('test-context-switchers');
    });
  });

  describe('Navigation Display', () => {
    it('shows sign in/sign up links for unauthenticated users', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          cust: null,
          email: null,
        }
      );

      await nextTick();

      const html = wrapper.html();
      expect(html).toContain('web.COMMON.header_sign_in');
      expect(html).toContain('web.COMMON.header_create_account');
    });

    it('shows UserMenu for authenticated users', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
        }
      );

      await nextTick();

      const userMenu = wrapper.find('.user-menu');
      expect(userMenu.exists()).toBe(true);
    });

    it('hides navigation when displayNavigation is false', async () => {
      wrapper = mountComponent(
        {
          displayNavigation: false,
        },
        {
          authenticated: true,
          cust: mockCustomer,
        }
      );

      await nextTick();

      const nav = wrapper.find('nav[role="navigation"]');
      expect(nav.exists()).toBe(false);
    });
  });

  describe('Custom Domain Logo', () => {
    it('hides site name by default when custom domain logo is present', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_logo: 'https://example.com/brand.png',
        }
      );

      await nextTick();

      // When domain_logo is present, showSiteName defaults to false
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      // Site name span should not be rendered
      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('shows site name when explicitly configured with custom domain logo', async () => {
      wrapper = mountComponent(
        {
          logo: {
            showSiteName: true,
            siteName: 'Custom Brand',
            isUserPresent: false,
          },
        },
        {
          authenticated: false,
          domain_logo: 'https://example.com/brand.png',
        }
      );

      await nextTick();

      // Logo prop override should show site name
      const logo = wrapper.find('.default-logo');
      if (logo.exists()) {
        expect(logo.attributes('data-show-site-name')).toBe('true');
      }
    });
  });

  describe('Site name visibility priority (regression #3160)', () => {
    /**
     * Priority chain in getShowSiteName():
     *   1. props.logo.showSiteName            (caller-site override)
     *   2. !identity.showPlatformIdentity     (resolver base guard: any custom
     *                                          domain OR a per-tenant logo hides
     *                                          the platform wordmark)
     *   3. headerConfig.branding.logo.show_name  (LOGO_SHOW_NAME explicit)
     *   4. isCustomStaticLogo.value           (heuristic: non-default LOGO_URL)
     *   5. !!site_name                        (default tied to SITE_NAME)
     *
     * #3160: in v0.25.3 step 4 ran ahead of step 3, so operators setting
     * LOGO_URL + LOGO_SHOW_NAME=true silently lost their wordmark.
     *
     * The tests below all use the canonical strategy with no domain_logo, so
     * showPlatformIdentity is true and rung 2 falls through — exercising the
     * operator/config rungs unchanged by the resolver consolidation.
     */
    const mountWithBranding = (
      branding: {
        logoUrl: string;
        showName: boolean;
        siteName: string;
      },
      storeState: Parameters<typeof mountComponent>[1] = {},
      props: Record<string, unknown> = {}
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
                  logo: {
                    url: branding.logoUrl,
                    alt: 'Brand',
                    show_name: branding.showName,
                  },
                  site_name: branding.siteName,
                },
              },
            },
            authentication: { enabled: true, signin: true, signup: true },
          },
        },
      });

      const authStore = useAuthStore(pinia);
      const hasAuthenticatedCustomer = storeState.authenticated && storeState.cust;
      const hasMfaPendingEmail = storeState.awaiting_mfa && storeState.email;
      (authStore as unknown as { isUserPresent: boolean }).isUserPresent = !!(
        hasAuthenticatedCustomer || hasMfaPendingEmail
      );

      return mount(MastHead, {
        props: { displayMasthead: true, displayNavigation: true, ...props },
        global: {
          plugins: [i18n, pinia],
          stubs: {
            RouterLink: { template: '<a :href="to"><slot /></a>', props: ['to'] },
          },
        },
      });
    };

    it('renders site name when LOGO_URL is custom AND show_name is true (core #3160 regression)', async () => {
      // The original bug: isCustomStaticLogo heuristic short-circuited ahead of
      // the explicit operator opt-in, so the wordmark vanished even though
      // LOGO_SHOW_NAME=true was configured.
      wrapper = mountWithBranding(
        {
          logoUrl: '/img/brand.svg',
          showName: true,
          siteName: 'Acme Vault',
        },
        { authenticated: false }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(true);
      expect(siteName.text()).toBe('Acme Vault');
    });

    it('hides site name when LOGO_URL is custom AND show_name is false', async () => {
      // Explicit operator opt-out must win over the SITE_NAME default.
      wrapper = mountWithBranding(
        {
          logoUrl: '/img/brand.svg',
          showName: false,
          siteName: 'Acme Vault',
        },
        { authenticated: false }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('renders site name for the stock DefaultLogo when show_name is true', async () => {
      // Default install (Vue component logo) must still honor an explicit
      // LOGO_SHOW_NAME=true; the stub exposes data-show-site-name for assertion.
      wrapper = mountWithBranding(
        {
          logoUrl: 'DefaultLogo.vue',
          showName: true,
          siteName: 'Onetime Secret',
        },
        { authenticated: false }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      expect(logo.attributes('data-show-site-name')).toBe('true');
    });

    it('hides site name when domain_logo is set even if static show_name is true (multi-tenant invariant)', async () => {
      // Per-tenant domain_logo (step 2) must override LOGO_SHOW_NAME (step 3):
      // the platform-wide site name has no business appearing on a tenant page.
      wrapper = mountWithBranding(
        {
          logoUrl: '/img/brand.svg',
          showName: true,
          siteName: 'Acme Vault',
        },
        {
          authenticated: false,
          domain_logo: 'https://tenant.example.com/logo.png',
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('hides site name when props.logo.showSiteName=false even with LOGO_URL and show_name=true', async () => {
      // props.logo.showSiteName (step 1) is the top of the priority chain;
      // an explicit false from a caller must beat both LOGO_SHOW_NAME and the
      // custom-logo heuristic.
      wrapper = mountWithBranding(
        {
          logoUrl: '/img/brand.svg',
          showName: true,
          siteName: 'Acme Vault',
        },
        { authenticated: false },
        {
          logo: { showSiteName: false, isUserPresent: false },
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });
  });

  describe('Accessibility', () => {
    it('has proper aria-label on main navigation', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
        }
      );

      await nextTick();

      const nav = wrapper.find('nav[role="navigation"]');
      expect(nav.attributes('aria-label')).toBe('web.layout.main_navigation');
    });

    it('logo link has aria-label', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_logo: 'https://example.com/brand.png',
        }
      );

      await nextTick();

      const logoLink = wrapper.find('a[aria-label]');
      expect(logoLink.exists()).toBe(true);
    });
  });

  describe('brand_product_name interpolation', () => {
    /**
     * These tests exercise the `t('...', { product_name })` interpolation
     * path in getLogoAlt (line 51 of MastHead.vue).
     *
     * Key setup requirements:
     *   1. Own i18n instance with `{product_name}` placeholders — the
     *      module-level i18n uses static strings so interpolation is ignored.
     *   2. branding.logo.alt and branding.site_name cleared — otherwise the
     *      `||` chain in getLogoAlt/getSiteName short-circuits before t().
     *   3. Non-.vue logo URL — so the <img :alt> branch renders (the
     *      DefaultLogo mock doesn't expose alt).
     */
    const brandI18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: {
        en: {
          web: {
            homepage: {
              one_time_secret_literal: '{product_name}',
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

    const mountWithBrand = (brandProductName: string | null | undefined) => {
      const pinia = createTestingPinia({
        createSpy: vi.fn,
        stubActions: false,
        initialState: {
          bootstrap: {
            authenticated: false,
            awaiting_mfa: false,
            email: null,
            cust: null,
            domain_logo: null,
            brand_product_name: brandProductName,
            ui: {
              header: {
                navigation: { enabled: true },
                branding: {
                  logo: { url: '/static/brand.png', alt: null },
                  site_name: null,
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
      (authStore as unknown as { isUserPresent: boolean }).isUserPresent = false;

      return mount(MastHead, {
        props: {
          displayMasthead: true,
          displayNavigation: true,
        },
        global: {
          plugins: [brandI18n, pinia],
          stubs: {
            RouterLink: {
              template: '<a :href="to"><slot /></a>',
              props: ['to'],
            },
          },
        },
      });
    };

    it('interpolates brand_product_name into logo alt text', async () => {
      wrapper = mountWithBrand('ACME');
      await nextTick();

      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('alt')).toBe('ACME');
    });

    it('falls back to NEUTRAL_BRAND_DEFAULTS.product_name when undefined', async () => {
      wrapper = mountWithBrand(undefined);
      await nextTick();

      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('alt')).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
    });

    it('falls back to NEUTRAL_BRAND_DEFAULTS.product_name when null', async () => {
      wrapper = mountWithBrand(null);
      await nextTick();

      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('alt')).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
    });

    it('falls back to NEUTRAL_BRAND_DEFAULTS.product_name for an empty string', async () => {
      wrapper = mountWithBrand('');
      await nextTick();

      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Consolidation routes the alt text through identityStore.productName,
      // which uses `||` (not `??`): a blank product-name config degrades to the
      // neutral 'Secure Links' instead of rendering an empty alt — matching
      // DefaultLogo and usePageTitle.
      expect(img.attributes('alt')).toBe(NEUTRAL_BRAND_DEFAULTS.product_name);
    });
  });
});
