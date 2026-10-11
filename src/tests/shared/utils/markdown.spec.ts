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

    it('strips javascript: links but keeps the link text', () => {
      const html = renderMarkdown('[click](javascript:alert(1))');
      expect(html).not.toContain('javascript:');
      expect(html).toContain('click');
    });

    it('strips data: links', () => {
      const html = renderMarkdown('[x](data:text/html,<script>alert(1)</script>)');
      expect(html).not.toContain('data:');
      expect(html).not.toContain('<script');
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
  });

  describe('links', () => {
    it('keeps https links and opens them in a new tab without opener or referrer', () => {
      const html = renderMarkdown('[docs](https://docs.example/page)');
      expect(html).toContain('href="https://docs.example/page"');
      expect(html).toContain('target="_blank"');
      expect(html).toContain('rel="noopener noreferrer nofollow"');
    });

    it('keeps mailto links', () => {
      expect(renderMarkdown('[mail](mailto:a@example.com)')).toContain(
        'href="mailto:a@example.com"'
      );
    });

    it('does not let a target other than _blank through', () => {
      const html = renderMarkdown('<a href="https://a.example" target="_top">x</a>');
      expect(html).toContain('target="_blank"');
      expect(html).not.toContain('_top');
    });
  });
});
