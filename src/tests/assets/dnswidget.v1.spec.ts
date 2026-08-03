// src/tests/assets/dnswidget.v1.spec.ts
//
// [M-4] Coverage for the vendored Approximated DNS widget hardening:
// - API-supplied HTML (instruction steps, verify section) is sanitized
//   before DOM insertion: script/iframe removed, event-handler attributes
//   stripped, javascript: URIs blocked.
// - Known-trusted inline onclick patterns are converted to real event
//   listeners so the widget stays functional without inline handlers.
// - Selector interpolations (data-apxid, widget_id) are CSS-escaped.
// - API-derived values in the verify templates are HTML-escaped.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import '@/assets/approximated/dnswidget.v1.js';

interface ApxDnsRecordFixture {
  apex: string;
  tld: string;
  domain: string;
  host: string;
  value: string;
  type: string;
}

interface ApxDnsWidget {
  config: {
    widget_id: string;
    api_url?: string;
    token?: string;
    prefillDomain?: string;
    verifyAutoScroll?: boolean;
    dnsRecords?: ApxDnsRecordFixture[];
  } | null;
  can_restart?: boolean;
  temp_records?: ApxDnsRecordFixture[] | null;
  escapeHtml: (value: unknown) => string;
  _cssEscape: (value: unknown) => string;
  _compileTrustedHandler: (value: unknown) => (() => void) | null;
  _resolveElementChain: (start: Element, expr: string) => Element | null;
  sanitizeHtmlToFragment: (html: unknown) => DocumentFragment;
  insertSanitizedHtml: (parent: Element, html: unknown) => void;
  renderProviderInstructions: (data: unknown) => void;
  showEnterDomain: () => void;
  showManualInstructions: (id: string) => void;
  verifyRecords: () => void;
  copyInputText: (el: HTMLInputElement) => void;
}

declare global {
  interface Window {
    __apx_pwned?: boolean;
  }
}

const apxDns = (): ApxDnsWidget =>
  (window as unknown as { apxDns: ApxDnsWidget }).apxDns;

describe('dnswidget.v1 sanitization [M-4]', () => {
  let widget: HTMLDivElement;

  beforeEach(() => {
    document.body.innerHTML = '';
    widget = document.createElement('div');
    widget.id = 'apxdnswidget';
    document.body.appendChild(widget);
    apxDns().config = { widget_id: 'apxdnswidget' };
    apxDns().can_restart = false;
    delete window.__apx_pwned;
  });

  afterEach(() => {
    apxDns().config = null;
    vi.restoreAllMocks();
  });

  describe('sanitizeHtmlToFragment', () => {
    it('removes script elements entirely', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<div class="apxdns-instruction"><script>window.__apx_pwned = true</' +
          'script><p>Step one</p></div>'
      );
      widget.appendChild(frag);

      expect(widget.querySelector('script')).toBeNull();
      expect(widget.querySelector('p')?.textContent).toBe('Step one');
      expect(window.__apx_pwned).toBeUndefined();
    });

    it('removes iframe/object/style elements and their subtrees', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<div><iframe src="https://evil.example"></iframe>' +
          '<object data="x"></object><style>*{display:none}</style>ok</div>'
      );
      widget.appendChild(frag);

      expect(widget.querySelector('iframe')).toBeNull();
      expect(widget.querySelector('object')).toBeNull();
      expect(widget.querySelector('style')).toBeNull();
      expect(widget.textContent).toContain('ok');
    });

    it('strips unknown event-handler attributes', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<img src="https://cdn.example/logo.png" onerror="window.__apx_pwned = true">' +
          '<button onclick="window.__apx_pwned = true" onmouseover="window.__apx_pwned = true">x</button>'
      );
      widget.appendChild(frag);

      const img = widget.querySelector('img');
      const button = widget.querySelector('button');
      expect(img?.getAttribute('onerror')).toBeNull();
      expect(button?.getAttribute('onclick')).toBeNull();
      expect(button?.getAttribute('onmouseover')).toBeNull();

      button?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      expect(window.__apx_pwned).toBeUndefined();
    });

    it('blocks javascript: URIs, including whitespace-smuggled schemes', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<a href="javascript:alert(1)">bad</a>' +
          '<a href="java\nscript:alert(1)">smuggled</a>' +
          '<a href="https://approximated.app/help">good</a>' +
          '<a href="/relative/path">relative</a>'
      );
      widget.appendChild(frag);

      const anchors = widget.querySelectorAll('a');
      expect(anchors[0].getAttribute('href')).toBeNull();
      expect(anchors[1].getAttribute('href')).toBeNull();
      expect(anchors[2].getAttribute('href')).toBe('https://approximated.app/help');
      expect(anchors[3].getAttribute('href')).toBe('/relative/path');
    });

    it('neutralizes form-submission primitives in API fragments', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<form action="https://evil.example/harvest" method="post" class="apxdns-form">' +
          '<input type="password" name="password" form="outer-form">' +
          '<button type="submit" formaction="https://evil.example/alt">Login</button>' +
          '</form>'
      );
      widget.appendChild(frag);

      // The FORM element itself must not survive, nor any submission target.
      expect(widget.querySelector('form')).toBeNull();
      expect(widget.querySelector('[action]')).toBeNull();
      expect(widget.querySelector('[formaction]')).toBeNull();

      // Children survive (unwrapped) but are inert: no form association via
      // ancestor or the `form` content attribute.
      const input = widget.querySelector('input');
      expect(input).not.toBeNull();
      expect(input?.getAttribute('form')).toBeNull();
      expect(input?.form).toBeNull();
      expect(widget.querySelector('button')?.textContent).toBe('Login');
    });

    it('strips action even on non-form elements', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<div action="https://evil.example">x</div>'
      );
      widget.appendChild(frag);
      expect(widget.querySelector('[action]')).toBeNull();
    });

    it('rejects protocol-relative URLs on href and src', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<a href="//evil.example/phish">pr</a>' +
          '<a href="/\\evil.example">backslash</a>' +
          '<a href="\\\\evil.example">unc</a>' +
          '<img src="//evil.example/x.png">' +
          '<a href="/ok/path">fine</a>'
      );
      widget.appendChild(frag);

      const anchors = widget.querySelectorAll('a');
      expect(anchors[0].getAttribute('href')).toBeNull();
      expect(anchors[1].getAttribute('href')).toBeNull();
      expect(anchors[2].getAttribute('href')).toBeNull();
      expect(widget.querySelector('img')?.getAttribute('src')).toBeNull();
      expect(anchors[3].getAttribute('href')).toBe('/ok/path');
    });

    it('hardens target=_blank anchors and drops other targets', () => {
      const frag = apxDns().sanitizeHtmlToFragment(
        '<a href="https://provider.example" target="_blank">login</a>' +
          '<a href="https://provider.example" target="parentFrame">retarget</a>'
      );
      widget.appendChild(frag);

      const anchors = widget.querySelectorAll('a');
      expect(anchors[0].getAttribute('rel')).toBe('noopener noreferrer');
      expect(anchors[1].getAttribute('target')).toBeNull();
    });

    it('preserves benign widget markup and attributes', () => {
      const html = `
        <div class="apxdns-instruction">
          <div class="apxdns-inst-heading">
            <img class="apxdns-inst-provider-logo" src="https://cdn.example/p.png" alt="Provider">
            Update records
          </div>
          <div class="apxdns-inst-body">
            <ol class="apxdns-inst-numbered-substeps">
              <li class="apxdns-inst-numbered-substep">Log in</li>
            </ol>
            <div class="apxdns-input-copy-container">
              <input type="text" readonly value="76.76.21.21">
              <button class="apxdns-copy-button" type="button">Copy</button>
            </div>
            <div data-apxid="manual-1" class="apxdns-hide">Manual steps</div>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path stroke-linecap="round" d="M9 15 3 9"></path>
            </svg>
          </div>
        </div>`;
      widget.appendChild(apxDns().sanitizeHtmlToFragment(html));

      expect(widget.querySelector('.apxdns-instruction')).not.toBeNull();
      expect(widget.querySelector('img')?.getAttribute('src')).toBe(
        'https://cdn.example/p.png'
      );
      expect(widget.querySelector('ol.apxdns-inst-numbered-substeps li')).not.toBeNull();
      expect(widget.querySelector('input')?.getAttribute('value')).toBe('76.76.21.21');
      expect(widget.querySelector('[data-apxid="manual-1"]')).not.toBeNull();
      expect(widget.querySelector('svg path')?.getAttribute('d')).toBe('M9 15 3 9');
    });
  });

  describe('trusted onclick conversion', () => {
    it('binds window.apxDns.verifyRecords() onclick as a real listener', () => {
      const verifySpy = vi.fn();
      const original = apxDns().verifyRecords;
      apxDns().verifyRecords = verifySpy;
      try {
        apxDns().insertSanitizedHtml(
          widget,
          '<button class="apxdns-verify-btn" onclick="window.apxDns.verifyRecords()">Verify</button>'
        );
        const button = widget.querySelector('button');
        expect(button?.getAttribute('onclick')).toBeNull();

        button?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        expect(verifySpy).toHaveBeenCalledTimes(1);
      } finally {
        apxDns().verifyRecords = original;
      }
    });

    it('binds showManualInstructions with its literal argument', () => {
      const manualSpy = vi.fn();
      const original = apxDns().showManualInstructions;
      apxDns().showManualInstructions = manualSpy;
      try {
        apxDns().insertSanitizedHtml(
          widget,
          `<button onclick="window.apxDns.showManualInstructions('manual-1')">Manual</button>`
        );
        widget.querySelector('button')?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        expect(manualSpy).toHaveBeenCalledWith('manual-1');
      } finally {
        apxDns().showManualInstructions = original;
      }
    });

    it('resolves copyInputText element chains without eval', () => {
      const copySpy = vi.fn();
      const original = apxDns().copyInputText;
      apxDns().copyInputText = copySpy;
      try {
        apxDns().insertSanitizedHtml(
          widget,
          `<div class="apxdns-input-copy-container">
            <input type="text" value="76.76.21.21">
            <button onclick="window.apxDns.copyInputText(this.parentElement.querySelector('input'))">Copy</button>
          </div>`
        );
        widget.querySelector('button')?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        expect(copySpy).toHaveBeenCalledTimes(1);
        expect(copySpy.mock.calls[0][0]).toBe(widget.querySelector('input'));
      } finally {
        apxDns().copyInputText = original;
      }
    });

    it('does not bind handlers that stray from the trusted patterns', () => {
      expect(
        apxDns()._compileTrustedHandler(
          "window.apxDns.showManualInstructions('a'); window.__apx_pwned = true"
        )
      ).toBeNull();
      expect(apxDns()._compileTrustedHandler('alert(1)')).toBeNull();
      expect(
        apxDns()._compileTrustedHandler('window.apxDns.copyInputText(alert(1))')
      ).toBeNull();
      expect(
        apxDns()._compileTrustedHandler(
          "window.apxDns.copyInputText(this.ownerDocument.defaultView.alert(1))"
        )
      ).toBeNull();
    });
  });

  describe('_resolveElementChain', () => {
    it('resolves allowlisted chains within the widget', () => {
      widget.innerHTML =
        '<div class="apxdns-input-copy-container">' +
        '<input type="text" value="76.76.21.21">' +
        '<button type="button">Copy</button></div>';
      const button = widget.querySelector('button')!;

      const target = apxDns()._resolveElementChain(
        button,
        "this.parentElement.querySelector('input')"
      );
      expect(target).toBe(widget.querySelector('input'));
    });

    it('rejects selectors outside the compile-time allowlist', () => {
      widget.innerHTML = '<div><input name="totp"><button>Copy</button></div>';
      const button = widget.querySelector('button')!;

      // Attribute selectors ([...]) are outside the allowlisted charset.
      expect(
        apxDns()._resolveElementChain(
          button,
          "this.parentElement.querySelector('input[name=totp]')"
        )
      ).toBeNull();

      // Selectors beyond the 128-char cap never parse.
      const long = 'a'.repeat(200);
      expect(
        apxDns()._resolveElementChain(button, `this.querySelector('${long}')`)
      ).toBeNull();
    });

    it('refuses chains that escape the widget container', () => {
      const outside = document.createElement('input');
      outside.id = 'outside-secret';
      outside.value = 'TOTP-SEED-VALUE';
      document.body.appendChild(outside);

      widget.innerHTML = '<div><button>Copy</button></div>';
      const button = widget.querySelector('button')!;

      expect(
        apxDns()._resolveElementChain(
          button,
          "this.parentElement.parentElement.parentElement.querySelector('#outside-secret')"
        )
      ).toBeNull();
    });

    it('compiled copy handlers cannot copy content outside the widget', () => {
      const outside = document.createElement('input');
      outside.id = 'outside-secret';
      outside.value = 'TOTP-SEED-VALUE';
      document.body.appendChild(outside);

      const copySpy = vi.fn();
      const original = apxDns().copyInputText;
      apxDns().copyInputText = copySpy;
      try {
        apxDns().insertSanitizedHtml(
          widget,
          `<button onclick="window.apxDns.copyInputText(this.parentElement.parentElement.parentElement.querySelector('#outside-secret'))">Copy</button>`
        );
        widget.querySelector('button')?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        expect(copySpy).not.toHaveBeenCalled();
      } finally {
        apxDns().copyInputText = original;
      }
    });
  });

  describe('renderProviderInstructions', () => {
    it('sanitizes instruction steps and the verify section', () => {
      apxDns().renderProviderInstructions({
        domain_results: {
          'example.com': {
            steps: [
              {
                html:
                  '<div class="apxdns-instruction"><p>Step</p>' +
                  '<img src="x" onerror="window.__apx_pwned = true"></div>',
              },
            ],
          },
        },
        verify_section: {
          html:
            '<div id="apxdnswidget-verify-section" class="apxdns-verify-container">' +
            '<button class="apxdns-verify-btn" onclick="window.apxDns.verifyRecords()">Verify</button>' +
            '<script>window.__apx_pwned = true</' +
            'script></div>',
        },
      });

      expect(widget.querySelector('.apxdns-instruction p')?.textContent).toBe('Step');
      expect(widget.querySelector('[onerror]')).toBeNull();
      expect(widget.querySelector('script')).toBeNull();
      expect(widget.querySelector('.apxdns-verify-btn')).not.toBeNull();
      expect(window.__apx_pwned).toBeUndefined();
    });
  });

  describe('selector escaping', () => {
    it('showManualInstructions tolerates hostile data-apxid values', () => {
      const el = document.createElement('div');
      const hostileId = "x'] , [data-other='y";
      el.setAttribute('data-apxid', hostileId);
      document.body.appendChild(el);

      // Without CSS escaping this selector throws a SyntaxError.
      expect(() => apxDns().showManualInstructions(hostileId)).not.toThrow();
      expect(el.classList.contains('apxdns-hide')).toBe(true);
    });

    it('showManualInstructions still toggles well-formed ids', () => {
      const el = document.createElement('div');
      el.setAttribute('data-apxid', 'manual-1');
      el.className = 'apxdns-hide';
      document.body.appendChild(el);

      apxDns().showManualInstructions('manual-1');
      expect(el.classList.contains('apxdns-hide')).toBe(false);
    });
  });

  describe('prefill domain', () => {
    it('assigns prefillDomain via the value property, not markup', () => {
      apxDns().config = {
        widget_id: 'apxdnswidget',
        prefillDomain: '"><img src=x onerror=window.__apx_pwned=true>',
      };
      apxDns().showEnterDomain();

      const input = widget.querySelector<HTMLInputElement>('.apxdns-domain-input');
      expect(input?.value).toBe('"><img src=x onerror=window.__apx_pwned=true>');
      expect(widget.querySelector('img')).toBeNull();
      expect(window.__apx_pwned).toBeUndefined();
    });
  });

  describe('verifyRecords output escaping', () => {
    it('escapes API-derived record values in the verify templates', async () => {
      apxDns().config = {
        widget_id: 'apxdnswidget',
        api_url: '',
        token: 'tok',
        verifyAutoScroll: false,
      };
      apxDns().temp_records = [
        { apex: 'a', tld: 'com', domain: 'a.com', host: '@', value: 'v', type: 'A' },
      ];

      widget.innerHTML =
        '<button class="apxdns-verify-btn">Verify</button>' +
        '<div class="apxdns-verify-loader apxdns-hide"></div>' +
        '<div id="apxdnswidget-verify-section"></div>';

      vi.mocked(global.fetch).mockResolvedValue({
        json: () =>
          Promise.resolve({
            records: [
              {
                apex: 'a',
                tld: 'com',
                match: false,
                type: 'a',
                combined_host: '<b>host</b>',
                value: '<img src=x onerror="window.__apx_pwned = true">',
                actual_values:
                  '</textarea><script>window.__apx_pwned = true</' + 'script>',
              },
            ],
          }),
      } as unknown as Response);

      apxDns().verifyRecords();

      const section = document.getElementById('apxdnswidget-verify-section')!;
      await vi.waitFor(() => {
        expect(section.querySelector('.apxdns-verify-record')).not.toBeNull();
      });

      expect(section.querySelector('script')).toBeNull();
      expect(section.querySelector('img')).toBeNull();
      expect(section.querySelector('b')).toBeNull();
      expect(section.textContent).toContain('<b>host</b>');
      const textarea = section.querySelector('textarea');
      expect(textarea?.value).toContain('</textarea><script>');
      expect(window.__apx_pwned).toBeUndefined();

      apxDns().temp_records = null;
    });
  });

  describe('escapeHtml', () => {
    it('escapes markup-significant characters', () => {
      expect(apxDns().escapeHtml(`<img src="x" onerror='p'>&`)).toBe(
        '&lt;img src=&quot;x&quot; onerror=&#39;p&#39;&gt;&amp;'
      );
      expect(apxDns().escapeHtml(null)).toBe('');
      expect(apxDns().escapeHtml(true)).toBe('true');
    });
  });
});
