// src/tests/composables/useDnsWidget.spec.ts
//
// [S5] Verifies the DNS widget's dynamically injected <script> carries the
// per-request CSP nonce. The backend emits a nonce-only script-src (no
// 'strict-dynamic', no 'self'), so an un-nonced injected script is blocked
// by the browser.

import { resolveCspNonce, useDnsWidget } from '@/shared/composables/useDnsWidget';
import { sanitizeDnsWidgetHtml } from '@/shared/utils/dnsWidgetHtml';
import { getGlobalAxiosMock } from '@/tests/setup-stores';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';

const TEST_NONCE = 'dGVzdC1ub25jZQ==';

/**
 * Mount a host component that owns the composable. The global test setup
 * (setup-stores.ts) mocks inject('api') to the shared axios-mock-adapter
 * instance, so token responses are configured via getGlobalAxiosMock().
 */
function mountWidgetHost() {
  const Host = defineComponent({
    setup(_, { expose }) {
      const widget = useDnsWidget({ dnsRecords: [] });
      expose({ widget });
      return () => h('div', { id: 'apxdnswidget' });
    },
  });
  return mount(Host, {
    attachTo: document.body,
    global: { plugins: [createTestI18n()] },
  });
}

/** Capture the <script> element appended to document.head by loadAssets. */
function spyOnInjectedScript() {
  const spy = vi.spyOn(document.head, 'appendChild');
  return {
    getScript(): HTMLScriptElement | undefined {
      return spy.mock.calls
        .map((call) => call[0])
        .find((node): node is HTMLScriptElement => node instanceof HTMLScriptElement);
    },
    restore: () => spy.mockRestore(),
  };
}

describe('useDnsWidget CSP nonce (S5)', () => {
  afterEach(() => {
    delete window.apxDns;
    document.querySelectorAll('meta[name="csp-nonce"], script[nonce]').forEach((el) =>
      el.remove()
    );
    vi.restoreAllMocks();
  });

  /**
   * Render the shell's nonced entry script as a browser exposes it after
   * nonce hiding: the content attribute is emptied, the IDL property keeps
   * the value. jsdom implements neither, so both are set by hand.
   */
  function appendNoncedScript(nonce: string) {
    const nonced = document.createElement('script');
    nonced.setAttribute('nonce', '');
    Object.defineProperty(nonced, 'nonce', { value: nonce, configurable: true });
    document.head.appendChild(nonced);
    return nonced;
  }

  describe('resolveCspNonce', () => {
    // RISK-2026-08-14-M08: the bootstrap payload no longer carries the nonce,
    // and the resolver must not go looking for it there either. A payload
    // that still has one (older backend) is stripped by the schema; a value
    // smuggled onto the window is ignored.
    it('never reads the nonce from the bootstrap payload', () => {
      (window as unknown as { __BOOTSTRAP_ME__?: unknown }).__BOOTSTRAP_ME__ = {
        nonce: TEST_NONCE,
      };
      try {
        expect(resolveCspNonce()).toBeUndefined();
      } finally {
        delete (window as unknown as { __BOOTSTRAP_ME__?: unknown }).__BOOTSTRAP_ME__;
      }
    });

    // SEC-F8b: a meta's content is readable by injected markup, and no
    // template emits one, so it is never a nonce source.
    it('ignores a csp-nonce meta tag', () => {
      const meta = document.createElement('meta');
      meta.setAttribute('name', 'csp-nonce');
      meta.setAttribute('content', 'meta-nonce');
      document.head.appendChild(meta);

      expect(resolveCspNonce()).toBeUndefined();

      appendNoncedScript('script-nonce');
      expect(resolveCspNonce()).toBe('script-nonce');
    });

    it('reads the nonce IDL property when the content attribute is hidden', () => {
      appendNoncedScript('script-nonce');

      expect(document.querySelector('script[nonce]')!.getAttribute('nonce')).toBe('');
      expect(resolveCspNonce()).toBe('script-nonce');
    });

    it('returns undefined when no nonce is discoverable', () => {
      expect(resolveCspNonce()).toBeUndefined();
    });
  });

  describe('script injection', () => {
    beforeEach(() => {
      getGlobalAxiosMock()
        .onGet('/api/domains/dns-widget/token')
        .reply(200, {
          success: true,
          token: 'tok',
          api_url: 'https://apx.example',
          expires_in: 300,
        });
    });

    it('stamps the injected widget script with the nonce of the shell script', async () => {
      appendNoncedScript(TEST_NONCE);
      const injected = spyOnInjectedScript();
      const wrapper = mountWidgetHost();

      const { widget } = wrapper.vm as unknown as {
        widget: ReturnType<typeof useDnsWidget>;
      };
      const initPromise = widget.initWidget();

      const script = injected.getScript();
      expect(script).toBeDefined();
      expect(script!.getAttribute('nonce')).toBe(TEST_NONCE);

      // Complete the load so initWidget resolves cleanly
      script!.onload?.(new Event('load'));
      await expect(initPromise).resolves.toBe(true);
      expect(widget.error.value).toBeNull();

      wrapper.unmount();
    });

    it('injects the script without a nonce attribute when none is available (fallback)', async () => {
      const injected = spyOnInjectedScript();
      const wrapper = mountWidgetHost();

      const { widget } = wrapper.vm as unknown as {
        widget: ReturnType<typeof useDnsWidget>;
      };
      const initPromise = widget.initWidget();

      const script = injected.getScript();
      expect(script).toBeDefined();
      expect(script!.hasAttribute('nonce')).toBe(false);

      script!.onload?.(new Event('load'));
      await expect(initPromise).resolves.toBe(true);

      wrapper.unmount();
    });
  });

  // RISK-2026-08-14-M09: the patched widget renders remote HTML only through
  // window.apxDns.sanitizeHtml and falls back to text without it, so the
  // composable must install it before init renders anything.
  describe('HTML sanitizer installation (M09)', () => {
    beforeEach(() => {
      getGlobalAxiosMock()
        .onGet('/api/domains/dns-widget/token')
        .reply(200, {
          success: true,
          token: 'tok',
          api_url: 'https://apx.example',
          expires_in: 300,
        });
    });

    it('installs the sanitizer on window.apxDns before calling init', async () => {
      let sanitizerAtInit: unknown;
      // An already-loaded widget: loadAssets returns early.
      window.apxDns = {
        init: vi.fn(() => {
          sanitizerAtInit = window.apxDns?.sanitizeHtml;
        }),
        stop: vi.fn(),
        restart: vi.fn(),
      };
      const wrapper = mountWidgetHost();
      const { widget } = wrapper.vm as unknown as {
        widget: ReturnType<typeof useDnsWidget>;
      };

      await expect(widget.initWidget()).resolves.toBe(true);

      expect(window.apxDns.init).toHaveBeenCalledTimes(1);
      expect(sanitizerAtInit).toBe(sanitizeDnsWidgetHtml);

      wrapper.unmount();
    });
  });
});
