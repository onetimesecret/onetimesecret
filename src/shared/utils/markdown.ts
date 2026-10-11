// src/shared/utils/markdown.ts
//
// Markdown -> sanitized HTML for secrets whose display_type is 'markdown'.
//
// The source is written by the sender and rendered in the recipient's
// browser, so the output is treated as hostile all the way through: marked
// parses, highlight.js colors fenced code, and a dedicated DOMPurify instance
// decides what reaches the DOM. On top of DOMPurify's HTML profile:
//
// - Elements that load remote resources (img, video, iframe, ...) are
//   stripped. A tracking pixel would tell the sender the recipient's IP
//   address and the moment of reveal, which the product promises not to leak.
// - Links keep only http(s)/mailto schemes (javascript:, data:, vbscript: are
//   dropped), open in a new tab, and carry rel="noopener noreferrer nofollow".
// - style and data-* attributes are dropped. The site CSP allows no inline
//   styles anyway; dropping them here keeps the output CSP-clean.
//
// Loaded lazily by MarkdownRenderer.vue so plain-text secrets never pay for
// the parser and highlighter.

import DOMPurify, { type Config, type DOMPurify as Purifier } from 'dompurify';
import hljs from 'highlight.js/lib/common';
import { Marked } from 'marked';
import { markedHighlight } from 'marked-highlight';

/**
 * DOMPurify's default URI pattern with the scheme allowlist reduced to
 * https/http/mailto. Relative URLs carry no scheme and pass. Mirrors the
 * pattern GlobalBroadcast.vue uses for operator-controlled content.
 */
const ALLOWED_URI_REGEXP = /^(?:(?:https?|mailto):|[^a-z]|[a-z+.-]+(?:[^a-z+.:-]|$))/i;

/**
 * Elements that fetch remote resources, accept input, or carry scripts and
 * styles. Removed on top of DOMPurify's HTML profile, which would otherwise
 * admit img, form controls and svg.
 */
const FORBID_TAGS = [
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
 * Every surviving anchor opens in a new tab without a window.opener and
 * without passing the secret page as a referrer. Runs after attribute
 * sanitization, so an href that failed ALLOWED_URI_REGEXP is already gone.
 */
function hardenAnchor(node: Element): void {
  if (node.tagName !== 'A') return;
  node.setAttribute('target', '_blank');
  node.setAttribute('rel', 'noopener noreferrer nofollow');
}

/**
 * A DOMPurify instance of our own: hooks are per instance, so registering
 * hardenAnchor here cannot leak into other sanitize() callers (GlobalBroadcast
 * adds and removes its hook around every call for the same reason).
 */
function createPurifier(): Purifier {
  const purifier = DOMPurify();
  purifier.addHook('afterSanitizeAttributes', hardenAnchor);
  return purifier;
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
