// src/tests/assets/dnswidget.v1.spec.ts
//
// RISK-2026-08-14-M09: the vendored Approximated DNS widget, evaluated as
// shipped, renders hostile remote HTML and hostile API values without
// producing executable markup, keeps its controls working through delegated
// data-apxdns-action listeners, and fails closed (text, not HTML) when no
// sanitizer is installed.
//
// vitest's jsdom runs inline handlers (runScripts: 'dangerously'), so a
// surviving onclick would really execute. Handlers see jsdom's own window,
// not the test global, so the canary is a DOM write: data-pwned on <body>.

import widgetSource from '@/assets/approximated/dnswidget.v1.js?raw';
import { sanitizeDnsWidgetHtml } from '@/shared/utils/dnsWidgetHtml';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

interface ApxDnsUnderTest {
  init: (config: Record<string, unknown>) => void;
  stop: () => void;
  renderProviderInstructions: (data: unknown) => void;
  sanitizeHtml?: (html: string) => string;
  can_restart?: boolean;
  actionRoot?: Element | null;
  config?: unknown;
}

type TestWindow = Window & { apxDns?: ApxDnsUnderTest };
const testWindow = window as TestWindow;

const API_URL = 'https://apx.example';

const HOSTILE_STEP = `
  <div class="apxdns-instruction fixed inset-0" style="position:fixed" id="app">
    <script>document.body.dataset.pwned='script'</script>
    <img src="https://cdn.example/logo.png" onerror="document.body.dataset.pwned='img'">
    <a class="apxdns-provider-login-link" href="javascript:document.body.dataset.pwned='href'" target="_top">Log in</a>
    <iframe src="https://evil.example"></iframe>
    <form action="https://evil.example"><input name="password"></form>
    <button class="apxdns-text-btn" onclick="document.body.dataset.pwned='onclick'">Trap</button>
    <button class="apxdns-show-manual-instructions-btn"
      onclick="window.apxDns.showManualInstructions('manual-1')">Show manual steps</button>
    <div class="apxdns-hide" data-apxid="manual-1">
      <div class="apxdns-input-copy-container">
        <input type="text" readonly value="target.example.net">
        <button class="apxdns-copy-button"
          onclick="window.apxDns.copyInputText(this.previousElementSibling)">Copy</button>
      </div>
    </div>
    <a class="apxdns-btn-link" href="https://dns.example/apply" target="_blank">Apply</a>
  </div>`;

const HOSTILE_VERIFY_SECTION = `
  <div class="apxdns-verify-container">
    <div id="apxdnswidget-verify-section" class="apxdnswidget-verify-section"></div>
    <div class="apxdns-verify-btn-loader-container">
      <button class="apxdns-verify-btn" onclick="window.apxDns.verifyRecords()">Verify</button>
      <div class="apxdns-verify-loader apxdns-hide"><div class="loader"></div></div>
    </div>
    <svg onload="document.body.dataset.pwned='svg'"><path d="M0 0h24"/></svg>
  </div>`;

const PROVIDER_INSTRUCTIONS = {
  domain_results: { 'example.com': { steps: [{ html: HOSTILE_STEP }] } },
  verify_section: { html: HOSTILE_VERIFY_SECTION },
};

const PAYLOAD = `<img src=x onerror="document.body.dataset.pwned='api'">`;

const HOSTILE_VERIFY_RESPONSE = {
  records: [
    {
      apex: 'example',
      tld: `com${PAYLOAD}`,
      domain: 'example.com',
      host: '@',
      type: `cname${PAYLOAD}`,
      combined_host: PAYLOAD,
      value: `"><svg onload="document.body.dataset.pwned='value'">`,
      actual_values: `</textarea>${PAYLOAD}`,
      match: `"><img src=x onerror="document.body.dataset.pwned='match'">`,
    },
  ],
};

/** Let the widget's un-returned fetch().then(resp.json().then()) chains settle. */
async function settle() {
  for (let i = 0; i < 10; i++) await Promise.resolve();
}

function jsonResponse(body: unknown) {
  return Promise.resolve({ json: () => Promise.resolve(body) });
}

/** Evaluate the vendored widget source, as the injected <script> would. */
function loadWidget(): ApxDnsUnderTest {
  new Function(widgetSource)();
  return testWindow.apxDns!;
}

function widgetRoot(): HTMLElement {
  return document.getElementById('apxdnswidget')!;
}

function onAttributes(root: Element): string[] {
  return Array.from(root.querySelectorAll('*')).flatMap((el) =>
    Array.from(el.attributes)
      .map((attr) => attr.name.toLowerCase())
      .filter((name) => name.startsWith('on'))
  );
}

function expectNotPwned() {
  expect(document.body.hasAttribute('data-pwned')).toBe(false);
}

function expectNoExecutableMarkup(root: Element) {
  expect(root.querySelector('script, iframe, form, style, object, embed')).toBeNull();
  expect(onAttributes(root)).toEqual([]);
  for (const el of Array.from(root.querySelectorAll('[href], [src]'))) {
    const url = el.getAttribute('href') ?? el.getAttribute('src') ?? '';
    expect(url.trim().toLowerCase()).not.toMatch(/^(javascript|vbscript|data):/);
  }
}

describe('vendored DNS widget (M09)', () => {
  let fetchMock: ReturnType<typeof vi.fn>;
  let writeText: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['setTimeout'] }); // token renewal timer
    document.body.innerHTML = '<div id="apxdnswidget" class="apxdnswidget"></div>';
    document.body.removeAttribute('data-pwned');

    fetchMock = vi.fn((url: string) =>
      url.endsWith('/get-provider-instructions')
        ? jsonResponse(PROVIDER_INSTRUCTIONS)
        : jsonResponse(HOSTILE_VERIFY_RESPONSE)
    );
    vi.stubGlobal('fetch', fetchMock);

    writeText = vi.fn();
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText },
      configurable: true,
    });
  });

  afterEach(() => {
    // stop() reads config.widget_id, so the vendor code throws on a second call.
    if (testWindow.apxDns?.config) testWindow.apxDns.stop();
    delete testWindow.apxDns;
    document.body.innerHTML = '';
    document.body.removeAttribute('data-pwned');
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  async function initWithDomain(apx: ApxDnsUnderTest) {
    apx.init({
      token: 'tok',
      api_url: API_URL,
      widget_id: 'apxdnswidget',
      domain: 'example.com',
      dnsRecords: [{ type: 'CNAME', host: '@', value: 'target.example.net' }],
      verifyAutoScroll: false,
    });
    await settle();
  }

  describe('with the sanitizer installed', () => {
    let apx: ApxDnsUnderTest;

    beforeEach(async () => {
      apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      await initWithDomain(apx);
    });

    it('renders hostile instructions and verify section without executable markup', () => {
      const root = widgetRoot();
      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/get-provider-instructions`,
        expect.anything()
      );
      expectNoExecutableMarkup(root);
      expect(root.querySelector('#app')).toBeNull();
      expect(root.querySelector('.fixed, [style]')).toBeNull();

      // Inline handlers that are not widget calls are gone: clicking is inert.
      root.querySelector<HTMLButtonElement>('.apxdns-text-btn')!.click();
      expectNotPwned();
    });

    it('keeps the legitimate controls and links', () => {
      const root = widgetRoot();
      expect(root.querySelector('[data-apxdns-action="verifyRecords"]')).not.toBeNull();
      expect(
        root.querySelector('[data-apxdns-action="showManualInstructions"][data-apxdns-arg="manual-1"]')
      ).not.toBeNull();
      expect(root.querySelector('[data-apxdns-action="copyInputText"]')).not.toBeNull();
      expect(root.querySelector('#apxdnswidget-verify-section')).not.toBeNull();

      const apply = root.querySelector<HTMLAnchorElement>('a.apxdns-btn-link')!;
      expect(apply.getAttribute('href')).toBe('https://dns.example/apply');
      expect(apply.getAttribute('target')).toBe('_blank');
      expect(apply.getAttribute('rel')).toBe('noopener noreferrer');
    });

    it('toggles manual instructions through the delegated listener', () => {
      const root = widgetRoot();
      const panel = root.querySelector('[data-apxid="manual-1"]')!;
      expect(panel.classList.contains('apxdns-hide')).toBe(true);

      root.querySelector<HTMLElement>('[data-apxdns-action="showManualInstructions"]')!.click();
      expect(panel.classList.contains('apxdns-hide')).toBe(false);
    });

    it('copies the adjacent field through the delegated listener', () => {
      widgetRoot().querySelector<HTMLElement>('[data-apxdns-action="copyInputText"]')!.click();
      expect(writeText).toHaveBeenCalledWith('target.example.net');
    });

    it('verifies records and renders hostile API values as text', async () => {
      widgetRoot().querySelector<HTMLElement>('[data-apxdns-action="verifyRecords"]')!.click();
      await settle();

      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/token/check-records-match-exactly`,
        expect.anything()
      );
      const section = document.getElementById('apxdnswidget-verify-section')!;
      expectNoExecutableMarkup(section);
      expect(section.querySelector('img, svg')).toBeNull();
      expect(section.querySelector('.apxdns-verify-record-is-false')).not.toBeNull();
      expect(section.textContent).toContain(PAYLOAD);
      expect(section.querySelector('textarea')!.value).toBe(`</textarea>${PAYLOAD}`);
      expectNotPwned();
    });

    it('removes its delegated listeners on stop', () => {
      const root = widgetRoot();
      apx.stop();
      expect(apx.actionRoot).toBeNull();

      root.innerHTML = '<div class="apxdns-copy-button" data-apxdns-action="copyInputText"></div>';
      root.querySelector<HTMLElement>('div')!.click();
      expect(writeText).not.toHaveBeenCalled();
    });

    /** Re-render the widget with one instruction step. */
    function renderStep(html: string) {
      apx.renderProviderInstructions({
        domain_results: { 'example.com': { steps: [{ html }] } },
        verify_section: { html: '<div id="apxdnswidget-verify-section"></div>' },
      });
    }

    // SEC-F7: the vendor copied this.previousElementSibling; a hidden first
    // input in the same container must not be what lands on the clipboard.
    it('copies the input just before the button, not the first in its container', () => {
      renderStep(`
        <div class="apxdns-input-copy-container">
          <input class="apxdns-hide" value="attacker.example">
          <input value="target.example.net">
          <button class="apxdns-copy-button"
            onclick="window.apxDns.copyInputText(this.previousElementSibling)">Copy</button>
        </div>`);

      widgetRoot().querySelector<HTMLElement>('[data-apxdns-action="copyInputText"]')!.click();

      expect(writeText).toHaveBeenCalledTimes(1);
      expect(writeText).toHaveBeenCalledWith('target.example.net');
    });

    it("falls back to the container's input when the button does not follow one", () => {
      renderStep(`
        <div class="apxdns-input-copy-container">
          <input value="target.example.net">
          <span>record value</span>
          <button class="apxdns-copy-button"
            onclick="window.apxDns.copyInputText(this.previousElementSibling)">Copy</button>
        </div>`);

      widgetRoot().querySelector<HTMLElement>('[data-apxdns-action="copyInputText"]')!.click();

      expect(writeText).toHaveBeenCalledWith('target.example.net');
    });

    // SEC-F1: a remote <label for> must not click an app control by id.
    it('does not let remote markup click an app control outside the widget', () => {
      const appControl = document.createElement('button');
      appControl.id = 'app-danger';
      document.body.prepend(appControl);
      const appClicks = vi.fn();
      appControl.addEventListener('click', appClicks);

      renderStep(
        '<label for="app-danger" class="apxdns-show-manual-instructions-btn">Show</label>'
      );
      const label = widgetRoot().querySelector<HTMLLabelElement>('label')!;
      expect(label.hasAttribute('for')).toBe(false);
      label.click();

      expect(appClicks).not.toHaveBeenCalled();
    });
  });

  describe('without a sanitizer (fail closed)', () => {
    it('inserts remote HTML as text', async () => {
      const apx = loadWidget();
      expect(apx.sanitizeHtml).toBeUndefined();
      await initWithDomain(apx);

      const root = widgetRoot();
      expect(root.children).toHaveLength(0);
      expect(root.querySelector('img, button, a, svg')).toBeNull();
      expect(root.textContent).toContain('<script>');
      expect(root.textContent).toContain('onclick="window.apxDns.verifyRecords()"');
      expectNotPwned();
    });
  });

  describe("the widget's own templates", () => {
    it('escapes prefillDomain and submits the form without an inline handler', async () => {
      const apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      const prefill = `"><img src=x onerror="document.body.dataset.pwned='prefill'">`;
      apx.init({
        token: 'tok',
        api_url: API_URL,
        widget_id: 'apxdnswidget',
        prefillDomain: prefill,
        dnsRecords: [{ type: 'CNAME', host: '@', value: 'target.example.net' }],
        verifyAutoScroll: false,
      });

      const root = widgetRoot();
      const form = root.querySelector('form')!;
      expect(form.getAttribute('data-apxdns-action')).toBe('submitDomain');
      expect(onAttributes(root)).toEqual([]);
      expect(root.querySelector('img')).toBeNull();
      const input = root.querySelector<HTMLInputElement>('input[name="apxdns-domain-input"]')!;
      expect(input.value).toBe(prefill);

      const submitted = vi.fn();
      document.addEventListener('apx-dnswidget-user-submitted-domain', submitted);
      input.value = 'example.com';
      form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
      document.removeEventListener('apx-dnswidget-user-submitted-domain', submitted);
      await settle();

      expect(submitted).toHaveBeenCalledTimes(1);
      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/get-provider-instructions`,
        expect.anything()
      );
      expectNotPwned();
    });

    it('restarts through the delegated listener', async () => {
      const apx = loadWidget();
      apx.sanitizeHtml = sanitizeDnsWidgetHtml;
      await initWithDomain(apx);
      apx.can_restart = true;
      apx.renderProviderInstructions(PROVIDER_INSTRUCTIONS);

      const restart = widgetRoot().querySelector<HTMLElement>('[data-apxdns-action="restart"]')!;
      expect(restart.hasAttribute('onclick')).toBe(false);
      restart.click();

      expect(widgetRoot().querySelector('form[data-apxdns-action="submitDomain"]')).not.toBeNull();
    });
  });
});
