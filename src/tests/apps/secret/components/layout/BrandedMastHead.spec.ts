// src/tests/apps/secret/components/layout/BrandedMastHead.spec.ts
//
// Guards the accessibility of the custom-domain logo image: it must carry a
// meaningful alt (the brand/workspace display name) rather than an empty alt,
// so screen-reader users hear the brand instead of skipping the image.

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';
import { nextTick } from 'vue';
import BrandedMastHead from '@/apps/secret/components/layout/BrandedMastHead.vue';

const i18n = createTestI18n();

interface Overrides {
  domain_logo?: string | null;
  domain_branding?: Record<string, unknown>;
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
        homepage_config: null,
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
