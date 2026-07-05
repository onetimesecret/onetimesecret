// src/tests/shared/components/layout/MastHead.customDomain.spec.ts
//
// Tests for MastHead logo/brand behavior on custom domains.
// Covers the interaction between domain_strategy, domain_logo,
// and how the component decides which logo to render.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import MastHead from '@/shared/components/layout/MastHead.vue';
import { nextTick } from 'vue';
import { useAuthStore } from '@/shared/stores/authStore';
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

// Interpolating i18n: unlike the pass-through createTestI18n, the wordmark
// message renders the actual product_name so the "Onetime Secret must not
// leak" assertions below observe the real rendered name, not an i18n key.
// Unlisted keys still echo the key (missing handler), matching the
// pass-through assertions elsewhere in this file.
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  missingWarn: false,
  fallbackWarn: false,
  missing: (_, key) => key,
  messages: {
    en: {
      web: {
        homepage: {
          one_time_secret_literal: '{product_name}',
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

  type StoreState = {
    authenticated?: boolean;
    awaiting_mfa?: boolean;
    email?: string | null;
    cust?: typeof mockCustomer | null;
    domain_logo?: string | null;
    domain_strategy?: string;
    display_domain?: string;
    domain_id?: string;
    brand_logo_url?: string | null;
    brand_logo_alt?: string | null;
  };

  const buildBootstrapState = (s: StoreState) => ({
    authenticated: s.authenticated ?? false,
    awaiting_mfa: s.awaiting_mfa ?? false,
    email: s.email ?? null,
    cust: s.cust ?? null,
    domain_logo: s.domain_logo ?? null,
    domain_strategy: s.domain_strategy ?? 'canonical',
    display_domain: s.display_domain ?? 'onetimesecret.com',
    domain_id: s.domain_id ?? '',
    brand_logo_url: s.brand_logo_url ?? null,
    brand_logo_alt: s.brand_logo_alt ?? null,
  });

  const mountComponent = (props: Record<string, unknown> = {}, storeState: StoreState = {}) => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
      initialState: {
        bootstrap: {
          ...buildBootstrapState(storeState),
          // #3612: brand identity flows through the flat brand_* fields;
          // ui.header keeps only layout knobs. The platform name below is
          // the operator's install identity that must never leak onto a
          // tenant's custom domain.
          brand_product_name: 'Onetime Secret',
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
    const hasAuthenticatedCustomer = storeState.authenticated && storeState.cust;
    const hasMfaPendingEmail = storeState.awaiting_mfa && storeState.email;
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
    });
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // CANONICAL DOMAIN — Default OTS Logo
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Canonical domain (domain_strategy="canonical")', () => {
    it('renders DefaultLogo component when no custom domain logo', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'canonical',
          domain_logo: null,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
    });

    it('shows site name on canonical domain', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'canonical',
          domain_logo: null,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-show-site-name')).toBe('true');
    });

    it('uses 48px logo for unauthenticated users on canonical domain', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'canonical',
          domain_logo: null,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.attributes('data-size')).toBe('48');
    });

    it('uses 40px logo for authenticated users on canonical domain', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
          domain_strategy: 'canonical',
          domain_logo: null,
        }
      );

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
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: customLogoUrl,
          display_domain: 'secrets.acme.com',
          domain_id: 'cd_acme',
        }
      );

      await nextTick();
      // Should NOT render DefaultLogo component
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(false);

      // Should render img element with custom logo
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe(customLogoUrl);
    });

    it('uses default 48px height for custom domain logo when prominent is not set', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: customLogoUrl,
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Without prominent=true, custom domain logos use default sizing
      expect(img.attributes('height')).toBe('48');
      expect(img.attributes('width')).toBeUndefined();
    });

    it('applies default h-12, w-auto, and object-contain classes when prominent is not set', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: customLogoUrl,
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // Without prominent=true, default unauthenticated sizing is h-12 (48px)
      expect(img.classes()).toContain('h-12');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.classes()).toContain('w-auto');
      expect(img.classes()).toContain('object-contain');
    });

    it('hides site name when custom domain logo is present', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: customLogoUrl,
        }
      );

      await nextTick();
      // Site name should not appear next to custom domain logo by default
      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });

    it('renders a compact 40px custom domain logo for authenticated users so context switchers fit on the same row', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
          domain_strategy: 'custom',
          domain_logo: customLogoUrl,
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // The prominent 160px treatment is reserved for unauthenticated views
      // (branded homepage / disabled page); authenticated rows must keep room
      // for the org/domain dropdowns.
      expect(img.attributes('height')).toBe('40');
      expect(img.classes()).toContain('h-10');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CUSTOM DOMAIN WITHOUT LOGO — The bug scenario
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Custom domain without logo (domain_strategy="custom", domain_logo=null)', () => {
    it('falls back to DefaultLogo when custom domain has no uploaded logo', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
          display_domain: 'secrets.acme.com',
          domain_id: 'cd_acme',
        }
      );

      await nextTick();
      // When domain_logo is null on a custom domain, the resolver's logoSource
      // falls to the neutral DefaultLogo sentinel (never the operator's
      // install logo — see the #3612 leak-fix test below).
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(true);
    });

    it('renders the neutral DefaultLogo even when brand_logo_url is set (install-logo leak fix #3612)', async () => {
      // The operator's install-wide BRAND_LOGO_URL is the platform's own
      // identity. On a tenant's custom domain it must NOT render — same
      // semantics as showPlatformIdentity suppressing the wordmark. The
      // resolver's installLogoUri nulls out on custom domains, so logoSource
      // degrades to the neutral sentinel instead of leaking the install logo.
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
          brand_logo_url: '/img/install-brand.svg',
          display_domain: 'secrets.acme.com',
          domain_id: 'cd_acme',
        }
      );

      await nextTick();
      // Neutral mark renders...
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(true);
      // ...and the install logo <img> does not.
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(false);
    });

    it('suppresses the OTS site name when custom domain has no logo', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
          display_domain: 'secrets.acme.com',
        }
      );

      await nextTick();
      // A3 fix (via identityStore.showPlatformIdentity): on a custom domain the
      // DefaultLogo neutral mark still renders, but the platform site name
      // "Onetime Secret" must NOT leak next to it.
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      expect(logo.attributes('data-show-site-name')).toBe('false');
    });

    it('uses standard sizing (not 80px) when no custom logo is set', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
        }
      );

      await nextTick();
      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      // Should use 48px (unauthenticated default), NOT 80px (custom domain logo size)
      expect(logo.attributes('data-size')).toBe('48');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LOGO CONFIGURATION PRIORITY
  // ═══════════════════════════════════════════════════════════════════════════

  describe('Logo configuration priority: props > domain_logo > brand_logo_url > default', () => {
    it('props override domain_logo when both are provided', async () => {
      wrapper = mountComponent(
        {
          logo: {
            url: '/custom-override.png',
            alt: 'Override Logo',
            size: 48,
            isUserPresent: false,
          },
        },
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: 'https://cdn.example.com/domain-logo.png',
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      // The img should use the prop override URL, not the domain_logo
      expect(img.attributes('src')).toBe('/custom-override.png');
      // Explicit prop size is honored via inline style instead of a Tailwind class
      expect(img.attributes('style')).toContain('height: 48px');
      expect(img.classes()).not.toContain('h-24');
      expect(img.classes()).not.toContain('sm:h-40');
      expect(img.attributes('height')).toBe('48');
    });

    it('domain_logo takes priority over brand_logo_url', async () => {
      // On the canonical domain the install logo is allowed to show, so this
      // is the one context where both rungs compete on equal footing: the
      // tenant's uploaded logo must still win. (On custom domains the install
      // logo never shows at all — see the #3612 leak-fix test above.)
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'canonical',
          domain_logo: 'https://cdn.example.com/domain-logo.png',
          brand_logo_url: '/img/install-brand.svg',
        }
      );

      await nextTick();
      // Should use domain_logo, not the operator's install logo
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
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: 'https://cdn.example.com/logo.png',
        }
      );

      await nextTick();
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('alt')).toBeTruthy();
    });

    it('custom domain logo link has aria-label', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: 'https://cdn.example.com/logo.png',
        }
      );

      await nextTick();
      const logoLink = wrapper.find('a[aria-label]');
      expect(logoLink.exists()).toBe(true);
    });

    it('navigation has proper aria-label on custom domains', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: true,
          cust: mockCustomer,
          email: mockCustomer.email,
          domain_strategy: 'custom',
          domain_logo: 'https://cdn.example.com/logo.png',
        }
      );

      await nextTick();
      const nav = wrapper.find('nav[role="navigation"]');
      expect(nav.attributes('aria-label')).toBe('web.layout.main_navigation');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // A3 FIX: Default logo no longer leaks the platform name on custom domains
  //
  // Previously MastHead's site-name logic was driven only by `domain_logo`
  // (URL or null), not the domain strategy. When the strategy was 'custom' but
  // domain_logo was null (customer hasn't uploaded a logo), MastHead fell back
  // to the DefaultLogo AND still rendered the platform "Onetime Secret" site
  // name — leaking our identity onto another company's custom domain.
  //
  // The consolidation routes the base decision through
  // identityStore.showPlatformIdentity (`!isCustom && !logoUri`), so any custom
  // domain — logo or not — suppresses the wordmark while the neutral mark
  // still renders. The caller/operator override rungs are untouched.
  //
  // Leak routes: /incoming, /feedback, /help, /pricing — these use
  // TransactionalHeader → MastHead directly, with no domain-aware switching.
  //
  // Non-leaking routes: homepage (BrandedHeader switches), reveal (hides
  // masthead entirely), receipt (beforeEnter guard patches props).
  // ═══════════════════════════════════════════════════════════════════════════

  describe('A3 fix: MastHead is domain-strategy-aware when domain_logo is null', () => {
    it('shows the neutral DefaultLogo mark but no OTS site name on a custom domain with no logo', async () => {
      // A customer on secrets.acme.com falls back to the neutral DefaultLogo
      // mark, but the platform "Onetime Secret" site name must not leak.
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
          display_domain: 'secrets.acme.com',
          domain_id: 'cd_acme',
        }
      );

      await nextTick();

      // The neutral DefaultLogo mark still renders (brand-agnostic KeyholeIcon).
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(true);

      // FIXED: "Onetime Secret" site name is suppressed on another company's domain
      expect(defaultLogo.attributes('data-show-site-name')).toBe('false');
    });

    it('does not suppress auth navigation on custom domain (correct: auth nav should remain)', async () => {
      // Even on custom domains, sign in/sign up links should still appear
      // if authentication is enabled — this is NOT a bug
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
        }
      );

      await nextTick();
      const html = wrapper.html();
      expect(html).toContain('web.COMMON.header_sign_in');
      expect(html).toContain('web.COMMON.header_create_account');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // A3 REGRESSION GUARDS: MastHead is domain-strategy-aware via the resolver
  //
  // identityStore.showPlatformIdentity makes MastHead:
  // 1. If domain_logo is set → show the custom logo (unchanged).
  // 2. If domain_logo is null on a custom domain → render the neutral
  //    DefaultLogo mark WITHOUT the platform "Onetime Secret" site name.
  // Canonical domains are unaffected — the site name still shows there.
  // ═══════════════════════════════════════════════════════════════════════════

  describe('A3 regression: MastHead is domain-strategy-aware', () => {
    it('does not leak the "Onetime Secret" site name when custom domain has no logo', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
          display_domain: 'secrets.acme.com',
          domain_id: 'cd_acme',
        }
      );

      await nextTick();

      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      // Site name is suppressed...
      expect(logo.attributes('data-show-site-name')).toBe('false');
      // ...and the DefaultLogo mock only renders the site-name span when
      // showSiteName is true, so "Onetime Secret" must be absent from the DOM.
      const siteName = wrapper.find('.default-logo .site-name');
      expect(siteName.exists()).toBe(false);
      expect(wrapper.text()).not.toContain('Onetime Secret');
    });

    it('still renders the neutral DefaultLogo mark on a custom domain with no logo', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: null,
          display_domain: 'secrets.acme.com',
          domain_id: 'cd_acme',
        }
      );

      await nextTick();

      // We suppress the wordmark, not the whole lockup — the mark itself is safe.
      const defaultLogo = wrapper.find('.default-logo');
      expect(defaultLogo.exists()).toBe(true);
      const logoIcon = wrapper.find('.default-logo .logo-icon');
      expect(logoIcon.exists()).toBe(true);
    });

    it('sanity: still shows the site name on a canonical domain (fix scoped to custom/tenant)', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'canonical',
          domain_logo: null,
        }
      );

      await nextTick();

      const logo = wrapper.find('.default-logo');
      expect(logo.exists()).toBe(true);
      // Canonical domains are unaffected: the platform site name still shows.
      expect(logo.attributes('data-show-site-name')).toBe('true');
    });

    it('leaves custom-domain-WITH-logo behavior unchanged (img renders, no site name)', async () => {
      wrapper = mountComponent(
        {},
        {
          authenticated: false,
          domain_strategy: 'custom',
          domain_logo: 'https://cdn.example.com/logos/acme-logo.png',
          display_domain: 'secrets.acme.com',
          domain_id: 'cd_acme',
        }
      );

      await nextTick();

      // Custom logo renders as an <img>, not the DefaultLogo component.
      const img = wrapper.find('img#logo');
      expect(img.exists()).toBe(true);
      expect(img.attributes('src')).toBe('https://cdn.example.com/logos/acme-logo.png');
      // And the site name text mark is not rendered next to it.
      const siteName = wrapper.find('span.font-brand.text-lg');
      expect(siteName.exists()).toBe(false);
    });
  });
});
