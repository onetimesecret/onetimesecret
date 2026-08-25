// src/tests/shared/components/common/LegalLink.spec.ts
//
// LegalLink renders a legal/policy document reference whose URL comes from
// site.legal config (#4278) and may be unset:
//
//   - absolute http(s) URL  -> <a target="_blank" rel="noopener noreferrer">
//   - relative path         -> <router-link> (in-app navigation)
//   - unset (null/empty)    -> plain text span: the surrounding sentence
//                              stays grammatical, with no dead anchor and
//                              no link styling on unclickable text.

import LegalLink from '@/shared/components/common/LegalLink.vue';
import { mount, RouterLinkStub } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';

const mountComponent = (url: string | null | undefined) =>
  mount(LegalLink, {
    props: { url },
    slots: { default: 'Terms of Service' },
    attrs: { class: 'link-style', 'data-testid': 'legal-link', target: '_blank' },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });

describe('LegalLink', () => {
  describe('external URL', () => {
    it('renders an anchor opening in a new tab', () => {
      const wrapper = mountComponent('https://example.com/terms');

      const anchor = wrapper.find('a');
      expect(anchor.exists()).toBe(true);
      expect(anchor.attributes('href')).toBe('https://example.com/terms');
      expect(anchor.attributes('target')).toBe('_blank');
      expect(anchor.attributes('rel')).toBe('noopener noreferrer');
      expect(anchor.text()).toBe('Terms of Service');
    });

    it('passes fallthrough attrs to the anchor', () => {
      const wrapper = mountComponent('https://example.com/terms');

      const anchor = wrapper.find('a');
      expect(anchor.classes()).toContain('link-style');
      expect(anchor.attributes('data-testid')).toBe('legal-link');
    });
  });

  describe('relative URL', () => {
    it('renders a router-link for in-app navigation', () => {
      const wrapper = mountComponent('/terms');

      const link = wrapper.findComponent(RouterLinkStub);
      expect(link.exists()).toBe(true);
      expect(link.props('to')).toBe('/terms');
      expect(wrapper.text()).toBe('Terms of Service');
    });
  });

  describe('unset URL', () => {
    it.each([null, undefined, ''])('renders plain text for %s', (url) => {
      const wrapper = mountComponent(url);

      expect(wrapper.find('a').exists()).toBe(false);
      expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
      const span = wrapper.find('span');
      expect(span.exists()).toBe(true);
      expect(span.text()).toBe('Terms of Service');
    });

    it('keeps identifying attrs but drops link styling and link-only attrs on the fallback', () => {
      const wrapper = mountComponent(null);

      const span = wrapper.find('span');
      expect(span.attributes('data-testid')).toBe('legal-link');
      expect(span.classes()).not.toContain('link-style');
      expect(span.attributes('target')).toBeUndefined();
      expect(span.attributes('rel')).toBeUndefined();
    });
  });
});
