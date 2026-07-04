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
   *
   * Brand identity is seeded through the flat `brand_*` bootstrap fields
   * (BRAND_PRODUCT_NAME / BRAND_LOGO_URL / BRAND_LOGO_ALT); the header keeps
   * only layout knobs at ui.header.logo (#3612 — the ui.header.branding
   * nesting no longer exists). The defaults below model an unconfigured
   * install: neutral DefaultLogo, no operator logo, no product name.
   */
  const mountComponent = (
    props: Record<string, unknown> = {},
    storeState: {
      authenticated?: boolean;
      awaiting_mfa?: boolean;
      email?: string | null;
      cust?: typeof mockCustomer | null;
      domain_logo?: string | null;
      domain_strategy?: string;
      brand_product_name?: string | null;
      brand_logo_url?: string | null;
      brand_logo_alt?: string | null;
      header_logo?: {
        href?: string | null;
        show_name?: boolean | null;
        prominent?: boolean | null;
      };
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
          brand_product_name: storeState.brand_product_name ?? null,
          brand_logo_url: storeState.brand_logo_url ?? null,
          brand_logo_alt: storeState.brand_logo_alt ?? null,
          ui: {
            header: {
              enabled: true,
              logo: {
                href: storeState.header_logo?.href ?? null,
                show_name: storeState.header_logo?.show_name ?? null,
                prominent: storeState.header_logo?.prominent ?? null,
              },
              navigation: { enabled: true },
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

  describe('Install brand logo (brand_logo_url)', () => {
    // The operator's install-wide logo now flows in through the flat
    // brand_logo_url bootstrap field and the identity resolver
    // (installLogoUri → logoSource) — not ui.header.branding.logo.url,
    // which is gone (#3612).

    it('renders the install logo <img> from brand_logo_url with default sizing', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          brand_logo_url: '/img/brand.svg',
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('/img/brand.svg');
      // Without prominent=true, unauthenticated users get default 48px (h-12)
      expect(img.classes()).toContain('h-12');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.classes()).toContain('w-auto');
      expect(img.classes()).toContain('object-contain');
      expect(img.attributes('height')).toBe('48');
    });

    it('does not apply BRAND_LOGO_ALT to a tenant logo that outranks the install logo', async () => {
      // The operator's alt text describes the operator's image. When a tenant
      // domain_logo wins the logoSource race, the rendered <img> must not
      // carry BRAND_LOGO_ALT (wrong accessible name for the tenant's asset).
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_logo: '/imagine/ext123/logo.png',
          brand_logo_url: '/img/install-brand.svg',
          brand_logo_alt: 'Acme Corp wordmark',
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('/imagine/ext123/logo.png');
      expect(img.attributes('alt')).not.toBe('Acme Corp wordmark');
    });

    it('links the logo lockup to ui.header.logo.href (LOGO_LINK)', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          brand_logo_url: '/img/brand.svg',
          header_logo: { href: '/dashboard' },
        }
      );

      await nextTick();
      const link = wrapper.find('[data-testid="header-logo-link"]');
      expect(link.exists()).toBe(true);
      expect(link.attributes('href')).toBe('/dashboard');
    });

    it('defaults the logo link to "/" when href is unset (null)', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          brand_logo_url: '/img/brand.svg',
        }
      );

      await nextTick();
      const link = wrapper.find('[data-testid="header-logo-link"]');
      expect(link.exists()).toBe(true);
      expect(link.attributes('href')).toBe('/');
    });

    it('hides the wordmark by default next to a custom install logo (heuristic)', async () => {
      // A custom BRAND_LOGO_URL typically embeds its own wordmark, so the
      // site-name text mark should not appear next to it (matches the
      // long-standing behavior for per-domain uploaded logos).
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          brand_logo_url: '/img/brand.svg',
        }
      );

      await nextTick();
      // Site name span should not be rendered for a custom install logo
      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('shows the wordmark when ui.header.logo.show_name is explicitly true', async () => {
      // LOGO_SHOW_NAME=true must beat the custom-logo heuristic (#3160 order,
      // knob relocated from header.branding.logo to header.logo in #3612).
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          brand_logo_url: '/img/brand.svg',
          header_logo: { show_name: true },
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(true);
    });

    it('renders the neutral DefaultLogo at guest size when no install logo is configured', async () => {
      // Unconfigured install: brand_logo_url unset means the resolver falls
      // to the DefaultLogo sentinel — regular guest size (48px), never a
      // "custom logo" treatment. (Sentinel exclusion happens in Ruby:
      // brand_logo_url can never carry the DefaultLogo.vue sentinel.)
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

  describe('Prominent logo config (ui.header.logo.prominent)', () => {
    // LOGO_PROMINENT now lives at ui.header.logo.prominent (#3612); the
    // logo asset itself arrives via domain_logo through the resolver.
    const mountWithProminentLogo = (
      prominent: boolean,
      storeState: Parameters<typeof mountComponent>[1] = {}
    ) =>
      mountComponent(
        {},
        {
          ...storeState,
          header_logo: { ...storeState.header_logo, prominent },
        }
      );

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

    it('domain_logo wins over brand_logo_url (tenant beats install)', async () => {
      // Both logos configured on the canonical domain: the tenant's uploaded
      // logo outranks the operator's install logo in the resolver
      // (logoSource = logoUri || installLogoUri || sentinel, #3612).
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_logo: 'https://example.com/tenant.png',
          brand_logo_url: '/img/install.svg',
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('https://example.com/tenant.png');
    });
  });

  describe('Site name visibility priority (regression #3160, consolidated #3612)', () => {
    /**
     * Priority chain in getShowSiteName():
     *   1. props.logo.showSiteName            (caller-site override)
     *   2. !identity.showPlatformIdentity     (resolver base guard: any custom
     *                                          domain OR a per-tenant logo hides
     *                                          the platform wordmark)
     *   3. headerConfig.logo.show_name        (LOGO_SHOW_NAME explicit layout
     *                                          knob; ships null when unset)
     *   4. !isCustomStaticLogo                (heuristic: a custom BRAND_LOGO_URL
     *                                          usually embeds its own wordmark)
     *
     * #3160: in v0.25.3 step 4 ran ahead of step 3, so operators setting
     * LOGO_URL + LOGO_SHOW_NAME=true silently lost their wordmark.
     *
     * #3612: the wordmark text is now the resolver's productName
     * (brand_product_name || 'Secure Links') — header.branding.site_name is
     * gone — and the operator logo arrives via brand_logo_url, not
     * header.branding.logo.url.
     *
     * The tests below all use the canonical strategy with no domain_logo
     * unless stated, so showPlatformIdentity is true and rung 2 falls through.
     */
    const nameI18n = createI18n({
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

    const mountWithIdentity = (
      identity: {
        brandLogoUrl?: string | null;
        showName?: boolean | null;
        brandProductName?: string | null;
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
            domain_strategy: storeState.domain_strategy ?? 'canonical',
            brand_product_name: identity.brandProductName ?? null,
            brand_logo_url: identity.brandLogoUrl ?? null,
            brand_logo_alt: null,
            ui: {
              header: {
                enabled: true,
                logo: {
                  href: null,
                  show_name: identity.showName ?? null,
                  prominent: null,
                },
                navigation: { enabled: true },
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
          plugins: [nameI18n, pinia],
          stubs: {
            RouterLink: { template: '<a :href="to"><slot /></a>', props: ['to'] },
          },
        },
      });
    };

    it('renders the wordmark when BRAND_LOGO_URL is set AND show_name is true (core #3160 regression)', async () => {
      // The original bug: isCustomStaticLogo heuristic short-circuited ahead of
      // the explicit operator opt-in, so the wordmark vanished even though
      // LOGO_SHOW_NAME=true was configured. The wordmark text is the
      // resolver's productName (brand_product_name), not a header site_name.
      wrapper = mountWithIdentity(
        {
          brandLogoUrl: '/img/brand.svg',
          showName: true,
          brandProductName: 'Acme Vault',
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

    it('hides the wordmark when BRAND_LOGO_URL is set AND show_name is false', async () => {
      // Explicit operator opt-out must win over everything below it.
      wrapper = mountWithIdentity(
        {
          brandLogoUrl: '/img/brand.svg',
          showName: false,
          brandProductName: 'Acme Vault',
        },
        { authenticated: false }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('hides the wordmark when show_name is unset and a custom install logo is present (heuristic)', async () => {
      // Rung 4: LOGO_SHOW_NAME unset ships as null, so presence of a custom
      // BRAND_LOGO_URL hides the wordmark (the asset embeds its own).
      wrapper = mountWithIdentity(
        {
          brandLogoUrl: '/img/brand.svg',
          showName: null,
          brandProductName: 'Acme Vault',
        },
        { authenticated: false }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);

      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('shows the neutral productName wordmark when show_name is unset and no install logo (default posture)', async () => {
      // Unconfigured install: DefaultLogo renders with the resolver-supplied
      // neutral product name visible — never "One-Time Secret" (#3612).
      wrapper = mountWithIdentity(
        { brandLogoUrl: null, showName: null, brandProductName: null },
        { authenticated: false }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      expect(logo.attributes('data-show-site-name')).toBe('true');
      expect(logo.find('.site-name').text()).toBe(
        NEUTRAL_BRAND_DEFAULTS.product_name
      );
    });

    it('uses brand_product_name as the wordmark text when configured (no install logo)', async () => {
      wrapper = mountWithIdentity(
        { brandLogoUrl: null, showName: null, brandProductName: 'Acme Vault' },
        { authenticated: false }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      expect(logo.attributes('data-show-site-name')).toBe('true');
      expect(logo.find('.site-name').text()).toBe('Acme Vault');
    });

    it('renders the wordmark for the stock DefaultLogo when show_name is true', async () => {
      // Default install (Vue component logo) must still honor an explicit
      // LOGO_SHOW_NAME=true; the stub exposes data-show-site-name for assertion.
      wrapper = mountWithIdentity(
        { brandLogoUrl: null, showName: true, brandProductName: 'Acme Vault' },
        { authenticated: false }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      expect(logo.attributes('data-show-site-name')).toBe('true');
    });

    it('hides the wordmark when domain_logo is set even if show_name is true (multi-tenant invariant)', async () => {
      // Per-tenant domain_logo (step 2) must override LOGO_SHOW_NAME (step 3):
      // the platform-wide wordmark has no business appearing on a tenant page.
      wrapper = mountWithIdentity(
        {
          brandLogoUrl: '/img/brand.svg',
          showName: true,
          brandProductName: 'Acme Vault',
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

    it('hides the wordmark when props.logo.showSiteName=false even with BRAND_LOGO_URL and show_name=true', async () => {
      // props.logo.showSiteName (step 1) is the top of the priority chain;
      // an explicit false from a caller must beat both LOGO_SHOW_NAME and the
      // custom-logo heuristic.
      wrapper = mountWithIdentity(
        {
          brandLogoUrl: '/img/brand.svg',
          showName: true,
          brandProductName: 'Acme Vault',
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

  describe('Logo alt text (brand_logo_alt / productName interpolation)', () => {
    /**
     * These tests exercise getLogoAlt():
     *   props.logo.alt > identity.installLogoAlt (BRAND_LOGO_ALT, only while
     *   the install logo is shown) > t('...', { product_name }).
     *
     * Key setup requirements:
     *   1. Own i18n instance with `{product_name}` placeholders — the
     *      module-level i18n uses static strings so interpolation is ignored.
     *   2. brand_logo_url set to a non-.vue URL — so the <img :alt> branch
     *      renders (the DefaultLogo mock doesn't expose alt).
     *   3. brand_logo_alt cleared (unless under test) — otherwise the `||`
     *      chain in getLogoAlt short-circuits before t().
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

    const mountWithBrand = (
      brandProductName: string | null | undefined,
      opts: { brandLogoAlt?: string | null } = {}
    ) => {
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
            domain_strategy: 'canonical',
            brand_product_name: brandProductName,
            brand_logo_url: '/static/brand.png',
            brand_logo_alt: opts.brandLogoAlt ?? null,
            ui: {
              header: {
                enabled: true,
                logo: { href: null, show_name: null, prominent: null },
                navigation: { enabled: true },
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

    it('uses brand_logo_alt when the install logo is the asset being shown', async () => {
      wrapper = mountWithBrand('ACME', { brandLogoAlt: 'ACME Corp wordmark' });
      await nextTick();

      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('/static/brand.png');
      expect(img.attributes('alt')).toBe('ACME Corp wordmark');
    });

    it('interpolates brand_product_name into logo alt text when brand_logo_alt is unset', async () => {
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
