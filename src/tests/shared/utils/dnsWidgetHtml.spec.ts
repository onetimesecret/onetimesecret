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
  parseJavascriptUrlAction,
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

    it('strips the onerror handler from <img> and keeps it as alt text', () => {
      const out = render(
        '<img class="apxdns-inst-provider-logo" alt="Provider" src="https://cdn.example/logo.png" onerror="alert(1)">'
      );
      const img = out.querySelector('img');
      expect(img).not.toBeNull();
      expect(img!.hasAttribute('onerror')).toBe(false);
      expect(img!.hasAttribute('src')).toBe(false);
      expect(img!.getAttribute('alt')).toBe('Provider');
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

    // QA-F1: a javascript: href carrying one recognised call becomes the same
    // data-action form; any other javascript: href is still dropped.
    it('converts a javascript: href carrying a widget call', () => {
      const out = render(
        `<a class="apxdns-show-manual-instructions-btn" ` +
          `href="javascript:window.apxDns.showManualInstructions('manual-example.com')">Show</a>`
      );
      const link = out.querySelector('a')!;
      expect(link.getAttribute(ACTION_ATTR)).toBe('showManualInstructions');
      expect(link.getAttribute(ACTION_ARG_ATTR)).toBe('manual-example.com');
      expect(link.getAttribute('href')).toBe('#');
    });

    it.each([
      ['javascript:window.apxDns.restart();alert(1)'],
      ['javascript:void(0)'],
    ])('drops the javascript: href %s without creating an action', (href) => {
      const link = render(`<a href="${href}">x</a>`).querySelector('a')!;
      expect(link.hasAttribute(ACTION_ATTR)).toBe(false);
      expect(link.hasAttribute('href')).toBe(false);
    });

    it('lets the first recognised handler win and removes the rest', () => {
      const link = render(
        `<a onclick="window.apxDns.verifyRecords()" ` +
          `href="javascript:window.apxDns.restart()" onmouseover="alert(1)">x</a>`
      ).querySelector('a')!;
      expect(link.getAttribute(ACTION_ATTR)).toBe('verifyRecords');
      expect(attributeNames(link.parentElement!).filter((n) => n.startsWith('on'))).toEqual([]);
      expect(link.getAttribute('href')).toBe('#');
    });

    it('accepts an id with dots and a preventDefault prefix', () => {
      const out = render(
        `<button onclick="event.preventDefault(); window.apxDns.showManualInstructions('manual-example.com'); return false;">x</button>`
      );
      const button = out.querySelector('button')!;
      expect(button.getAttribute(ACTION_ATTR)).toBe('showManualInstructions');
      expect(button.getAttribute(ACTION_ARG_ATTR)).toBe('manual-example.com');
    });
  });

  // SEC-F9: a named img/a becomes a window or document property and can
  // shadow a global the app reads.
  it.each([
    ['<img name="__BOOTSTRAP_ME__" src="https://cdn.example/x.png">'],
    ['<a name="apxDns" href="https://dns.example">x</a>'],
    ['<input name="password" value="x">'],
  ])('drops the name attribute: %s', (html) => {
    const out = render(html);
    expect(attributeNames(out)).not.toContain('name');
    expect(out.firstElementChild).not.toBeNull();
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

describe('sanitizeDnsWidgetHtml resource loading', () => {
  // SEC-F6: any src would fire a request on render. The CSP's img-src
  // 'self' data: blocks cross-origin images, so the only requests a src
  // could still make are same-origin ones; all are dropped.
  describe('resource URLs', () => {
    it.each([
      ['<img src="/logout">'],
      ['<img src="logout">'],
      [`<img src="${window.location.origin}/logout">`],
      ['<img src="https://app.onetimesecret.example/logout">'],
      ['<img src="https://cdn.example/logo.png">'],
      ['<img src="//evil.example/x.png">'],
      ['<img src="http://cdn.example/x.png">'],
      ['<img src="data:image/png;base64,iVBORw0KGgo=">'],
      ['<input type="image" src="https://app.onetimesecret.example/account/delete">'],
    ])('drops src: %s', (html) => {
      const out = render(html);
      expect(out.firstElementChild).not.toBeNull();
      expect(attributeNames(out)).not.toContain('src');
    });

    it('drops srcset, poster and background', () => {
      const out = render(
        '<img srcset="/logout 1x, https://cdn.example/b.png 2x" poster="/logout">' +
          '<table><tbody><tr><td background="/logout">x</td></tr></tbody></table>'
      );
      for (const attribute of ['srcset', 'poster', 'background']) {
        expect(attributeNames(out)).not.toContain(attribute);
      }
    });
  });

  // SEC-F10: SVG presentation attributes are parsed as CSS, so a url() or
  // image function in one fetches. Only a same-document url(#id) is kept.
  describe('CSS url() and image functions', () => {
    const svgWith = (attribute: string, value: string) =>
      render(`<svg><path d="M0 0h24" ${attribute}='${value}'/></svg>`).querySelector('path')!;

    it.each([
      ['fill', 'url(/logout#a)'],
      ['fill', 'URL( /logout )'],
      ['stroke', 'url("/logout")'],
      ['filter', "url(https://evil.example/f.svg#f)"],
      ['mask', 'url(#m) url(/logout)'],
      ['clip-path', 'url( #a)x'],
      ['marker-start', 'url(data:image/svg+xml,x)'],
      ['marker-mid', 'u\\72 l(/logout)'],
      ['marker-end', '\\75 rl(/logout)'],
      ['mask', "image-set('/logout' 1x)"],
      ['mask', "-webkit-image-set('/logout' 1x)"],
      ['fill', "url(#a\\29)"],
      ['fill', 'url("#grad")'],
    ])('drops %s="%s"', (attribute, value) => {
      expect(svgWith(attribute, value).hasAttribute(attribute)).toBe(false);
    });

    it.each([
      ['fill', 'url(#grad)'],
      ['stroke', 'URL( #grad-1 )'],
      ['fill', 'currentColor'],
      ['stroke-width', '1.5'],
    ])('keeps %s="%s"', (attribute, value) => {
      expect(svgWith(attribute, value).getAttribute(attribute)).toBe(value);
    });

    it('leaves plain-text attributes alone', () => {
      const out = render('<img alt="See image (above)" title="url(/x) is just text">');
      expect(out.querySelector('img')!.getAttribute('alt')).toBe('See image (above)');
      expect(out.querySelector('img')!.getAttribute('title')).toBe('url(/x) is just text');
    });
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

  // QA-F1: no real Approximated markup sample exists, so the recognizer
  // accepts the plausible shapes of one widget call.
  describe('accepted shapes', () => {
    it.each([
      ["window.apxDns.showManualInstructions('manual-example.com')", 'manual-example.com'],
      ['apxDns.showManualInstructions("manual:example.com:1")', 'manual:example.com:1'],
      ["window.apxDns.showManualInstructions('a b/c?d=e&f#g')", 'a b/c?d=e&f#g'],
      ["window.apxDns.showManualInstructions('" + 'x'.repeat(128) + "')", 'x'.repeat(128)],
    ])('showManualInstructions argument: %s', (handler, arg) => {
      expect(parseInlineAction(handler)).toEqual({ name: 'showManualInstructions', arg });
    });

    it.each([
      ['window.apxDns.verifyRecords()', 'verifyRecords'],
      ['apxDns.verifyRecords()', 'verifyRecords'],
      ['event.preventDefault(); window.apxDns.verifyRecords()', 'verifyRecords'],
      ['event.preventDefault();window.apxDns.restart();return false;', 'restart'],
      ['return window.apxDns.restart()', 'restart'],
      ['window.apxDns.restart() ; return false', 'restart'],
      ['  window.apxDns.verifyRecords();  ', 'verifyRecords'],
      ['window.apxDns.copyInputText()', 'copyInputText'],
      ["window.apxDns.copyInputText(this.parentElement.querySelector('input'))", 'copyInputText'],
      ['window.apxDns.copyInputText(this.nextElementSibling)', 'copyInputText'],
      ["window.apxDns.copyInputText(this.closest('div').firstElementChild)", 'copyInputText'],
      ['window.apxDns.copyInputText(this.parentNode.lastElementChild)', 'copyInputText'],
    ])('%s', (handler, name) => {
      expect(parseInlineAction(handler)).toMatchObject({ name });
    });
  });

  describe('rejected near-misses', () => {
    it.each([
      ['an extra statement after', "window.apxDns.showManualInstructions('x'); alert(1)"],
      ['an extra statement before', "alert(1); window.apxDns.verifyRecords()"],
      ['a comma expression', 'window.apxDns.restart(), alert(1)'],
      ['concatenation', "window.apxDns.showManualInstructions('a' + document.cookie)"],
      ['concatenation of literals', "window.apxDns.showManualInstructions('a' + 'b')"],
      ['a template literal', 'window.apxDns.showManualInstructions(`x${document.cookie}`)'],
      ['an escaped quote', "window.apxDns.showManualInstructions('x\\'y')"],
      ['a mixed-quote string', `window.apxDns.showManualInstructions('x"y')`],
      ['a control character', "window.apxDns.showManualInstructions('x\u0007y')"],
      ['an empty string', "window.apxDns.showManualInstructions('')"],
      ['an over-long string', "window.apxDns.showManualInstructions('" + 'x'.repeat(129) + "')"],
      ['two arguments', "window.apxDns.showManualInstructions('a', 'b')"],
      ['a non-string argument', 'window.apxDns.showManualInstructions(manualId)'],
      ['code as a copy argument', "window.apxDns.copyInputText((()=>{fetch('//evil')})())"],
      ['a function call as a copy argument', 'window.apxDns.copyInputText(alert(1))'],
      // The copy argument is `this` plus DOM navigation steps only.
      [
        'eval reached through the copy argument',
        "window.apxDns.copyInputText(this.ownerDocument.defaultView.eval('alert(1)'))",
      ],
      [
        'a location change in the copy argument',
        "window.apxDns.copyInputText(document.location.assign('https://evil.example'))",
      ],
      ['a document lookup as the copy argument', "window.apxDns.copyInputText(document.getElementById('x'))"],
      ['an unlisted property in the copy argument', 'window.apxDns.copyInputText(this.ownerDocument)'],
      ['a property called as a method', "window.apxDns.copyInputText(this.parentElement('x'))"],
      ['a method used as a property', 'window.apxDns.copyInputText(this.querySelector)'],
      ['a navigation method without a string', 'window.apxDns.copyInputText(this.closest())'],
      ['a different object', 'evil.apxDns.verifyRecords()'],
      ['an unknown action', 'window.apxDns.stop()'],
      ['a non-boolean return', 'window.apxDns.restart(); return document.cookie'],
      ['a call after return false', 'window.apxDns.restart(); return false; alert(1)'],
      ['a different leading call', 'event.stopPropagation(); window.apxDns.verifyRecords()'],
    ])('rejects %s', (_label, handler) => {
      expect(parseInlineAction(handler)).toBeNull();
    });
  });
});

describe('parseJavascriptUrlAction', () => {
  it.each([
    ["javascript:window.apxDns.showManualInstructions('manual-example.com')", 'showManualInstructions'],
    ['JavaScript:apxDns.verifyRecords()', 'verifyRecords'],
    ['  javascript:window.apxDns.restart()  ', 'restart'],
    ['java\tscript:window.apxDns.restart()', 'restart'],
    ["javascript:window.apxDns.showManualInstructions(%27manual-1%27)", 'showManualInstructions'],
  ])('recognizes %s', (url, name) => {
    expect(parseJavascriptUrlAction(url)).toMatchObject({ name });
  });

  it.each([
    ['javascript:void(0)'],
    ['javascript:window.apxDns.restart();alert(1)'],
    ['javascript:window.apxDns.showManualInstructions(%27x%27%2Balert(1))'],
    ['javascript:window.apxDns.restart()%'],
    ['https://dns.example/apply'],
  ])('rejects %s', (url) => {
    expect(parseJavascriptUrlAction(url)).toBeNull();
  });
});
