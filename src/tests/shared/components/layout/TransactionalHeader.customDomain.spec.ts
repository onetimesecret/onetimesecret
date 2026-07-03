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
import { createTestingPinia } from '@pinia/testing';
import TransactionalHeader from '@/shared/components/layout/TransactionalHeader.vue';
import { createTestI18n } from '@tests/setup';
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

const i18n = createTestI18n();

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

  type HomepageConfigState = {
    domain_id?: string;
    enabled?: boolean;
    signup_enabled?: boolean;
    signin_enabled?: boolean;
    created_at?: number | null;
    updated_at?: number | null;
  } | null;

  const mountComponent = (
    props: Record<string, unknown> = {},
    storeState: {
      domain_strategy?: string;
      domain_logo?: string | null;
      authentication?: { enabled?: boolean; signin?: boolean; signup?: boolean };
      homepage_config?: HomepageConfigState;
      header?: Record<string, unknown>;
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
          homepage_config: storeState.homepage_config !== undefined
            ? storeState.homepage_config
            : null,
          ui: {
            header: storeState.header ?? {
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
            ...storeState.authentication,
          },
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
        stubs: {
          'router-link': {
            props: ['to'],
            template: '<a :href="typeof to === \'string\' ? to : \'#\'"><slot /></a>',
          },
        },
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

  describe('showMinimalNav — Sign Up + Sign In links', () => {
    const minimalNavProps = { displayMasthead: false, displayNavigation: true };

    it('renders Sign Up and Sign In when both are enabled', async () => {
      wrapper = mountComponent(minimalNavProps, { domain_strategy: 'custom' });
      await nextTick();
      expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(true);
      expect(wrapper.find('[role="separator"]').exists()).toBe(true);
    });

    it('hides Sign Up when authentication.signup is false', async () => {
      wrapper = mountComponent(minimalNavProps, {
        domain_strategy: 'custom',
        authentication: { enabled: true, signin: true, signup: false },
      });
      await nextTick();
      expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(true);
      expect(wrapper.find('[role="separator"]').exists()).toBe(false);
    });

    it('hides Sign In when authentication.signin is false', async () => {
      wrapper = mountComponent(minimalNavProps, {
        domain_strategy: 'custom',
        authentication: { enabled: true, signin: false, signup: true },
      });
      await nextTick();
      expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(false);
      expect(wrapper.find('[role="separator"]').exists()).toBe(false);
    });

    it('hides both links when authentication.enabled is false', async () => {
      wrapper = mountComponent(minimalNavProps, {
        domain_strategy: 'custom',
        authentication: { enabled: false, signin: true, signup: true },
      });
      await nextTick();
      expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(false);
    });

    it('does not render minimal nav when displayMasthead is true (canonical domain)', async () => {
      wrapper = mountComponent(
        { displayMasthead: true, displayNavigation: true },
        { domain_strategy: 'canonical' }
      );
      await nextTick();
      expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(false);
    });

    describe('homepage_config domain-level toggles', () => {
      // System authentication flags are both true in all cases below so the
      // domain-layer toggle is the only variable under test.

      it('hides Sign Up when homepage_config.signup_enabled is false (system signup=true)', async () => {
        wrapper = mountComponent(minimalNavProps, {
          domain_strategy: 'custom',
          authentication: { enabled: true, signin: true, signup: true },
          homepage_config: {
            domain_id: 'test-domain-id',
            enabled: true,
            signup_enabled: false,
            signin_enabled: true,
            created_at: null,
            updated_at: null,
          },
        });
        await nextTick();
        expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(true);
        // Separator requires both sides to be visible
        expect(wrapper.find('[role="separator"]').exists()).toBe(false);
      });

      it('hides Sign In when homepage_config.signin_enabled is false (system signin=true)', async () => {
        wrapper = mountComponent(minimalNavProps, {
          domain_strategy: 'custom',
          authentication: { enabled: true, signin: true, signup: true },
          homepage_config: {
            domain_id: 'test-domain-id',
            enabled: true,
            signup_enabled: true,
            signin_enabled: false,
            created_at: null,
            updated_at: null,
          },
        });
        await nextTick();
        expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(false);
        expect(wrapper.find('[role="separator"]').exists()).toBe(false);
      });

      it('hides both links when homepage_config has both disabled; no separator renders', async () => {
        wrapper = mountComponent(minimalNavProps, {
          domain_strategy: 'custom',
          authentication: { enabled: true, signin: true, signup: true },
          homepage_config: {
            domain_id: 'test-domain-id',
            enabled: true,
            signup_enabled: false,
            signin_enabled: false,
            created_at: null,
            updated_at: null,
          },
        });
        await nextTick();
        expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(false);
        expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(false);
        expect(wrapper.find('[role="separator"]').exists()).toBe(false);
      });

      // INVARIANT GUARD: null homepage_config must mean "show the links".
      // TransactionalHeader renders on the canonical site too, where there is
      // no per-domain config (null). If someone changes the component's
      // `!== false` gate to `=== true` (to match BrandedMastHead's stricter
      // custom-only rule), this case fails — that failure is intentional. Do
      // not relax this expectation to make such a change pass; canonical relies
      // on null → visible. See the comment on showDomainSignin in
      // TransactionalHeader.vue.
      it('renders both links when homepage_config is null (canonical domain, no restriction)', async () => {
        wrapper = mountComponent(minimalNavProps, {
          domain_strategy: 'custom',
          authentication: { enabled: true, signin: true, signup: true },
          homepage_config: null,
        });
        await nextTick();
        expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(true);
        expect(wrapper.find('[role="separator"]').exists()).toBe(true);
      });

      it('renders both links when homepage_config has both explicitly true', async () => {
        wrapper = mountComponent(minimalNavProps, {
          domain_strategy: 'custom',
          authentication: { enabled: true, signin: true, signup: true },
          homepage_config: {
            domain_id: 'test-domain-id',
            enabled: true,
            signup_enabled: true,
            signin_enabled: true,
            created_at: null,
            updated_at: null,
          },
        });
        await nextTick();
        expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(true);
        expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(true);
        expect(wrapper.find('[role="separator"]').exists()).toBe(true);
      });
    });
  });

  // HEADER_ENABLED gate (#3362): operator config collapses the entire
  // <header> banner landmark — no empty landmark, no whitespace band.
  // This guard is folded into the existing displayHeader check (both must hold).
  describe('HEADER_ENABLED gate', () => {
    it('removes the <header> element when header.enabled is false', async () => {
      wrapper = mountComponent({}, {
        domain_strategy: 'canonical',
        header: { enabled: false },
      });

      await nextTick();
      expect(wrapper.find('header').exists()).toBe(false);
      // Content collapses with the landmark, not merely emptied.
      expect(wrapper.find('.masthead').exists()).toBe(false);
    });

    it('renders the <header> element when header.enabled is true', async () => {
      wrapper = mountComponent({}, {
        domain_strategy: 'canonical',
        header: { enabled: true },
      });

      await nextTick();
      expect(wrapper.find('header').exists()).toBe(true);
    });

    it('renders the <header> element when header.enabled is omitted (default true)', async () => {
      wrapper = mountComponent({}, { domain_strategy: 'canonical' });

      await nextTick();
      expect(wrapper.find('header').exists()).toBe(true);
    });

    // Regression: header.enabled is orthogonal to displayMasthead. With the
    // header enabled but masthead hidden (custom-domain fallback), the minimal
    // nav must still render — the operator gate must not break showMinimalNav.
    it('still fires showMinimalNav when header.enabled is true but displayMasthead is false', async () => {
      wrapper = mountComponent(
        { displayMasthead: false, displayNavigation: true },
        {
          domain_strategy: 'custom',
          header: { enabled: true },
          authentication: { enabled: true, signin: true, signup: true },
        }
      );

      await nextTick();
      expect(wrapper.find('header').exists()).toBe(true);
      expect(wrapper.find('.masthead').exists()).toBe(false);
      expect(wrapper.find('[data-testid="header-signup-link"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="header-signin-link"]').exists()).toBe(true);
    });
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
