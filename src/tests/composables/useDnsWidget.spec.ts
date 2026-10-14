// src/tests/composables/useDnsWidget.spec.ts
//
// [S5] Verifies the DNS widget's dynamically injected <script> carries the
// per-request CSP nonce. The backend emits a nonce-only script-src (no
// 'strict-dynamic', no 'self'), so an un-nonced injected script is blocked
// by the browser.

import {
  resolveCspNonce,
  useDnsWidget,
  type UseDnsWidgetOptions,
} from '@/shared/composables/useDnsWidget';
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
function mountWidgetHost(options: Partial<UseDnsWidgetOptions> = {}) {
  const Host = defineComponent({
    setup(_, { expose }) {
      const widget = useDnsWidget({ dnsRecords: [], ...options });
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

// SEC-F11: the widget root id is fixed and window.apxDns is shared, so an
// init that resumes after its host unmounted, or after a later init on the
// same host, must abandon itself instead of taking over the live widget.
describe('superseded init (SEC-F11)', () => {
  type TokenReply = [number, Record<string, unknown>];
  let inits: Array<{ domain?: string; token: string }>;

  function tokenReply(token: string): TokenReply {
    return [200, { success: true, token, api_url: 'https://apx.example', expires_in: 300 }];
  }

  /** Queue one token response per call; each resolves when its test says so. */
  function deferTokens(count: number) {
    const resolvers: Array<(reply: TokenReply) => void> = [];
    const mock = getGlobalAxiosMock();
    for (let i = 0; i < count; i++) {
      const pending = new Promise<TokenReply>((resolve) => resolvers.push(resolve));
      mock.onGet('/api/domains/dns-widget/token').replyOnce(() => pending);
    }
    return resolvers;
  }

  async function settle() {
    for (let i = 0; i < 20; i++) await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));
  }

  function mountHost(options: Partial<UseDnsWidgetOptions> = {}) {
    const wrapper = mountWidgetHost(options);
    const { widget } = wrapper.vm as unknown as { widget: ReturnType<typeof useDnsWidget> };
    return { wrapper, widget };
  }

  function verifyEvent() {
    document.dispatchEvent(
      new CustomEvent('apx-dnswidget-records-completely-verified', { detail: [] })
    );
  }

  beforeEach(() => {
    getGlobalAxiosMock().reset();
    inits = [];
    // An already-loaded widget: loadAssets returns early.
    window.apxDns = {
      init: vi.fn((config) => {
        inits.push({ domain: config.domain, token: config.token });
      }),
      stop: vi.fn(),
      restart: vi.fn(),
    };
  });

  afterEach(() => {
    getGlobalAxiosMock().reset();
    delete window.apxDns;
    document.body.innerHTML = '';
    vi.restoreAllMocks();
  });

  it('an unmounted host whose token arrives late does not take over the next host', async () => {
    const [resolveA, resolveB] = deferTokens(2);
    const verifiedA = vi.fn();
    const verifiedB = vi.fn();

    const hostA = mountHost({ domain: 'a.example', onRecordsVerified: verifiedA });
    const initA = hostA.widget.initWidget();
    await settle();
    hostA.wrapper.unmount(); // navigated away while A's token was pending

    const hostB = mountHost({ domain: 'b.example', onRecordsVerified: verifiedB });
    const initB = hostB.widget.initWidget();
    await settle();
    resolveB(tokenReply('token-b'));
    await expect(initB).resolves.toBe(true);

    resolveA(tokenReply('token-a'));
    await expect(initA).resolves.toBe(false);

    expect(inits).toEqual([{ domain: 'b.example', token: 'token-b' }]);
    expect(hostA.widget.isInitialized.value).toBe(false);
    expect(hostA.widget.error.value).toBeNull();

    verifyEvent();
    expect(verifiedA).not.toHaveBeenCalled();
    expect(verifiedB).toHaveBeenCalledTimes(1);

    hostB.wrapper.unmount();
  });

  it.each([
    ['the later token first', [1, 0]],
    ['the earlier token first', [0, 1]],
  ])('back-to-back inits on one host: the later wins (%s)', async (_label, order) => {
    const resolvers = deferTokens(2);
    const verified = vi.fn();
    const { wrapper, widget } = mountHost({ domain: 'example.com', onRecordsVerified: verified });

    // The first init's token request is in flight when the second starts.
    const first = widget.initWidget();
    await settle();
    const second = widget.initWidget();
    await settle();
    expect(widget.isLoading.value).toBe(true);

    for (const [step, index] of order.entries()) {
      resolvers[index](tokenReply(`token-${index}`));
      await settle();
      if (step === 0 && index === 0) {
        // The superseded init finished first: nothing started, still loading.
        expect(inits).toEqual([]);
        expect(widget.isLoading.value).toBe(true);
      }
    }

    await expect(first).resolves.toBe(false);
    await expect(second).resolves.toBe(true);
    expect(inits).toEqual([{ domain: 'example.com', token: 'token-1' }]);
    expect(widget.isLoading.value).toBe(false);
    expect(widget.isInitialized.value).toBe(true);

    verifyEvent();
    expect(verified).toHaveBeenCalledTimes(1); // listeners registered once

    wrapper.unmount();
  });

  it("abandons a pending init on stop, as DnsWidget.vue's domain watch does", async () => {
    const [resolveOld, resolveNew] = deferTokens(2);
    const { wrapper, widget } = mountHost({ domain: 'example.com' });

    const pending = widget.initWidget();
    await settle();
    widget.stopWidget();
    const restarted = widget.initWidget();
    await settle();

    resolveOld(tokenReply('token-old'));
    resolveNew(tokenReply('token-new'));

    await expect(pending).resolves.toBe(false);
    await expect(restarted).resolves.toBe(true);
    expect(inits).toEqual([{ domain: 'example.com', token: 'token-new' }]);

    wrapper.unmount();
  });

  it('clears the loading state when a pending init is stopped', async () => {
    const [resolveToken] = deferTokens(1);
    const { wrapper, widget } = mountHost({ domain: 'example.com' });

    const pending = widget.initWidget();
    await settle();
    expect(widget.isLoading.value).toBe(true);
    widget.stopWidget();
    expect(widget.isLoading.value).toBe(false);

    resolveToken(tokenReply('token-late'));
    await expect(pending).resolves.toBe(false);
    expect(inits).toEqual([]);
    expect(widget.isLoading.value).toBe(false);

    wrapper.unmount();
  });
});
