// src/shared/utils/markdown.ts
//
// Markdown -> sanitized HTML for secrets whose display_type is 'markdown'.
//
// The source is written by the sender and rendered in the recipient's
// browser, so the output is treated as hostile all the way through: marked
// parses, highlight.js colors fenced code, and a dedicated DOMPurify instance
// decides what reaches the DOM. On top of DOMPurify's HTML profile:
//
// - Links are not clickable. A Markdown link renders as its text followed by
//   the real destination, so `[Your bank](https://evil.example)` cannot pose
//   as a bank link on this site; raw <a> elements are unwrapped to their
//   text. A clickable link with a warning is a separate display type's job.
// - Elements that load remote resources (img, video, iframe, ...) are
//   stripped. A tracking pixel would tell the sender the recipient's IP
//   address and the moment of reveal.
// - style, data-*, id and background attributes are dropped, and class keeps
//   only the renderer's own tokens. Otherwise sender HTML could borrow the
//   app's utility classes to overlay the reveal page, claim one of its ids,
//   or fetch a remote background image when CSP is disabled.
//
// MarkdownRenderer.vue imports this module dynamically, but the production
// build is a single chunk (vite.config.ts, codeSplitting: false), so the
// parser and highlighter ship in the main bundle either way.

import DOMPurify, {
  type Config,
  type DOMPurify as Purifier,
  type UponSanitizeAttributeHookEvent,
} from 'dompurify';
import hljs from 'highlight.js/lib/common';
import { Marked, type Tokens } from 'marked';
import { markedHighlight } from 'marked-highlight';

/**
 * DOMPurify's default URI pattern with the scheme allowlist reduced to
 * https/http/mailto. Relative URLs carry no scheme and pass. Mirrors the
 * pattern GlobalBroadcast.vue uses for operator-controlled content. With
 * anchors and media forbidden this only guards leftovers such as `cite`.
 */
const ALLOWED_URI_REGEXP = /^(?:(?:https?|mailto):|[^a-z]|[a-z+.-]+(?:[^a-z+.:-]|$))/i;

/**
 * Elements that link out, fetch remote resources, accept input, carry
 * scripts and styles, or (dialog) draw outside the rendered flow, where an
 * open one could cover the reveal page. Removed on top of DOMPurify's HTML
 * profile, which would otherwise admit a, img, form controls, svg and
 * dialog. DOMPurify keeps the text content of a removed element, so a raw
 * <a> collapses to its label.
 */
const FORBID_TAGS = [
  'a',
  'img',
  'picture',
  'source',
  'video',
  'audio',
  'track',
  'iframe',
  'frame',
  'object',
  'embed',
  'form',
  'input',
  'textarea',
  'select',
  'button',
  'style',
  'link',
  'meta',
  'base',
  'svg',
  'math',
  'template',
  'slot',
  'dialog',
];

/**
 * `role` goes with the aria-* attributes (ALLOW_ARIA_ATTR below): sender
 * markup must not change what a screen reader hears, e.g. aria-hidden or
 * role="img" silencing text that stays on screen. The reveal page supplies
 * the region's semantics.
 */
const FORBID_ATTR = [
  'style',
  'srcset',
  'ping',
  'action',
  'formaction',
  'background',
  'id',
  'role',
];

/**
 * Class tokens the renderer itself emits: highlight.js scopes (`hljs-title`
 * and suffixes such as `class_`), marked's `language-*` code class, and the
 * inert link URL. Every other token is dropped.
 */
const RENDERER_CLASS = /^(?:hljs(?:-[\w-]+)?|[a-z]+_+|language-\S+|md-link-url)$/;

const SANITIZE_CONFIG: Config = {
  USE_PROFILES: { html: true },
  FORBID_TAGS,
  FORBID_ATTR,
  ALLOWED_URI_REGEXP,
  ALLOW_DATA_ATTR: false,
  ALLOW_ARIA_ATTR: false,
};

function keepRendererClasses(_node: Element, data: UponSanitizeAttributeHookEvent): void {
  if (data.attrName !== 'class') return;
  const kept = data.attrValue.split(/\s+/).filter((token) => RENDERER_CLASS.test(token));
  if (kept.length) data.attrValue = kept.join(' ');
  else data.keepAttr = false;
}

/**
 * A DOMPurify instance of our own: GlobalBroadcast adds and removes hooks on
 * the shared default instance around its calls, and nothing it registers
 * should ever apply here, nor ours there.
 */
function createPurifier(): Purifier {
  const instance = DOMPurify();
  instance.addHook('uponSanitizeAttribute', keepRendererClasses);
  return instance;
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * A Markdown link as inert text: the rendered label followed by the
 * destination, or the destination alone when the label already is the
 * destination (bare URLs and emails that GFM autolinks). Either way the
 * recipient sees where the link would have gone.
 */
function inertLink(label: string, token: Tokens.Link): string {
  const { href, text } = token;
  if (!href) return label;

  const shown = href === `mailto:${text}` ? text : href;
  const url = `<span class="md-link-url">${escapeHtml(shown)}</span>`;
  return text === shown ? url : `${label} (${url})`;
}

/**
 * Only languages in highlight.js's common bundle are highlighted. An unknown
 * or missing language returns the code unchanged, which tells marked-highlight
 * to escape it like any other code block. No auto-detection: a wrong guess
 * colors prose, and the cost is paid on every keystroke of the live preview.
 */
function highlightCode(code: string, lang: string): string {
  if (!lang || !hljs.getLanguage(lang)) return code;
  return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
}

function createMarked(): Marked {
  return new Marked(
    markedHighlight({
      emptyLangClass: 'hljs',
      langPrefix: 'hljs language-',
      highlight: highlightCode,
    }),
    {
      renderer: {
        link(token) {
          return inertLink(this.parser.parseInline(token.tokens), token);
        },
      },
    },
    // GFM with line breaks: a single newline becomes <br>, which is what
    // people typing a message (rather than a document) expect to see.
    { gfm: true, breaks: true }
  );
}

let marked: Marked | null = null;
let purifier: Purifier | null = null;

/**
 * Render Markdown to HTML that is safe to bind with v-html.
 *
 * @param source Markdown text as the sender typed it
 * @returns sanitized HTML fragment (empty string for empty input)
 */
export function renderMarkdown(source: string): string {
  marked ??= createMarked();
  purifier ??= createPurifier();

  const html = marked.parse(source ?? '', { async: false });
  return purifier.sanitize(html, SANITIZE_CONFIG);
}
