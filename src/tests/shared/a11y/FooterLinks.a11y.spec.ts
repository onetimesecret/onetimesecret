// src/tests/shared/a11y/FooterLinks.a11y.spec.ts

//
// Layer-1 accessibility regression tests for FooterLinks.vue — the configurable
// footer link columns rendered on public/transactional pages. Exercises the
// heading + list + anchor structure with a realistic footer_links config from
// the bootstrap store.
//

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, vi, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import FooterLinks from '@/shared/components/layout/FooterLinks.vue';
import { createTestI18n } from '@tests/setup';
import { expectNoA11yViolations } from '@tests/support/axe';

const i18n = createTestI18n();

const footerLinksConfig = {
  enabled: true,
  groups: [
    {
      name: 'company',
      i18n_key: 'web.footer.company',
      links: [
        { url: 'https://example.com/about', i18n_key: 'web.footer.about' },
        { url: 'https://example.com/blog', text: 'Blog' },
      ],
    },
    {
      name: 'legal',
      i18n_key: 'web.footer.legal',
      links: [
        { url: '/privacy', text: 'Privacy' },
        // Intentionally empty URL: renders as a non-link <span> fallback.
        { url: '', text: 'Coming soon' },
      ],
    },
  ],
};

describe('FooterLinks a11y', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = (footerLinks: unknown = footerLinksConfig) =>
    mount(FooterLinks, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: {
                ui: { footer_links: footerLinks },
              },
            },
          }),
        ],
      },
    });

  it('has no a11y violations with a populated footer config', async () => {
    wrapper = mountComponent();
    await expectNoA11yViolations(wrapper);
  });
});
