// src/tests/components/GlobalBroadcast.spec.ts
//
// [S4] Verifies the narrowed DOMPurify config in GlobalBroadcast.vue:
// - URI scheme allowlist (https/http/mailto + relative) strips javascript:/data: hrefs
// - afterSanitizeAttributes hook forces rel="noopener noreferrer" on anchors
//   and only permits target="_blank"
// - allowed-tags list stays minimal (only <a>)

import GlobalBroadcast from '@/shared/components/ui/GlobalBroadcast.vue';
import { mount, type VueWrapper } from '@vue/test-utils';
import { beforeEach, describe, expect, it } from 'vitest';

const CONTENT_SELECTOR = '[role="status"] span';

function mountBroadcast(content: string): VueWrapper {
  return mount(GlobalBroadcast, {
    props: { content, show: true },
    global: {
      stubs: {
        OIcon: true,
        MovingGlobules: true,
      },
    },
  });
}

function renderedHtml(wrapper: VueWrapper): string {
  return wrapper.find(CONTENT_SELECTOR).element.innerHTML;
}

describe('GlobalBroadcast sanitization (S4)', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  describe('URI scheme allowlist', () => {
    it('strips javascript: hrefs', () => {
      const wrapper = mountBroadcast('<a href="javascript:alert(1)">click</a>');
      const html = renderedHtml(wrapper);
      expect(html).not.toContain('javascript:');
      expect(html).not.toContain('href');
      // Text content is preserved even when the href is dropped
      expect(html).toContain('click');
    });

    it('strips data: hrefs', () => {
      const wrapper = mountBroadcast(
        '<a href="data:text/html,<script>alert(1)</script>">payload</a>'
      );
      expect(renderedHtml(wrapper)).not.toContain('data:');
    });

    it('strips javascript: hrefs smuggled via HTML entities (decode-then-sanitize order)', () => {
      // Component decodes entities BEFORE sanitizing, so entity-encoded
      // payloads must still be caught.
      const wrapper = mountBroadcast(
        '&lt;a href="javascript:alert(1)"&gt;x&lt;/a&gt;'
      );
      expect(renderedHtml(wrapper)).not.toContain('javascript:');
    });

    it('keeps https, mailto, and relative hrefs', () => {
      const wrapper = mountBroadcast(
        '<a href="https://example.com">a</a>' +
          '<a href="mailto:ops@example.com">b</a>' +
          '<a href="/pricing">c</a>'
      );
      const html = renderedHtml(wrapper);
      expect(html).toContain('href="https://example.com"');
      expect(html).toContain('href="mailto:ops@example.com"');
      expect(html).toContain('href="/pricing"');
    });
  });

  describe('anchor hardening hook', () => {
    it('forces rel="noopener noreferrer" on every anchor', () => {
      const wrapper = mountBroadcast('<a href="https://example.com">link</a>');
      const anchor = wrapper.find(`${CONTENT_SELECTOR} a`);
      expect(anchor.attributes('rel')).toBe('noopener noreferrer');
    });

    it('overrides an attacker-supplied rel value', () => {
      const wrapper = mountBroadcast(
        '<a href="https://example.com" rel="opener">link</a>'
      );
      const anchor = wrapper.find(`${CONTENT_SELECTOR} a`);
      expect(anchor.attributes('rel')).toBe('noopener noreferrer');
    });

    it('keeps target="_blank"', () => {
      const wrapper = mountBroadcast(
        '<a href="https://example.com" target="_blank">link</a>'
      );
      const anchor = wrapper.find(`${CONTENT_SELECTOR} a`);
      expect(anchor.attributes('target')).toBe('_blank');
      expect(anchor.attributes('rel')).toBe('noopener noreferrer');
    });

    it('strips any target other than _blank', () => {
      const wrapper = mountBroadcast(
        '<a href="https://example.com" target="_top">link</a>'
      );
      const anchor = wrapper.find(`${CONTENT_SELECTOR} a`);
      expect(anchor.attributes('target')).toBeUndefined();
    });
  });

  describe('minimal tag allowlist', () => {
    it('strips script tags and event-handler-bearing elements', () => {
      const wrapper = mountBroadcast(
        'hello <script>alert(1)</script><img src="x" onerror="alert(1)"> world'
      );
      const html = renderedHtml(wrapper);
      expect(html).not.toContain('<script');
      expect(html).not.toContain('<img');
      expect(html).not.toContain('onerror');
      expect(html).toContain('hello');
      expect(html).toContain('world');
    });

    it('does not allow bold or other formatting tags (list not expanded)', () => {
      const wrapper = mountBroadcast('<b>bold</b> and <em>em</em>');
      const html = renderedHtml(wrapper);
      expect(html).not.toContain('<b>');
      expect(html).not.toContain('<em>');
      // Inner text survives
      expect(html).toContain('bold');
      expect(html).toContain('em');
    });
  });
});
