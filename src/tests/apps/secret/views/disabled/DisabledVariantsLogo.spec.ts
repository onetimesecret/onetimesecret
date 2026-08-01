// src/tests/apps/secret/views/disabled/DisabledVariantsLogo.spec.ts
//
// Guards the centred-mark fallback chain for the branding-aware disabled
// homepage variants (V1 + Minimal):
//   configured custom-domain logo -> branded monogram -> NEUTRAL keyhole mark
//
// The neutral fallback must be the keyhole (KeyholeIcon). The OTS-company-only
// maruhi (秘) mark was removed from the codebase entirely so it can no longer
// leak into unbranded/private-label contexts.

import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { createTestI18n } from '@tests/setup';
import DisabledMinimal from '@/apps/secret/views/disabled/variants/DisabledMinimal.vue';
import DisabledV1 from '@/apps/secret/views/disabled/variants/DisabledV1.vue';

// Render the neutral mark as an identifiable stub so we can assert the
// fallback picked it.
vi.mock('@/shared/components/icons/KeyholeIcon.vue', () => ({
  default: { name: 'KeyholeIcon', template: '<svg data-testid="keyhole-mark" />' },
}));

const baseProps = {
  isBranded: false,
  workspaceName: 'Acme',
  monogramInitial: 'A',
  primaryColor: '#3B82F6',
  logoUri: null as string | null,
  logoDarkUri: null as string | null,
  logoAlt: null as string | null,
  displayDomain: 'acme.example',
  showSignin: true,
  showWhatIsThis: false,
  whatIsThisHref: null,
  showPromo: false,
  promoHref: null,
  ssoOneClick: false,
  ssoProviderName: null,
  onSsoLogin: () => {},
};

const mountVariant = (
  Component: typeof DisabledMinimal | typeof DisabledV1,
  overrides: Partial<typeof baseProps> = {}
) =>
  mount(Component, {
    props: { ...baseProps, ...overrides },
    global: {
      plugins: [createTestI18n()],
      stubs: {
        'router-link': { template: '<a><slot /></a>' },
        OIcon: { template: '<i />' },
      },
    },
  });

describe.each([
  ['DisabledMinimal', DisabledMinimal],
  ['DisabledV1', DisabledV1],
])('%s centred-mark fallback', (_name, Component) => {
  it('renders the neutral keyhole mark when unbranded with no logo', () => {
    const wrapper = mountVariant(Component, { isBranded: false, logoUri: null });

    expect(wrapper.find('[data-testid="keyhole-mark"]').exists()).toBe(true);
  });

  it('renders the uploaded custom-domain logo when logoUri is set', () => {
    const wrapper = mountVariant(Component, { logoUri: '/imagine/cd123/logo.png' });

    const img = wrapper.find('img');
    expect(img.exists()).toBe(true);
    expect(img.attributes('src')).toBe('/imagine/cd123/logo.png');
    expect(wrapper.find('[data-testid="keyhole-mark"]').exists()).toBe(false);
  });

  it('renders the branded monogram when branded with no logo', () => {
    const wrapper = mountVariant(Component, {
      isBranded: true,
      logoUri: null,
      monogramInitial: 'A',
    });

    expect(wrapper.text()).toContain('A');
    expect(wrapper.find('[data-testid="keyhole-mark"]').exists()).toBe(false);
  });
});

describe.each([
  ['DisabledMinimal', DisabledMinimal],
  ['DisabledV1', DisabledV1],
])('%s dark-logo variant + alt text (BrandMark)', (_name, Component) => {
  it('renders the dark img (hidden dark:block) when logoDarkUri is set', () => {
    const wrapper = mountVariant(Component, {
      logoUri: '/imagine/cd123/logo.png',
      logoDarkUri: '/imagine/cd123/logo-dark.png',
    });

    const dark = wrapper.find('[data-testid="logo-dark"]');
    expect(dark.exists()).toBe(true);
    expect(dark.attributes('src')).toBe('/imagine/cd123/logo-dark.png');
    expect(dark.classes()).toContain('hidden');
    expect(dark.classes()).toContain('dark:block');
    // Light img is swapped out in dark mode.
    expect(wrapper.findAll('img')[0].classes()).toContain('dark:hidden');
  });

  it('renders no dark img when logoDarkUri is null', () => {
    const wrapper = mountVariant(Component, {
      logoUri: '/imagine/cd123/logo.png',
      logoDarkUri: null,
    });

    expect(wrapper.find('[data-testid="logo-dark"]').exists()).toBe(false);
    expect(wrapper.findAll('img')).toHaveLength(1);
  });

  // Regression guard: an earlier v-if chain let the monogram/keyhole
  // co-render with a configured logo. The BrandMark fallback-slot boundary
  // must make that impossible.
  it('never co-renders the keyhole with a logo', () => {
    const wrapper = mountVariant(Component, {
      isBranded: false,
      logoUri: '/imagine/cd123/logo.png',
      logoDarkUri: '/imagine/cd123/logo-dark.png',
    });

    expect(wrapper.find('img').exists()).toBe(true);
    expect(wrapper.find('[data-testid="keyhole-mark"]').exists()).toBe(false);
  });

  it('never co-renders the monogram with a logo', () => {
    const wrapper = mountVariant(Component, {
      isBranded: true,
      monogramInitial: 'Z',
      logoUri: '/imagine/cd123/logo.png',
    });

    expect(wrapper.find('img').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Z');
  });

  it('uses logoAlt for both imgs when provided', () => {
    const wrapper = mountVariant(Component, {
      logoUri: '/imagine/cd123/logo.png',
      logoDarkUri: '/imagine/cd123/logo-dark.png',
      logoAlt: 'Acme Corp wordmark',
    });

    for (const img of wrapper.findAll('img')) {
      expect(img.attributes('alt')).toBe('Acme Corp wordmark');
    }
  });

  it('falls back to the i18n logo_alt key when logoAlt is null', () => {
    const wrapper = mountVariant(Component, {
      logoUri: '/imagine/cd123/logo.png',
      logoAlt: null,
    });

    // Pass-through test i18n renders the key itself (ADR-014).
    expect(wrapper.find('img').attributes('alt')).toBe('homepage_secrets.disabled.logo_alt');
  });
});

describe('DisabledV1 eyebrow dot color', () => {
  // The dot accent must follow primaryColor (which identityStore already
  // resolves to the neutral default when unbranded) and never the old
  // hardcoded OTS orange (#dc4a22 = rgb(220, 74, 34)).
  const findDot = (wrapper: ReturnType<typeof mountVariant>) =>
    wrapper.findAll('span').find((s) => (s.attributes('style') || '').includes('box-shadow'));

  it('uses primaryColor for the dot when unbranded (not hardcoded orange)', () => {
    const wrapper = mountVariant(DisabledV1, { isBranded: false, primaryColor: '#10b981' });
    const dot = findDot(wrapper);

    expect(dot).toBeDefined();
    // jsdom normalizes hex to rgb in inline styles.
    expect((dot!.element as HTMLElement).style.backgroundColor).toBe('rgb(16, 185, 129)');
    expect(dot!.attributes('style')).not.toContain('220, 74, 34');
  });

  it('uses the workspace primaryColor for the dot when branded', () => {
    const wrapper = mountVariant(DisabledV1, { isBranded: true, primaryColor: '#7c3aed' });
    const dot = findDot(wrapper);

    expect((dot!.element as HTMLElement).style.backgroundColor).toBe('rgb(124, 58, 237)');
  });
});
