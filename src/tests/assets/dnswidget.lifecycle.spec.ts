// src/tests/assets/dnswidget.lifecycle.spec.ts
//
// RISK-2026-08-14-M09 (QA): lifecycle and dispatch edges of the patched
// Approximated DNS widget that dnswidget.v1.spec.ts does not cover:
// - stop() then init() on a new root element rebinds the delegated listener
//   to the new root and releases the old one;
// - the useDnsWidget composable installs the sanitizer and the listener is
//   released when the host unmounts;
// - insertHtml fails closed when the sanitizer throws (no raw fallback);
// - action anchors cancel navigation, ordinary links do not;
// - action names the dispatcher does not know, and submitDomain outside a
//   form, invoke nothing;
// - showManualInstructions only toggles inside the widget root and treats
//   its argument as a value, not a selector;
// - copy finds its field in the copy container wherever the button sits.

import widgetSource from '@/assets/approximated/dnswidget.v1.js?raw';
import { useDnsWidget, type UseDnsWidgetOptions } from '@/shared/composables/useDnsWidget';
import { sanitizeDnsWidgetHtml } from '@/shared/utils/dnsWidgetHtml';
import { getGlobalAxiosMock } from '@/tests/setup-stores';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';

interface ApxDnsUnderTest {
  init: (config: Record<string, unknown>) => void;
  stop: () => void;
  restart: () => void;
  verifyRecords: () => void;
  copyInputText: (el: Element) => void;
  submitDomain: (form: HTMLFormElement) => boolean;
  insertHtml: (el: Element, html: string) => void;
  showManualInstructions: (id: string) => void;
  renderProviderInstructions: (data: unknown) => void;
  sanitizeHtml?: (html: string) => string;
  actionRoot?: Element | null;
  config?: unknown;
  renewTimer?: unknown;
}

type TestWindow = Window & { apxDns?: ApxDnsUnderTest };
const testWindow = window as TestWindow;

const WIDGET_ID = 'apxdnswidget';

function loadWidget(): ApxDnsUnderTest {
  new Function(widgetSource)();
  return testWindow.apxDns!;
}

function setRoot(): HTMLElement {
  const root = document.createElement('div');
  root.id = WIDGET_ID;
  root.className = 'apxdnswidget';
  document.body.appendChild(root);
  return root;
}

function baseConfig(extra: Record<string, unknown> = {}) {
  return {
    token: 'tok',
    api_url: 'https://apx.example',
    widget_id: WIDGET_ID,
    dnsRecords: [{ type: 'CNAME', host: '@', value: 'target.example.net' }],
    verifyAutoScroll: false,
    ...extra,
  };
}

/** Insert remote-shaped markup through the widget's sanitizing path. */
function renderRemote(apx: ApxDnsUnderTest, root: HTMLElement, html: string) {
  root.innerHTML = '';
  apx.insertHtml(root, html);
}

/** Let the widget's un-returned fetch().then(resp.json().then()) chains settle. */
async function settle() {
  for (let i = 0; i < 10; i++) await Promise.resolve();
}

function click(el: Element): MouseEvent {
  const event = new MouseEvent('click', { bubbles: true, cancelable: true });
  el.dispatchEvent(event);
  return event;
}

describe('vendored DNS widget lifecycle and dispatch (M09, QA)', () => {
  let writeText: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout'] }); // token renewal timer
    document.body.innerHTML = '';
    vi.stubGlobal(
      'fetch',
      vi.fn(() =>
        Promise.resolve({
          json: () => Promise.resolve({ domain_results: {}, verify_section: { html: '' } }),
        })
      )
    );
    writeText = vi.fn();
    Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
  });

  afterEach(() => {
    delete testWindow.apxDns;
    document.body.innerHTML = '';
    vi.unstubAllGlobals();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  describe('stop() and re-init', () => {
    it('rebinds the delegated listener to a new root and releases the old one', () => {
      const apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      const oldRoot = setRoot();
      apx.init(baseConfig());
      expect(apx.actionRoot).toBe(oldRoot);

      apx.stop();
      expect(apx.actionRoot).toBeNull();
      oldRoot.remove();

      const newRoot = setRoot();
      apx.init(baseConfig());
      expect(apx.actionRoot).toBe(newRoot);

      const restart = vi.spyOn(apx, 'restart');
      // The detached old root no longer dispatches...
      oldRoot.innerHTML = '<button data-apxdns-action="restart">old</button>';
      click(oldRoot.querySelector('button')!);
      expect(restart).not.toHaveBeenCalled();

      // ...the new one does.
      renderRemote(apx, newRoot, '<button class="apxdns-text-btn" onclick="window.apxDns.restart()">x</button>');
      click(newRoot.querySelector('button')!);
      expect(restart).toHaveBeenCalledTimes(1);
    });

    // QA-F3: stop() must tolerate a root that is already gone, and a second call.
    it('stops cleanly when the root was removed first, and twice', () => {
      const apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      const root = setRoot();
      apx.init(baseConfig());
      root.remove();

      expect(() => apx.stop()).not.toThrow();
      expect(() => apx.stop()).not.toThrow();
      expect(apx.actionRoot).toBeNull();
      expect(apx.config).toBeNull();
    });

    it('drops a verify response that arrives after stop', async () => {
      const pending: Array<(value: unknown) => void> = [];
      vi.stubGlobal('fetch', vi.fn(() => new Promise((resolve) => pending.push(resolve))));
      const apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      const root = setRoot();
      apx.init(baseConfig({ domain: 'example.com' }));
      renderRemote(
        apx,
        root,
        '<div id="apxdnswidget-verify-section"></div>' +
          '<button class="apxdns-verify-btn">Verify</button>' +
          '<div class="apxdns-verify-loader apxdns-hide"></div>'
      );
      const verified = vi.fn();
      document.addEventListener('apx-dnswidget-records-failed-verification', verified);
      apx.verifyRecords();
      apx.stop();

      // pending[0] is the instructions request from init, pending[1] the verify.
      for (const resolve of pending) {
        resolve({ json: () => Promise.resolve({ records: [{ match: false }] }) });
      }
      await settle();
      document.removeEventListener('apx-dnswidget-records-failed-verification', verified);

      expect(verified).not.toHaveBeenCalled();
      expect(root.innerHTML).toBe('');
    });

    it('does not render a stale response into the root of a later init', async () => {
      const pending: Array<(value: unknown) => void> = [];
      vi.stubGlobal('fetch', vi.fn(() => new Promise((resolve) => pending.push(resolve))));
      const apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      const root = setRoot();
      apx.init(baseConfig({ domain: 'old.example' }));
      apx.stop();
      apx.init(baseConfig({ domain: 'new.example' }));

      const instructions = (text: string) => ({
        json: () =>
          Promise.resolve({
            domain_results: { d: { steps: [{ html: `<p class="apxdns-inst-body">${text}</p>` }] } },
            verify_section: { html: '' },
          }),
      });
      pending[0](instructions('stale'));
      await settle();
      expect(root.textContent).not.toContain('stale');

      pending[1](instructions('current'));
      await settle();
      expect(root.textContent).toContain('current');
    });

    it('does not stack listeners when init runs twice on the same root', () => {
      const apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      const root = setRoot();
      apx.init(baseConfig());
      apx.init(baseConfig());

      const verify = vi.spyOn(apx, 'verifyRecords').mockImplementation(() => {});
      renderRemote(apx, root, '<button class="apxdns-verify-btn" onclick="window.apxDns.verifyRecords()">Verify</button>');
      click(root.querySelector('button')!);

      expect(verify).toHaveBeenCalledTimes(1);
    });
  });

  describe('useDnsWidget host lifecycle', () => {
    beforeEach(() => {
      getGlobalAxiosMock()
        .onGet('/api/domains/dns-widget/token')
        .reply(200, { success: true, token: 'tok', api_url: 'https://apx.example', expires_in: 300 });
    });

    function mountHost(options: Partial<UseDnsWidgetOptions> = {}) {
      const Host = defineComponent({
        setup(_, { expose }) {
          const widget = useDnsWidget({ dnsRecords: [], domain: 'example.com', ...options });
          expose({ widget });
          return () => h('div', { id: WIDGET_ID, class: 'apxdnswidget' });
        },
      });
      const errors: unknown[] = [];
      const wrapper = mount(Host, {
        attachTo: document.body,
        global: {
          plugins: [createTestI18n()],
          // Collect errors raised during unmount (the vendored stop() used to
          // throw on its detached root) so a test can assert there are none.
          config: { errorHandler: (err: unknown) => void errors.push(err) },
        },
      });
      const { widget } = wrapper.vm as unknown as { widget: ReturnType<typeof useDnsWidget> };
      return { wrapper, widget, errors };
    }

    it('installs the sanitizer and binds the listener to the host root', async () => {
      const apx = loadWidget();
      const { wrapper, widget } = mountHost();

      await expect(widget.initWidget()).resolves.toBe(true);
      await settle();

      expect(apx.sanitizeHtml).toBe(sanitizeDnsWidgetHtml);
      expect(apx.actionRoot).toBe(document.getElementById(WIDGET_ID));
      wrapper.unmount();
    });

    it('releases the delegated listener when the host unmounts', async () => {
      const apx = loadWidget();
      const { wrapper, widget } = mountHost();
      await widget.initWidget();
      await settle();
      const root = document.getElementById(WIDGET_ID)!;

      wrapper.unmount();

      expect(apx.actionRoot).toBeNull();
      const restart = vi.spyOn(apx, 'restart');
      root.innerHTML = '<button data-apxdns-action="restart">x</button>';
      click(root.querySelector('button')!);
      expect(restart).not.toHaveBeenCalled();
    });

    // QA-F3: onUnmounted runs after the root is detached. The vendored stop()
    // used to throw there, so stopWidget skipped its own cleanup.
    it('removes its document listeners and stops token renewal on unmount', async () => {
      const apx = loadWidget();
      const onRecordsVerified = vi.fn();
      const { wrapper, widget, errors } = mountHost({ onRecordsVerified });
      await widget.initWidget();
      await settle();
      expect(widget.isInitialized.value).toBe(true);

      wrapper.unmount();

      expect(errors).toEqual([]);
      expect(widget.isInitialized.value).toBe(false);
      expect(apx.config).toBeNull();
      expect(apx.renewTimer).toBeNull();

      document.dispatchEvent(
        new CustomEvent('apx-dnswidget-records-completely-verified', { detail: [] })
      );
      expect(onRecordsVerified).not.toHaveBeenCalled();

      const fetchMock = vi.mocked(fetch);
      fetchMock.mockClear();
      vi.advanceTimersByTime(300_000);
      await settle();
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it('ignores a provider-instructions response that arrives after unmount', async () => {
      let resolveInstructions!: (value: unknown) => void;
      vi.stubGlobal(
        'fetch',
        vi.fn(() => new Promise((resolve) => (resolveInstructions = resolve)))
      );
      const apx = loadWidget();
      const render = vi.spyOn(apx, 'renderProviderInstructions');
      const { wrapper, widget, errors } = mountHost();
      await widget.initWidget();
      await settle();
      expect(fetch).toHaveBeenCalledWith(
        'https://apx.example/get-provider-instructions',
        expect.anything()
      );

      wrapper.unmount();
      resolveInstructions({
        json: () =>
          Promise.resolve({
            domain_results: { 'example.com': { steps: [{ html: '<p>late</p>' }] } },
            verify_section: { html: '' },
          }),
      });
      await settle();

      expect(errors).toEqual([]);
      expect(render).not.toHaveBeenCalled();
      // A direct call after stop is a no-op too.
      expect(() =>
        apx.renderProviderInstructions({ domain_results: {}, verify_section: { html: '' } })
      ).not.toThrow();
    });
  });

  describe('insertHtml', () => {
    it('inserts nothing when the sanitizer throws (no raw fallback)', () => {
      const apx = loadWidget();
      apx.sanitizeHtml = () => {
        throw new Error('sanitizer failed');
      };
      const root = setRoot();

      expect(() =>
        apx.insertHtml(root, '<img src="x" onerror="document.body.dataset.pwned=1">')
      ).toThrow('sanitizer failed');
      expect(root.innerHTML).toBe('');
      expect(document.body.hasAttribute('data-pwned')).toBe(false);
    });
  });

  describe('delegated dispatch', () => {
    let apx: ApxDnsUnderTest;
    let root: HTMLElement;

    beforeEach(() => {
      apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      root = setRoot();
      apx.init(baseConfig());
    });

    afterEach(() => {
      if (apx.config) apx.stop();
    });

    it('cancels navigation for action anchors but not for ordinary links', () => {
      renderRemote(
        apx,
        root,
        `<a class="apxdns-show-manual-instructions-btn" href="javascript:void(0)"
            onclick="window.apxDns.showManualInstructions('manual-1')">Show</a>
         <div class="apxdns-hide" data-apxid="manual-1">steps</div>
         <a class="apxdns-provider-login-link" href="https://dns.example/login" target="_blank">Log in</a>`
      );

      const action = root.querySelector('a.apxdns-show-manual-instructions-btn')!;
      expect(click(action).defaultPrevented).toBe(true);
      expect(root.querySelector('[data-apxid="manual-1"]')!.classList.contains('apxdns-hide')).toBe(
        false
      );

      const login = root.querySelector('a.apxdns-provider-login-link')!;
      expect(click(login).defaultPrevented).toBe(false);
    });

    it('invokes nothing for unknown actions or submitDomain outside a form', () => {
      const spies = ['restart', 'verifyRecords', 'showManualInstructions', 'copyInputText', 'submitDomain', 'stop'].map(
        (name) => vi.spyOn(apx, name as keyof ApxDnsUnderTest as 'restart')
      );
      // Remote markup may carry data-* attributes directly (DOMPurify keeps them).
      renderRemote(
        apx,
        root,
        `<button data-apxdns-action="stop">a</button>
         <button data-apxdns-action="setDomain">b</button>
         <button data-apxdns-action="submitDomain" type="submit">c</button>`
      );

      for (const button of Array.from(root.querySelectorAll('button'))) click(button);

      for (const spy of spies) expect(spy).not.toHaveBeenCalled();
      expect(apx.actionRoot).toBe(root);
    });

    it('toggles only the matching panel inside the widget root', () => {
      const outside = document.createElement('div');
      outside.setAttribute('data-apxid', 'manual-1');
      outside.className = 'apxdns-hide';
      document.body.appendChild(outside);
      renderRemote(apx, root, '<div class="apxdns-hide" data-apxid="manual-1">steps</div>');

      apx.showManualInstructions('manual-1');

      expect(root.querySelector('[data-apxid]')!.classList.contains('apxdns-hide')).toBe(false);
      expect(outside.classList.contains('apxdns-hide')).toBe(true);
    });

    it('treats the manual-instructions id as a value, not a selector', () => {
      renderRemote(apx, root, '<div class="apxdns-hide" data-apxid="manual-1">steps</div>');

      expect(() => apx.showManualInstructions("x'], [data-apxid='manual-1")).not.toThrow();
      expect(root.querySelector('[data-apxid]')!.classList.contains('apxdns-hide')).toBe(true);
    });

    it.each([
      [
        'button after the field',
        `<div class="apxdns-input-copy-container"><input type="text" readonly value="v1.example.net">
           <button class="apxdns-copy-button" onclick="window.apxDns.copyInputText(this.previousElementSibling)">Copy</button></div>`,
        'v1.example.net',
      ],
      [
        'button before the field',
        `<div class="apxdns-input-copy-container">
           <button class="apxdns-copy-button" onclick="window.apxDns.copyInputText(this.nextElementSibling)">Copy</button>
           <input type="text" readonly value="v2.example.net"></div>`,
        'v2.example.net',
      ],
      [
        'textarea field',
        `<div class="apxdns-input-copy-container"><textarea readonly>v=spf1 include:example.net ~all</textarea>
           <button class="apxdns-copy-button" onclick="window.apxDns.copyInputText(this.parentElement.querySelector('textarea'))">Copy</button></div>`,
        'v=spf1 include:example.net ~all',
      ],
      [
        'adjacent field without a container',
        `<div><input type="text" readonly value="v4.example.net"><button class="apxdns-copy-button"
           onclick="window.apxDns.copyInputText(this.previousElementSibling)">Copy</button></div>`,
        'v4.example.net',
      ],
    ])('copies the field for a %s', (_label, html, expected) => {
      renderRemote(apx, root, html);

      click(root.querySelector('[data-apxdns-action="copyInputText"]')!);

      expect(writeText).toHaveBeenCalledWith(expected);
    });
  });
});
