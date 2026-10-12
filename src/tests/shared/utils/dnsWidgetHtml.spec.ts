// src/tests/shared/utils/dnsWidgetHtml.spec.ts
//
// RISK-2026-08-14-M09: the sanitizer the vendored Approximated DNS widget
// routes its remote API HTML through. Remote markup must come out with no
// script, no inline handlers and no script-capable URLs, while the widget's
// own controls survive as data-apxdns-action attributes.

import { loggingService } from '@/services/logging.service';
import {
  ACTION_ARG_ATTR,
  ACTION_ATTR,
  parseInlineAction,
  sanitizeDnsWidgetHtml,
} from '@/shared/utils/dnsWidgetHtml';
import DOMPurify from 'dompurify';
import { afterEach, describe, expect, it, vi } from 'vitest';

/** Sanitize into a detached container for DOM assertions. */
function render(html: string): HTMLDivElement {
  const container = document.createElement('div');
  container.innerHTML = sanitizeDnsWidgetHtml(html);
  return container;
}

/** Every attribute name in the subtree, lower-cased. */
function attributeNames(root: Element): string[] {
  return Array.from(root.querySelectorAll('*')).flatMap((el) =>
    Array.from(el.attributes).map((attr) => attr.name.toLowerCase())
  );
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe('sanitizeDnsWidgetHtml', () => {
  describe('removes executable markup', () => {
    it('strips <script> elements', () => {
      const out = render('<div class="apxdns-inst-body">ok<script>window.__x = 1</script></div>');
      expect(out.querySelector('script')).toBeNull();
      expect(out.textContent).toBe('ok');
    });

    it('strips the onerror handler from <img> and keeps the image', () => {
      const out = render('<img class="apxdns-inst-provider-logo" src="https://cdn.example/logo.png" onerror="alert(1)">');
      const img = out.querySelector('img');
      expect(img).not.toBeNull();
      expect(img!.hasAttribute('onerror')).toBe(false);
      expect(img!.getAttribute('src')).toBe('https://cdn.example/logo.png');
    });

    it.each([
      ['javascript:alert(1)'],
      ['JaVaScRiPt:alert(1)'],
      ['  javascript:alert(1)'],
      ['jav&#x09;ascript:alert(1)'],
      ['vbscript:msgbox(1)'],
      ['data:text/html,<script>alert(1)</script>'],
    ])('removes the href %s', (href) => {
      const out = render(`<a class="apxdns-btn-link" href="${href}">x</a>`);
      expect(out.querySelector('a')!.hasAttribute('href')).toBe(false);
    });

    it('keeps https and mailto hrefs', () => {
      const out = render(
        '<a href="https://dns.example/login">a</a><a href="mailto:help@example.com">b</a>'
      );
      const hrefs = Array.from(out.querySelectorAll('a')).map((a) => a.getAttribute('href'));
      expect(hrefs).toEqual(['https://dns.example/login', 'mailto:help@example.com']);
    });

    it('removes iframe, form, style and other non-allowlisted elements', () => {
      const out = render(`
        <iframe src="https://evil.example"></iframe>
        <form action="https://evil.example"><input name="password"></form>
        <style>body { display: none }</style>
        <object data="https://evil.example/x.swf"></object>
        <math><mi>x</mi></math>`);
      for (const tag of ['iframe', 'form', 'style', 'object', 'math']) {
        expect(out.querySelector(tag)).toBeNull();
      }
    });

    it('drops style, form and formaction attributes', () => {
      const out = render(
        '<div class="apxdns-instruction" style="position:fixed;inset:0">x</div>' +
          '<button form="login-form" formaction="https://evil.example">go</button>'
      );
      expect(attributeNames(out)).not.toContain('style');
      expect(attributeNames(out)).not.toContain('form');
      expect(attributeNames(out)).not.toContain('formaction');
    });

    it.each([
      ['an unknown handler', 'onmouseover="alert(1)"'],
      ['a non-widget onclick', 'onclick="alert(1)"'],
      ['an unknown widget function', 'onclick="window.apxDns.stop()"'],
      ['a widget call followed by other code', 'onclick="window.apxDns.verifyRecords(); alert(1)"'],
      ['a widget call on a non-click event', 'onmouseover="window.apxDns.verifyRecords()"'],
      ['a widget function read off another object', 'onclick="evil.apxDns.verifyRecords()"'],
    ])('drops %s without creating an action', (_label, handler) => {
      const out = render(`<button class="apxdns-verify-btn" ${handler}>Verify</button>`);
      const names = attributeNames(out);
      expect(names.filter((name) => name.startsWith('on'))).toEqual([]);
      expect(names).not.toContain(ACTION_ATTR);
    });

    it('strips handlers from SVG elements', () => {
      const out = render('<svg class="apxdns-automate-dns-icon" onload="alert(1)"><path d="M0 0h24"/></svg>');
      expect(attributeNames(out).filter((name) => name.startsWith('on'))).toEqual([]);
      expect(out.querySelector('path')!.getAttribute('d')).toBe('M0 0h24');
    });

    it('logs when a handler that mentions apxDns is dropped', () => {
      const warn = vi.spyOn(loggingService, 'warn').mockImplementation(() => {});
      render('<button onclick="window.apxDns.somethingNew()">x</button>');
      expect(warn).toHaveBeenCalledWith(
        '[dnsWidgetHtml] dropped unrecognised widget handler',
        { attribute: 'onclick' }
      );
    });
  });

  describe('preserves widget actions', () => {
    it.each([
      ['window.apxDns.verifyRecords()', 'verifyRecords'],
      ['apxDns.verifyRecords();', 'verifyRecords'],
      ['window.apxDns.restart(); return false;', 'restart'],
      ['window.apxDns.copyInputText(this.previousElementSibling)', 'copyInputText'],
      ["return window.apxDns.copyInputText(this.parentElement.querySelector('input'))", 'copyInputText'],
    ])('rewrites onclick="%s" into data-apxdns-action', (handler, action) => {
      const out = render(`<button class="apxdns-button" onclick="${handler}">x</button>`);
      const button = out.querySelector('button')!;
      expect(button.getAttribute(ACTION_ATTR)).toBe(action);
      expect(button.hasAttribute('onclick')).toBe(false);
    });

    it('keeps the identifier argument of showManualInstructions', () => {
      const out = render(
        `<a class="apxdns-show-manual-instructions-btn" href="javascript:void(0)" ` +
          `onclick="window.apxDns.showManualInstructions('manual-abc_123')">Show</a>`
      );
      const link = out.querySelector('a')!;
      expect(link.getAttribute(ACTION_ATTR)).toBe('showManualInstructions');
      expect(link.getAttribute(ACTION_ARG_ATTR)).toBe('manual-abc_123');
      // The javascript: href is gone; '#' keeps the control keyboard-reachable.
      expect(link.getAttribute('href')).toBe('#');
    });

    it.each([
      [`window.apxDns.showManualInstructions('x\\'];alert(1)//')`],
      ['window.apxDns.showManualInstructions(document.cookie)'],
      ['window.apxDns.showManualInstructions()'],
    ])('rejects showManualInstructions with a non-identifier argument: %s', (handler) => {
      const out = render(`<button onclick="${handler.replace(/"/g, '&quot;')}">x</button>`);
      expect(out.querySelector('button')!.hasAttribute(ACTION_ATTR)).toBe(false);
    });

    it('keeps data-apxid targets', () => {
      const out = render('<div class="apxdns-hide" data-apxid="manual-1">steps</div>');
      expect(out.querySelector('[data-apxid="manual-1"]')).not.toBeNull();
    });
  });

  // SEC-F1: these attributes let a click inside the widget act on an app
  // element by id (e.g. <label for="app-danger"> clicks an app button).
  describe('attributes that reach elements outside the widget', () => {
    it.each([
      ['<label for="app-danger" class="apxdns-x">Show</label>', 'for'],
      ['<button popovertarget="app-popover" popovertargetaction="show">x</button>', 'popovertarget'],
      ['<button popovertarget="app-popover" popovertargetaction="show">x</button>', 'popovertargetaction'],
      ['<button command="show-modal" commandfor="app-dialog">x</button>', 'command'],
      ['<button command="show-modal" commandfor="app-dialog">x</button>', 'commandfor'],
    ])('drops %s -> %s', (html, attribute) => {
      expect(attributeNames(render(html))).not.toContain(attribute);
    });
  });

  // SEC-F6: a relative source is fetched from this origin on render.
  describe('resource URLs', () => {
    it.each([
      ['<img src="/logout">'],
      ['<img src="logout">'],
      ['<img src="//evil.example/x.png">'],
      ['<img src="http://cdn.example/x.png">'],
      ['<img src="data:image/svg+xml,<svg></svg>">'],
      ['<input type="image" src="/account/delete">'],
    ])('drops a src that is not absolute https: %s', (html) => {
      expect(attributeNames(render(html))).not.toContain('src');
    });

    it('keeps an absolute https src', () => {
      const out = render('<img src="https://cdn.example/logo.png">');
      expect(out.querySelector('img')!.getAttribute('src')).toBe('https://cdn.example/logo.png');
    });

    it('drops srcset and background', () => {
      const out = render(
        '<img src="https://cdn.example/a.png" srcset="/logout 1x, https://cdn.example/b.png 2x">' +
          '<table><tbody><tr><td background="/logout">x</td></tr></tbody></table>'
      );
      expect(attributeNames(out)).not.toContain('srcset');
      expect(attributeNames(out)).not.toContain('background');
    });
  });

  describe('anchors', () => {
    // SEC-F2: an SVG anchor's tagName is lower-case 'a'.
    it.each([['_blank'], ['_top']])(
      'removes target=%s from SVG anchors and forces rel',
      (target) => {
        const out = render(
          `<svg><a href="https://dns.example/" target="${target}"><rect width="10" height="10"/></a></svg>`
        );
        const link = out.querySelector('svg a')!;
        expect(link.hasAttribute('target')).toBe(false);
        expect(link.getAttribute('rel')).toBe('noopener noreferrer');
      }
    );

    it('keeps target=_blank and forces rel="noopener noreferrer"', () => {
      const out = render('<a href="https://dns.example/apply" target="_blank" rel="opener">Apply</a>');
      const link = out.querySelector('a')!;
      expect(link.getAttribute('target')).toBe('_blank');
      expect(link.getAttribute('rel')).toBe('noopener noreferrer');
    });

    it('removes any target other than _blank', () => {
      const out = render('<a href="https://dns.example" target="_top">x</a>');
      expect(out.querySelector('a')!.hasAttribute('target')).toBe(false);
    });
  });

  describe('class and id names', () => {
    it("keeps only the widget's own class names", () => {
      const out = render('<div class="fixed inset-0 z-50 apxdns-instruction loader">x</div>');
      expect(out.querySelector('div')!.getAttribute('class')).toBe('apxdns-instruction loader');
    });

    it('drops the class attribute when no widget class remains', () => {
      const out = render('<div class="fixed inset-0">x</div>');
      expect(out.querySelector('div')!.hasAttribute('class')).toBe(false);
    });

    it('keeps widget ids and drops the rest', () => {
      const out = render('<div id="apxdnswidget-verify-section"></div><div id="app"></div>');
      const ids = Array.from(out.querySelectorAll('div')).map((el) => el.id);
      expect(ids).toEqual(['apxdnswidget-verify-section', '']);
    });
  });

  // SEC-F5: DOMPurify returns its input unchanged where it is unsupported.
  it('returns escaped text when DOMPurify is unsupported', async () => {
    vi.resetModules();
    vi.doMock('dompurify', () => ({
      default: () => ({
        isSupported: false,
        addHook: vi.fn(),
        sanitize: (dirty: string) => dirty,
      }),
    }));
    try {
      const { sanitizeDnsWidgetHtml: unsupported } = await import('@/shared/utils/dnsWidgetHtml');
      const hostile = '<img src=x onerror="alert(1)"><b>bold</b>';

      const container = document.createElement('div');
      container.innerHTML = unsupported(hostile);

      expect(container.children).toHaveLength(0);
      expect(container.textContent).toBe(hostile);
    } finally {
      vi.doUnmock('dompurify');
      vi.resetModules();
    }
  });

  it('does not change the shared DOMPurify instance', () => {
    sanitizeDnsWidgetHtml('<div class="apxdns-x">x</div>');
    // The class restriction lives on a private instance only.
    expect(DOMPurify.sanitize('<div class="fixed">x</div>')).toBe('<div class="fixed">x</div>');
  });
});

describe('parseInlineAction', () => {
  it('returns null for oversized handlers', () => {
    const padding = ' '.repeat(300);
    expect(parseInlineAction(`window.apxDns.verifyRecords()${padding}`)).toBeNull();
  });

  it('returns null for unbalanced calls', () => {
    expect(parseInlineAction('window.apxDns.copyInputText(this')).toBeNull();
  });

  it('returns null when arguments are passed to an argument-free action', () => {
    expect(parseInlineAction('window.apxDns.verifyRecords(fetch("https://evil"))')).toBeNull();
  });

  it('does not treat a parenthesis inside a string as the end of the call', () => {
    expect(
      parseInlineAction("window.apxDns.copyInputText(this.closest(')')); alert(1)")
    ).toBeNull();
  });
});
