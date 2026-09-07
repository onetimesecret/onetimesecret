// src/tests/apps/secret/components/layout/SecretFooterAttribution.spec.ts
//
// The branded reveal footer's terms/privacy links resolve from site.legal
// config (#4278). A configured URL renders a link; an unset URL removes the
// whole affordance — separator dot included — so there is never a dead link
// on a recipient-facing page.

import SecretFooterAttribution from '@/apps/secret/components/layout/SecretFooterAttribution.vue';
import { createTestingPinia } from '@pinia/testing';
import { mount, RouterLinkStub } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import { createTestI18n } from '@tests/setup';

const i18n = createTestI18n();

interface LegalState {
  terms_url?: string | null;
  privacy_url?: string | null;
}

const mountComponent = (legal: LegalState = {}, props: Record<string, unknown> = {}) =>
  mount(SecretFooterAttribution, {
    props: { siteHost: 'example.com', showNav: true, showTerms: true, ...props },
    global: {
      plugins: [
        i18n,
        createTestingPinia({
          createSpy: vi.fn,
          stubActions: false,
          initialState: {
            bootstrap: {
              legal: {
                terms_url: legal.terms_url ?? null,
                privacy_url: legal.privacy_url ?? null,
                dpa_url: null,
                cookie_url: null,
                aup_url: null,
                security_url: null,
              },
            },
          },
        }),
      ],
      stubs: { RouterLink: RouterLinkStub },
    },
  });

const separators = (wrapper: ReturnType<typeof mountComponent>) =>
  wrapper.findAll('span[role="presentation"]');

describe('SecretFooterAttribution — legal links (#4278)', () => {
  describe('with both URLs configured', () => {
    it('renders external URLs as anchors opening in a new tab', () => {
      const wrapper = mountComponent({
        terms_url: 'https://example.com/terms',
        privacy_url: 'https://example.com/privacy',
      });

      const anchors = wrapper
        .findAll('a')
        .filter((a) => a.attributes('href')?.includes('/terms') || a.attributes('href')?.includes('/privacy'));
      expect(anchors).toHaveLength(2);
      for (const anchor of anchors) {
        expect(anchor.attributes('target')).toBe('_blank');
        expect(anchor.attributes('rel')).toBe('noopener noreferrer');
      }
      expect(separators(wrapper)).toHaveLength(2);
    });

    it('renders relative URLs as router-links', () => {
      const wrapper = mountComponent({ terms_url: '/terms', privacy_url: '/privacy' });

      const links = wrapper.findAllComponents(RouterLinkStub);
      expect(links.map((l) => l.props('to'))).toEqual(['/terms', '/privacy']);
    });
  });

  describe('with URLs unset', () => {
    it('renders neither link nor separators (absent, not dead)', () => {
      const wrapper = mountComponent({});

      expect(wrapper.findAllComponents(RouterLinkStub)).toHaveLength(0);
      expect(separators(wrapper)).toHaveLength(0);
      expect(wrapper.text()).not.toContain('web.footer.terms');
      expect(wrapper.text()).not.toContain('web.footer.privacy');
    });

    it('renders only the configured link when just one URL is set', () => {
      const wrapper = mountComponent({ privacy_url: '/privacy' });

      expect(wrapper.text()).not.toContain('web.footer.terms');
      expect(wrapper.text()).toContain('web.footer.privacy');
      expect(separators(wrapper)).toHaveLength(1);
    });
  });

  describe('showTerms=false', () => {
    it('renders no legal links even when configured', () => {
      const wrapper = mountComponent(
        { terms_url: '/terms', privacy_url: '/privacy' },
        { showTerms: false }
      );

      expect(wrapper.findAllComponents(RouterLinkStub)).toHaveLength(0);
      expect(separators(wrapper)).toHaveLength(0);
    });
  });
});
