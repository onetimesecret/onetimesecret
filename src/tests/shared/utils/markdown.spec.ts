// src/tests/shared/utils/markdown.spec.ts
//
// renderMarkdown(): Markdown -> sanitized HTML for secrets with
// display_type 'markdown'. The source is written by the sender and shown in
// the recipient's browser, so most of this is about what does NOT survive.

import { renderMarkdown } from '@/shared/utils/markdown';
import { describe, expect, it } from 'vitest';

describe('renderMarkdown', () => {
  describe('rendering', () => {
    it('renders headings, emphasis and lists', () => {
      const html = renderMarkdown('# Title\n\nSome **bold** text\n\n- one\n- two');
      expect(html).toContain('<h1>Title</h1>');
      expect(html).toContain('<strong>bold</strong>');
      expect(html).toMatch(/<ul>\s*<li>one<\/li>\s*<li>two<\/li>\s*<\/ul>/);
    });

    it('treats a single newline as a line break (GFM breaks)', () => {
      expect(renderMarkdown('line one\nline two')).toContain('<br>');
    });

    it('highlights fenced code in a known language', () => {
      const html = renderMarkdown('```js\nconst x = 1;\n```');
      expect(html).toContain('class="hljs language-js"');
      expect(html).toContain('hljs-keyword');
    });

    it('escapes fenced code in an unknown language without highlighting', () => {
      const html = renderMarkdown('```nosuchlang\n<b>not html</b>\n```');
      expect(html).toContain('&lt;b&gt;not html&lt;/b&gt;');
      expect(html).not.toContain('<b>');
      expect(html).not.toContain('hljs-');
    });

    it('escapes fenced code with no language', () => {
      const html = renderMarkdown('```\na < b && c > d\n```');
      expect(html).toContain('class="hljs"');
      expect(html).toContain('a &lt; b &amp;&amp; c &gt; d');
    });

    it('returns an empty string for empty input', () => {
      expect(renderMarkdown('')).toBe('');
    });
  });

  describe('sanitization', () => {
    it('strips script tags and their content', () => {
      const html = renderMarkdown('hello <script>alert(1)</script> world');
      expect(html).not.toContain('<script');
      expect(html).not.toContain('alert(1)');
      expect(html).toContain('hello');
    });

    it('strips inline event handlers', () => {
      const html = renderMarkdown('<p onclick="alert(1)">x</p>');
      expect(html).not.toContain('onclick');
      expect(html).toContain('x');
    });

    it('strips images so a reveal cannot ping the sender', () => {
      const html = renderMarkdown(
        '![pixel](https://evil.example/p.gif)\n\n<img src="https://evil.example/p.gif">'
      );
      expect(html).not.toContain('<img');
      expect(html).not.toContain('evil.example');
    });

    it('strips iframes, forms and form controls', () => {
      const html = renderMarkdown(
        '<iframe src="https://a.example"></iframe>' +
          '<form action="https://a.example"><input name="pw"><button>go</button></form>'
      );
      expect(html).not.toContain('<iframe');
      expect(html).not.toContain('<form');
      expect(html).not.toContain('<input');
      expect(html).not.toContain('<button');
    });

    it('strips style attributes and style elements', () => {
      const html = renderMarkdown(
        '<p style="position:fixed">x</p><style>body{display:none}</style>'
      );
      expect(html).not.toContain('style=');
      expect(html).not.toContain('<style');
      expect(html).not.toContain('display:none');
    });

    it('strips svg and math', () => {
      const html = renderMarkdown(
        '<svg onload="alert(1)"><circle r="1"/></svg><math><mi>x</mi></math>'
      );
      expect(html).not.toContain('<svg');
      expect(html).not.toContain('<math');
      expect(html).not.toContain('onload');
    });

    it('strips data-* attributes', () => {
      expect(renderMarkdown('<p data-track="1">x</p>')).not.toContain('data-track');
    });

    it('strips the background attribute so a table cannot ping the sender', () => {
      const html = renderMarkdown(
        '<table background="https://evil.example/p.gif">' +
          '<tr><td background="https://evil.example/p.gif">x</td></tr></table>'
      );
      expect(html).toContain('<td>x</td>');
      expect(html).not.toContain('background');
      expect(html).not.toContain('evil.example');
    });

    it('drops classes the renderer does not own', () => {
      // The app's utility classes would let sender HTML overlay the reveal
      // page, e.g. a full-screen fake notice.
      const html = renderMarkdown(
        '<div class="fixed inset-0 z-50 bg-white">fake</div>' +
          '<span class="hljs-keyword sr-only md-link-url">x</span>'
      );
      expect(html).toContain('<div>fake</div>');
      expect(html).toContain('<span class="hljs-keyword md-link-url">x</span>');
    });

    it('keeps highlight.js scope classes', () => {
      expect(renderMarkdown('```js\nclass Foo {}\n```')).toContain(
        '<span class="hljs-title class_">Foo</span>'
      );
    });

    it('strips id attributes so content cannot take over page ids', () => {
      expect(renderMarkdown('<p id="copy-instructions">x</p>')).toBe('<p>x</p>');
    });

    it('strips dialog, keeping its text, so an open one cannot cover the page', () => {
      expect(renderMarkdown('<dialog open>Session expired</dialog>')).toBe('Session expired');
    });

    it('strips aria-* and role so text on screen is not hidden from screen readers', () => {
      const html = renderMarkdown(
        '<span aria-hidden="true">pw1</span> <span role="img">pw2</span> ' +
          '<span aria-label="nothing here">pw3</span>'
      );
      expect(html.trim()).toBe('<p><span>pw1</span> <span>pw2</span> <span>pw3</span></p>');
    });
  });

  describe('links', () => {
    // A secret page on this domain must not carry clickable links whose label
    // can say one thing while the destination is another. Links render as
    // inert text that shows where they would have gone.
    const noAnchors = (html: string) => {
      expect(html).not.toContain('<a');
      expect(html).not.toContain('href=');
    };

    it('renders a link as its label followed by the destination', () => {
      const html = renderMarkdown('[docs](https://docs.example/page)');
      noAnchors(html);
      expect(html).toContain('docs (<span class="md-link-url">https://docs.example/page</span>)');
    });

    it('shows the real destination when the label looks like a different URL', () => {
      const html = renderMarkdown('[https://bank.example](https://evil.example/login)');
      noAnchors(html);
      expect(html).toContain('https://bank.example');
      expect(html).toContain('<span class="md-link-url">https://evil.example/login</span>');
    });

    it('shows an autolinked URL or email once', () => {
      const html = renderMarkdown('see https://a.example/p or a@example.com');
      noAnchors(html);
      expect(html).toContain('see <span class="md-link-url">https://a.example/p</span> or');
      expect(html).toContain('<span class="md-link-url">a@example.com</span>');
      expect(html).not.toContain('mailto:');
    });

    it('keeps the label formatting and handles reference links', () => {
      const html = renderMarkdown('[**bold**][1]\n\n[1]: https://r.example');
      noAnchors(html);
      expect(html).toContain(
        '<strong>bold</strong> (<span class="md-link-url">https://r.example</span>)'
      );
    });

    it('shows a javascript: or data: destination as escaped text', () => {
      const html = renderMarkdown(
        '[click](javascript:alert(1)) [x](data:text/html,<script>alert(1)</script>)'
      );
      noAnchors(html);
      expect(html).not.toContain('<script');
      expect(html).toContain('<span class="md-link-url">javascript:alert(1)</span>');
    });

    it('unwraps raw <a> elements to their text', () => {
      const html = renderMarkdown('<a href="https://a.example" target="_top">x</a>');
      noAnchors(html);
      expect(html).toContain('x');
      expect(html).not.toContain('a.example');
    });
  });
});
