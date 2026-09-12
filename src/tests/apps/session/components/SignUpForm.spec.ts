// src/tests/apps/session/components/SignUpForm.spec.ts
//
// The signup consent links resolve from site.legal config (#4278). With a
// URL configured the document name is a link (external -> new-tab anchor,
// relative -> router-link); with it unset the name renders as plain text so
// the consent sentence still reads correctly — the agreement still binds.

import SignUpForm from '@/apps/session/components/SignUpForm.vue';
import { createTestingPinia } from '@pinia/testing';
import { mount, RouterLinkStub } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { createTestI18n } from '@tests/setup';

vi.mock('@/shared/composables/useAuth', () => ({
  useAuth: () => ({
    signup: vi.fn(),
    isLoading: ref(false),
    error: ref(null),
    fieldError: ref(null),
    clearErrors: vi.fn(),
  }),
}));

vi.mock('vue-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('vue-router')>();
  return {
    ...actual,
    useRoute: () => ({ query: {} }),
  };
});

const i18n = createTestI18n();

interface LegalState {
  terms_url?: string | null;
  privacy_url?: string | null;
}

const mountComponent = (legal: LegalState = {}) =>
  mount(SignUpForm, {
    global: {
      plugins: [
        i18n,
        createTestingPinia({
          createSpy: vi.fn,
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
      stubs: { OIcon: true, RouterLink: RouterLinkStub },
    },
  });

describe('SignUpForm — consent links (#4278)', () => {
  it('links the terms and privacy names when URLs are configured (external)', () => {
    const wrapper = mountComponent({
      terms_url: 'https://example.com/terms',
      privacy_url: 'https://example.com/privacy',
    });

    const terms = wrapper.find('[data-testid="signup-terms-link"]');
    expect(terms.element.tagName).toBe('A');
    expect(terms.attributes('href')).toBe('https://example.com/terms');
    expect(terms.attributes('target')).toBe('_blank');
    expect(terms.attributes('rel')).toBe('noopener noreferrer');

    const privacy = wrapper.find('[data-testid="signup-privacy-link"]');
    expect(privacy.element.tagName).toBe('A');
    expect(privacy.attributes('href')).toBe('https://example.com/privacy');
  });

  it('uses router-links for relative URLs', () => {
    const wrapper = mountComponent({ terms_url: '/terms', privacy_url: '/privacy' });

    const links = wrapper.findAllComponents(RouterLinkStub);
    expect(links.map((l) => l.props('to'))).toEqual(['/terms', '/privacy']);
  });

  it('renders the names as plain text when URLs are unset — sentence stays grammatical', () => {
    const wrapper = mountComponent({});

    const terms = wrapper.find('[data-testid="signup-terms-link"]');
    const privacy = wrapper.find('[data-testid="signup-privacy-link"]');
    expect(terms.element.tagName).toBe('SPAN');
    expect(privacy.element.tagName).toBe('SPAN');
    expect(wrapper.findAllComponents(RouterLinkStub)).toHaveLength(0);

    // Full consent sentence still reads in order (pass-through i18n keys).
    const label = wrapper.find('label[for="terms-agreement"]');
    expect(label.text().replace(/\s+/g, ' ')).toBe(
      'web.auth.terms.agree_prefix web.layout.terms_of_service web.COMMON.and web.layout.privacy_policy'
    );
  });

  it('links one document and leaves the other as text when only one URL is set', () => {
    const wrapper = mountComponent({ privacy_url: 'https://example.com/privacy' });

    expect(wrapper.find('[data-testid="signup-terms-link"]').element.tagName).toBe('SPAN');
    expect(wrapper.find('[data-testid="signup-privacy-link"]').element.tagName).toBe('A');
  });
});
