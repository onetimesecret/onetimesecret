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
//   address and the moment of reveal, which the product promises not to leak.
// - style and data-* attributes are dropped. The site CSP allows no inline
//   styles anyway; dropping them here keeps the output CSP-clean.
//
// MarkdownRenderer.vue imports this module dynamically, but the production
// build is a single chunk (vite.config.ts, codeSplitting: false), so the
// parser and highlighter ship in the main bundle either way.

import DOMPurify, { type Config, type DOMPurify as Purifier } from 'dompurify';
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
 * Elements that link out, fetch remote resources, accept input, or carry
 * scripts and styles. Removed on top of DOMPurify's HTML profile, which would
 * otherwise admit a, img, form controls and svg. DOMPurify keeps the text
 * content of a removed element, so a raw <a> collapses to its label.
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
];

const FORBID_ATTR = ['style', 'srcset', 'ping', 'action', 'formaction'];

const SANITIZE_CONFIG: Config = {
  USE_PROFILES: { html: true },
  FORBID_TAGS,
  FORBID_ATTR,
  ALLOWED_URI_REGEXP,
  ALLOW_DATA_ATTR: false,
};

/**
 * A DOMPurify instance of our own: GlobalBroadcast adds and removes hooks on
 * the shared default instance around its calls, and nothing it registers
 * should ever apply here.
 */
function createPurifier(): Purifier {
  return DOMPurify();
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
