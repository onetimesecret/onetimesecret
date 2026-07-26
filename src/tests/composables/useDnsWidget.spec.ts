// src/tests/composables/useDnsWidget.spec.ts
//
// [S5] Verifies the DNS widget's dynamically injected <script> carries the
// per-request CSP nonce. The backend emits a nonce-only script-src (no
// 'strict-dynamic', no 'self'), so an un-nonced injected script is blocked
// by the browser.

import { resolveCspNonce, useDnsWidget } from '@/shared/composables/useDnsWidget';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { getGlobalAxiosMock } from '@/tests/setup-stores';
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
  return mount(Host, { attachTo: document.body });
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

  describe('resolveCspNonce', () => {
    it('returns the nonce from the bootstrap store', () => {
      useBootstrapStore().$patch({ nonce: TEST_NONCE });
      expect(resolveCspNonce()).toBe(TEST_NONCE);
    });

    it('falls back to a csp-nonce meta tag when the store has none', () => {
      const meta = document.createElement('meta');
      meta.setAttribute('name', 'csp-nonce');
      meta.setAttribute('content', 'meta-nonce');
      document.head.appendChild(meta);

      expect(resolveCspNonce()).toBe('meta-nonce');
    });

    it('falls back to the nonce of an existing nonced script element', () => {
      const nonced = document.createElement('script');
      nonced.setAttribute('nonce', 'script-nonce');
      document.head.appendChild(nonced);

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

    it('stamps the injected widget script with the resolved nonce', async () => {
      useBootstrapStore().$patch({ nonce: TEST_NONCE });
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
});
