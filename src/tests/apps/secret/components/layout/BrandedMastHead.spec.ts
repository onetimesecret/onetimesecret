// src/tests/apps/secret/components/layout/BrandedMastHead.spec.ts
//
// Guards two behaviours of the custom-domain masthead:
//   1. Logo accessibility: the logo image must carry a meaningful alt (the
//      brand/workspace display name) rather than an empty alt.
//   2. Auth nav links default OFF: the Create Account / Sign In links only
//      render when the domain's homepage_config explicitly opts in
//      (signup_enabled/signin_enabled === true). A null homepage_config or a
//      false flag keeps them hidden — recipients and employees arriving via a
//      shared link should not see account chrome unless an operator enabled it.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { nextTick } from 'vue';
import BrandedMastHead from '@/apps/secret/components/layout/BrandedMastHead.vue';

// Neutralise the SSO feature helpers so showSignIn depends purely on the
// platform auth flags and the domain-level homepage_config toggle under test.
vi.mock('@/utils/features', () => ({
  isSsoEnabled: () => false,
  isOrgsSsoEnabled: () => false,
}));

const i18n = createTestI18n();

type HomepageConfigState = {
  domain_id?: string;
  enabled?: boolean;
  signup_enabled?: boolean;
  signin_enabled?: boolean;
  created_at?: number | null;
  updated_at?: number | null;
} | null;

interface Overrides {
  domain_logo?: string | null;
  domain_branding?: Record<string, unknown>;
  authentication?: { enabled?: boolean; signin?: boolean; signup?: boolean };
  homepage_config?: HomepageConfigState;
}

const mountBranded = (overrides: Overrides = {}): VueWrapper => {
  const pinia = createTestingPinia({
    createSpy: vi.fn,
    stubActions: false,
    initialState: {
      bootstrap: {
        domain_strategy: 'custom',
        domain_logo: overrides.domain_logo ?? 'https://cdn.example/acme-logo.png',
        domains_enabled: true,
        display_domain: 'secrets.acme.com',
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        domain_id: 'cd_acme',
        domain_branding: overrides.domain_branding ?? {
          description: 'Acme Corp',
          primary_color: '#36454F',
          corner_style: 'rounded',
          font_family: 'sans',
          button_text_light: true,
        },
        authentication: overrides.authentication,
        homepage_config: overrides.homepage_config ?? null,
      },
    },
  });

  return mount(BrandedMastHead, {
    global: {
      plugins: [i18n, pinia],
      stubs: {
        RouterLink: { template: '<a><slot /></a>', props: ['to'] },
      },
    },
  });
};

describe('BrandedMastHead logo accessibility', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('uses the brand display name as the logo alt (not an empty alt)', async () => {
    wrapper = mountBranded();
    await nextTick();

    const img = wrapper.find('img');
    expect(img.exists()).toBe(true);
    expect(img.attributes('alt')).toBe('Acme Corp');
    expect(img.attributes('alt')).not.toBe('');
  });

  it('falls back to the display domain when no brand description is configured', async () => {
    wrapper = mountBranded({ domain_branding: { primary_color: '#36454F' } });
    await nextTick();

    expect(wrapper.find('img').attributes('alt')).toBe('secrets.acme.com');
  });
});

describe('BrandedMastHead auth nav links (default-off)', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  // Platform auth is fully enabled in every case below so the domain-level
  // homepage_config toggle is the only variable under test.
  const authOn = { enabled: true, signin: true, signup: true };

  const config = (overrides: Partial<NonNullable<HomepageConfigState>>) => ({
    domain_id: 'cd_acme',
    enabled: true,
    signup_enabled: false,
    signin_enabled: false,
    created_at: null,
    updated_at: null,
    ...overrides,
  });

  it('hides both links (and the nav) when homepage_config is null', async () => {
    wrapper = mountBranded({ authentication: authOn, homepage_config: null });
    await nextTick();

    expect(wrapper.find('[data-testid="branded-signup-link"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="branded-signin-link"]').exists()).toBe(false);
    // The whole nav collapses when neither link is shown.
    expect(wrapper.find('nav').exists()).toBe(false);
  });

  it('keeps both links hidden when homepage_config flags are false', async () => {
    wrapper = mountBranded({
      authentication: authOn,
      homepage_config: config({ signup_enabled: false, signin_enabled: false }),
    });
    await nextTick();

    expect(wrapper.find('[data-testid="branded-signup-link"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="branded-signin-link"]').exists()).toBe(false);
  });

  it('shows both links only when homepage_config explicitly opts in (=== true)', async () => {
    wrapper = mountBranded({
      authentication: authOn,
      homepage_config: config({ signup_enabled: true, signin_enabled: true }),
    });
    await nextTick();

    expect(wrapper.find('[data-testid="branded-signup-link"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="branded-signin-link"]').exists()).toBe(true);
    expect(wrapper.find('[role="separator"]').exists()).toBe(true);
  });

  it('shows only Sign In when signin_enabled opts in but signup_enabled stays off', async () => {
    wrapper = mountBranded({
      authentication: authOn,
      homepage_config: config({ signup_enabled: false, signin_enabled: true }),
    });
    await nextTick();

    expect(wrapper.find('[data-testid="branded-signup-link"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="branded-signin-link"]').exists()).toBe(true);
    // Separator only renders when both sides are visible.
    expect(wrapper.find('[role="separator"]').exists()).toBe(false);
  });
});
