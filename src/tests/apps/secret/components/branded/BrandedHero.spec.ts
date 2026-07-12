// src/tests/apps/secret/components/branded/BrandedHero.spec.ts
//
// Guards the shared branded hero (logo + headline + subline) that
// BrandedHomepage and BrandedMastHead render through:
//   1. Font tokens: the h1 binds headingFontClass (heading_font, falling back
//      to font_family) while the root binds the body fontFamilyClass — the
//      heading token must never degrade to the body font (the masthead
//      regression this component exists to prevent).
//   2. Logo behaviour: banner-friendly sizing (fixed height, natural width),
//      hidden entirely when absent or broken — no generic placeholder on a
//      branded page — and wrapped in a router-link only when the call site
//      asks for one.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { nextTick } from 'vue';
import BrandedHero from '@/apps/secret/components/branded/BrandedHero.vue';

const i18n = createTestI18n();

interface Overrides {
  domain_logo?: string | null;
  domain_branding?: Record<string, unknown>;
}

interface HeroProps {
  title?: string;
  subtitle?: string;
  logoLinkTo?: string;
}

const mountHero = (props: HeroProps = {}, overrides: Overrides = {}): VueWrapper => {
  const pinia = createTestingPinia({
    createSpy: vi.fn,
    stubActions: false,
    initialState: {
      bootstrap: {
        domain_strategy: 'custom',
        // `in` (not `??`) so an explicit null override reads as "no logo".
        domain_logo:
          'domain_logo' in overrides
            ? overrides.domain_logo
            : 'https://cdn.example/acme-logo.png',
        domains_enabled: true,
        display_domain: 'secrets.acme.com',
        site_host: 'onetimesecret.com',
        canonical_domain: 'onetimesecret.com',
        domain_id: 'cd_acme',
        domain_branding: overrides.domain_branding ?? {
          description: 'Acme Corp',
          primary_color: '#36454F',
          corner_style: 'rounded',
          font_family: 'serif',
          heading_font: 'slab',
          button_text_light: true,
        },
      },
    },
  });

  return mount(BrandedHero, {
    props: {
      title: 'Send a secret',
      subtitle: 'Deliver sensitive information securely',
      ...props,
    },
    global: {
      plugins: [i18n, pinia],
      stubs: {
        RouterLink: { template: '<a><slot /></a>', props: ['to'] },
      },
    },
  });
};

describe('BrandedHero font tokens', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('binds the heading font token (not the body font) on the h1', async () => {
    wrapper = mountHero();
    await nextTick();

    const h1 = wrapper.find('h1');
    expect(h1.exists()).toBe(true);
    expect(h1.classes()).toContain('font-brand-slab');
    expect(h1.classes()).not.toContain('font-serif');
    expect(h1.text()).toBe('Send a secret');
  });

  it('binds the body font token on the root so the subtitle inherits it', async () => {
    wrapper = mountHero();
    await nextTick();

    expect(wrapper.classes()).toContain('font-serif');
    expect(wrapper.classes()).not.toContain('font-brand-slab');
    expect(wrapper.find('p').text()).toBe('Deliver sensitive information securely');
  });

  it('falls back to the body font on the h1 when heading_font is unset', async () => {
    wrapper = mountHero({}, {
      domain_branding: {
        description: 'Acme Corp',
        primary_color: '#36454F',
        font_family: 'serif',
      },
    });
    await nextTick();

    expect(wrapper.find('h1').classes()).toContain('font-serif');
  });
});

describe('BrandedHero logo', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  it('renders banner-friendly sizing classes (fixed height, natural width)', async () => {
    wrapper = mountHero();
    await nextTick();

    const img = wrapper.find('img');
    expect(img.exists()).toBe(true);
    expect(img.classes()).toContain('h-16');
    expect(img.classes()).toContain('w-auto');
    expect(img.classes()).toContain('max-w-full');
    expect(img.classes()).toContain('object-contain');
  });

  it('uses the brand display name as the logo alt', async () => {
    wrapper = mountHero();
    await nextTick();

    expect(wrapper.find('img').attributes('alt')).toBe('Acme Corp');
  });

  it('hides the logo block entirely when no logo is configured', async () => {
    wrapper = mountHero({}, { domain_logo: null });
    await nextTick();

    expect(wrapper.find('img').exists()).toBe(false);
    // No placeholder either — the hero degrades to text-only.
    expect(wrapper.find('svg').exists()).toBe(false);
  });

  it('hides the logo block after the image fails to load', async () => {
    wrapper = mountHero();
    await nextTick();

    await wrapper.find('img').trigger('error');

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('svg').exists()).toBe(false);
  });

  it('wraps the logo in a router-link only when logoLinkTo is passed', async () => {
    wrapper = mountHero({ logoLinkTo: '/' });
    await nextTick();

    const link = wrapper.find('a');
    expect(link.exists()).toBe(true);
    expect(link.find('img').exists()).toBe(true);
  });

  it('renders a bare img when logoLinkTo is absent', async () => {
    wrapper = mountHero();
    await nextTick();

    expect(wrapper.find('img').exists()).toBe(true);
    expect(wrapper.find('a').exists()).toBe(false);
  });
});

describe('BrandedHero logo-only', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  // The reveal/confirm case opens with the logo but supplies its own heading
  // + instructions, so the hero must render the logo alone — no empty h1/p.
  it('renders the logo alone when title and subtitle are omitted', async () => {
    wrapper = mountHero({ title: undefined, subtitle: undefined });
    await nextTick();

    expect(wrapper.find('img').exists()).toBe(true);
    expect(wrapper.find('h1').exists()).toBe(false);
    expect(wrapper.find('p').exists()).toBe(false);
  });

  it('still links the logo when logoLinkTo is passed without title/subtitle', async () => {
    wrapper = mountHero({ title: undefined, subtitle: undefined, logoLinkTo: '/' });
    await nextTick();

    const link = wrapper.find('a');
    expect(link.exists()).toBe(true);
    expect(link.find('img').exists()).toBe(true);
  });
});
