// src/shared/utils/dnsWidgetHtml.ts

import { loggingService } from '@/services/logging.service';
import DOMPurify, { type Config, type DOMPurify as Purifier } from 'dompurify';

/**
 * Sanitizer for the HTML the vendored Approximated DNS widget
 * (src/assets/approximated/dnswidget.v1.js) receives from its remote API
 * (RISK-2026-08-14-M09).
 *
 * The widget renders provider instructions and its verify section from
 * `inst.html` / `verify_section.html` strings returned by the Approximated
 * API. useDnsWidget installs this function as `window.apxDns.sanitizeHtml`;
 * the patched widget routes every remote or API-derived HTML string through
 * it and inserts plain text when it is missing (fail closed).
 *
 * That markup drives the widget with inline handlers such as
 * `onclick="window.apxDns.verifyRecords()"` (or a `javascript:` href carrying
 * the same call). Inline handlers cannot run under the nonce-only script-src,
 * and keeping them would mean trusting remote script. They are never
 * evaluated: a call to a known widget function with the expected argument
 * shape (see parseInlineAction) becomes `data-apxdns-action` (and
 * `data-apxdns-arg`), which the widget dispatches from one delegated listener
 * on its root. Every other `on*` attribute is dropped, and any other
 * `javascript:` URL is removed by the scheme rule below.
 *
 * Beyond DOMPurify's defaults the config:
 * - allows only the tags an instructions fragment needs (no form, style,
 *   media, or embedding elements);
 * - drops `style`, `form` and `formaction`, so markup cannot restyle the page
 *   or submit one of the app's own forms;
 * - drops `for`, `popovertarget(action)`, `command` and `commandfor`, which
 *   let a click inside the widget act on an app element by id;
 * - restricts URL schemes to https and mailto (relative URLs carry no scheme
 *   and pass), so javascript:, data:, vbscript: etc. are removed;
 * - drops `src`, `srcset`, `poster` and `background` outright, so rendering
 *   cannot fire a request at an app route (`<img src="/logout">`, or the
 *   same URL spelled absolute). The CSP's `img-src 'self' data:` would block
 *   a cross-origin image anyway, so an https-only rule could only ever let
 *   same-origin requests through. Images in remote markup render as alt text;
 * - drops any attribute (other than plain-text ones such as alt or title)
 *   whose value contains a CSS `url(...)` or image function other than a
 *   same-document `url(#id)`: SVG `fill`, `filter`, `mask`, `clip-path`,
 *   `marker-*` ..., escaped spellings included;
 * - keeps only the widget's own `apxdns*` class and id names, so remote markup
 *   cannot borrow the app's utility classes to overlay the page or claim ids
 *   the app looks up;
 * - on HTML anchors allows `target` only as `_blank`; SVG anchors lose
 *   `target`. Every anchor gets rel="noopener noreferrer".
 *
 * If DOMPurify reports the environment unsupported, it would return its input
 * unchanged; this function then returns the input escaped, which renders as
 * the same plain text the widget inserts when no sanitizer is installed.
 */

/** Widget functions remote markup may invoke, keyed by name. */
export const DNS_WIDGET_ACTIONS = [
  'copyInputText',
  'restart',
  'showManualInstructions',
  'verifyRecords',
] as const;

export type DnsWidgetActionName = (typeof DNS_WIDGET_ACTIONS)[number];

export interface DnsWidgetAction {
  name: DnsWidgetActionName;
  /** Present for showManualInstructions: the `data-apxid` it toggles. */
  arg?: string;
}

export const ACTION_ATTR = 'data-apxdns-action';
export const ACTION_ARG_ATTR = 'data-apxdns-arg';

const MAX_HANDLER_LENGTH = 256;
// Longest string argument, e.g. a data-apxid value such as 'manual-example.com'.
const MAX_STRING_ARG_LENGTH = 128;

const JAVASCRIPT_URL = /^javascript:/i;
const NAME_START = /[A-Za-z_$]/;
const NAME = /^[A-Za-z_$][\w$]*/;
const WHITESPACE = /\s/;

// Mirrors DOMPurify's default pattern with the scheme list reduced to
// https/mailto. Same structure as GlobalBroadcast.vue: non-URL attribute
// values (type="text", viewBox, path data) must still pass.
const ALLOWED_URI_REGEXP = /^(?:(?:https|mailto):|[^a-z]|[a-z+.-]+(?:[^a-z+.:-]|$))/i;

const WIDGET_NAME = /^apxdns[\w-]*$/;
// The spinner class the widget's stylesheet scopes under .apxdnswidget.
const EXTRA_CLASSES = new Set(['loader']);

const SANITIZE_CONFIG: Config = {
  ALLOWED_TAGS: [
    // HTML
    'a', 'b', 'br', 'button', 'code', 'div', 'em', 'h1', 'h2', 'h3', 'h4', 'h5',
    'h6', 'hr', 'i', 'img', 'input', 'kbd', 'label', 'li', 'ol', 'p', 'pre',
    'small', 'span', 'strong', 'sub', 'sup', 'table', 'tbody', 'td', 'textarea',
    'th', 'thead', 'tr', 'u', 'ul',
    // SVG icons
    'svg', 'circle', 'ellipse', 'g', 'line', 'path', 'polygon', 'polyline', 'rect',
  ],
  ADD_ATTR: ['target'],
  FORBID_ATTR: [
    'style',
    'form',
    'formaction',
    // Act on an element elsewhere in the document by id.
    'for',
    'popovertarget',
    'popovertargetaction',
    'command',
    'commandfor',
    // Fetched on render. Remote markup may not make the page request anything.
    'src',
    'srcset',
    'poster',
    'background',
    // A named img/a/form/embed/object becomes a window or document property
    // and can shadow a global the app reads.
    'name',
  ],
  ALLOWED_URI_REGEXP,
};

// CSS functions that load a resource: url() and the image functions that take
// a plain string (`mask="image-set('/logout' 1x)"`). CSS ignores case.
const CSS_FETCH_FUNCTION = /(?:url|src|image-set|image|cross-fade|element)\s*\(/i;
// The one url() kept: a reference to an element in this document, url(#id).
const FRAGMENT_URL_ONLY = /^url\(\s*#[A-Za-z_][\w-]*\s*\)$/i;
// Attributes the browser only ever shows as text, never parses as CSS.
const TEXT_ATTRIBUTE = /^(?:alt|title|value|placeholder|aria-[\w-]+|data-[\w.-]+)$/;

const SVG_NAMESPACE = 'http://www.w3.org/2000/svg';

function isActionName(name: string): name is DnsWidgetActionName {
  return (DNS_WIDGET_ACTIONS as readonly string[]).includes(name);
}

type Token = { kind: 'name' | 'punct' | 'string'; value: string };

/**
 * A string literal's body: 1-128 characters with no quote of any kind, no
 * backslash (so no escapes) and no control character.
 */
function isPlainStringBody(body: string): boolean {
  if (body.length === 0 || body.length > MAX_STRING_ARG_LENGTH) return false;
  for (const ch of body) {
    const code = ch.charCodeAt(0);
    if (code < 0x20 || code === 0x7f || `'"\`\\`.includes(ch)) return false;
  }
  return true;
}

/**
 * Split handler text into names, `.` `(` `)` `;` and plain quoted strings.
 * Null on anything else: operators, template literals, braces, commas.
 */
function tokenize(code: string): Token[] | null {
  const tokens: Token[] = [];
  for (let i = 0; i < code.length; ) {
    const read = readToken(code, i);
    if (!read) return null;
    if (read.token) tokens.push(read.token);
    i = read.next;
  }
  return tokens;
}

/** The token at `i` (null for whitespace) and where the next one starts. */
function readToken(code: string, i: number): { token: Token | null; next: number } | null {
  const ch = code[i];
  if (WHITESPACE.test(ch)) return { token: null, next: i + 1 };
  if (NAME_START.test(ch)) {
    const name = NAME.exec(code.slice(i))![0];
    return { token: { kind: 'name', value: name }, next: i + name.length };
  }
  if ('.();'.includes(ch)) return { token: { kind: 'punct', value: ch }, next: i + 1 };
  if (ch === "'" || ch === '"') {
    const end = code.indexOf(ch, i + 1);
    const body = end === -1 ? '' : code.slice(i + 1, end);
    return isPlainStringBody(body) ? { token: { kind: 'string', value: body }, next: end + 1 } : null;
  }
  return null;
}

type Cursor = ReturnType<typeof cursorOver>;

/** A read position over tokens. */
function cursorOver(tokens: Token[]) {
  let pos = 0;
  const isWord = (token: Token | undefined, value: string) =>
    token !== undefined && token.kind !== 'string' && token.value === value;
  return {
    /** Whether the next token is the name or punctuation `value`. */
    peek: (value: string) => isWord(tokens[pos], value),
    /** Consume `values` if the next tokens are exactly those; else nothing. */
    accept(...values: string[]): boolean {
      if (!values.every((value, k) => isWord(tokens[pos + k], value))) return false;
      pos += values.length;
      return true;
    },
    /** Consume and return the next token's value if it is of `kind`. */
    take(kind: Token['kind']): string | null {
      const token = tokens[pos];
      if (token?.kind !== kind) return null;
      pos++;
      return token.value;
    },
    done: () => pos === tokens.length,
  };
}

/**
 * copyInputText's argument names the field to copy, e.g.
 * `this.previousElementSibling` or `this.parentElement.querySelector('input')`.
 * Accept such a reference (or none) without evaluating it: the widget's
 * delegated handler finds the field from the clicked button instead.
 */
function acceptElementReference(c: Cursor): boolean {
  if (c.peek(')')) return true;
  if (!c.accept('this') && !c.accept('document')) return false;
  while (c.accept('.')) {
    if (c.take('name') === null) return false;
    if (c.accept('(') && (c.take('string') === null || !c.accept(')'))) return false;
  }
  return true;
}

function parseArguments(name: DnsWidgetActionName, c: Cursor): DnsWidgetAction | null {
  switch (name) {
    case 'restart':
    case 'verifyRecords':
      return { name };
    case 'showManualInstructions': {
      const arg = c.take('string');
      return arg === null ? null : { name, arg };
    }
    case 'copyInputText':
      return acceptElementReference(c) ? { name } : null;
  }
}

/**
 * Recognise an inline handler that is exactly one call to a known widget
 * function, in the shape
 *
 *   [event.preventDefault();] [return] [window.]apxDns.<action>(<args>)
 *     [;] [return false|true] [;]
 *
 * where <args> is empty for restart and verifyRecords, one single- or
 * double-quoted string for showManualInstructions (1-128 characters, no
 * quotes, backslashes or control characters), and an element reference for
 * copyInputText. Returns null for anything else (more statements,
 * concatenation, template literals, other functions); the handler text is
 * never evaluated either way. The action comes from a fixed list and the
 * string is only ever compared with data-apxid values, so accepting any such
 * string widens nothing.
 */
export function parseInlineAction(code: string): DnsWidgetAction | null {
  if (code.length > MAX_HANDLER_LENGTH) return null;
  const tokens = tokenize(code);
  if (!tokens) return null;
  const c = cursorOver(tokens);

  acceptPrefix(c);
  const action = parseCall(c);
  return action && acceptSuffix(c) ? action : null;
}

/** `[event.preventDefault();] [return]` before the call. */
function acceptPrefix(c: Cursor): void {
  if (c.accept('event', '.', 'preventDefault', '(', ')')) c.accept(';');
  c.accept('return');
}

/** `[window.]apxDns.<action>(<args>)`. */
function parseCall(c: Cursor): DnsWidgetAction | null {
  c.accept('window', '.');
  if (!c.accept('apxDns', '.')) return null;
  const name = c.take('name');
  if (name === null || !isActionName(name) || !c.accept('(')) return null;
  const action = parseArguments(name, c);
  return action && c.accept(')') ? action : null;
}

/** `[;] [return false|true] [;]` and nothing else after the call. */
function acceptSuffix(c: Cursor): boolean {
  c.accept(';');
  if (c.accept('return') && !c.accept('false') && !c.accept('true')) return false;
  c.accept(';');
  return c.done();
}

/**
 * The widget call carried by a `javascript:` URL, if it is exactly one call
 * parseInlineAction accepts. Browsers drop tabs and newlines in a URL and
 * percent-decode a javascript: URL before running it; this reads it the same
 * way, without running it.
 */
export function parseJavascriptUrlAction(url: string): DnsWidgetAction | null {
  const normalized = normalizeUrl(url);
  if (!JAVASCRIPT_URL.test(normalized)) return null;
  try {
    return parseInlineAction(decodeURIComponent(normalized.slice('javascript:'.length)));
  } catch {
    return null; // malformed percent-encoding
  }
}

function normalizeUrl(url: string): string {
  return url.replace(/[\t\n\r]/g, '').trim();
}

/**
 * The widget action an attribute carries, if any. `on*` attributes are always
 * removed; a recognised `javascript:` href is removed here, and any other is
 * left for the scheme rule to drop.
 */
function attributeAction(node: Element, attr: Attr): DnsWidgetAction | null {
  const name = attr.name.toLowerCase();
  let action: DnsWidgetAction | null = null;
  if (name.startsWith('on')) {
    node.removeAttribute(attr.name);
    if (name === 'onclick') action = parseInlineAction(attr.value);
  } else if (name === 'href' || name === 'xlink:href') {
    action = parseJavascriptUrlAction(attr.value);
    if (action) node.removeAttribute(attr.name);
    else if (!JAVASCRIPT_URL.test(normalizeUrl(attr.value))) return null;
  } else {
    return null;
  }
  if (!action && attr.value.includes('apxDns')) {
    // The widget's markup changed shape; the control it drives will be inert.
    loggingService.warn('[dnsWidgetHtml] dropped unrecognised widget handler', {
      attribute: attr.name,
    });
  }
  return action;
}

/**
 * beforeSanitizeAttributes: turn allowlisted inline handlers and
 * `javascript:` hrefs into data attributes. The first recognised one wins.
 */
function translateInlineHandlers(node: Element): void {
  if (node.nodeType !== 1 || !node.attributes) return;

  let action: DnsWidgetAction | null = null;
  for (const attr of Array.from(node.attributes)) {
    // Called for every attribute: it also removes the handlers it reads.
    const found = attributeAction(node, attr);
    action ??= found;
  }
  if (action) {
    node.setAttribute(ACTION_ATTR, action.name);
    if (action.arg !== undefined) node.setAttribute(ACTION_ARG_ATTR, action.arg);
  }
}

/**
 * Whether an attribute value can make the browser fetch through CSS: any
 * url() or image function, except exactly one `url(#id)`. A backslash next to
 * a `(` counts too, since a CSS escape can spell `url` (`\75 rl(`).
 */
function hasFetchingCssValue(name: string, value: string): boolean {
  if (TEXT_ATTRIBUTE.test(name) || FRAGMENT_URL_ONLY.test(value.trim())) return false;
  return CSS_FETCH_FUNCTION.test(value) || (value.includes('\\') && value.includes('('));
}

/**
 * uponSanitizeAttribute: drop fetching CSS url() values, and keep only the
 * widget's own class and id names.
 */
function restrictWidgetAttributes(
  _node: Element,
  event: { attrName: string; attrValue: string; keepAttr: boolean }
): void {
  if (hasFetchingCssValue(event.attrName, event.attrValue)) {
    event.keepAttr = false;
  } else if (event.attrName === 'class') {
    const kept = event.attrValue
      .split(/\s+/)
      .filter((token) => WIDGET_NAME.test(token) || EXTRA_CLASSES.has(token));
    event.attrValue = kept.join(' ');
    if (kept.length === 0) event.keepAttr = false;
  } else if (event.attrName === 'id' && !WIDGET_NAME.test(event.attrValue)) {
    event.keepAttr = false;
  }
}

/** afterSanitizeAttributes: anchor hardening and keyboard access for actions. */
function hardenElement(node: Element): void {
  // localName, not tagName: an SVG anchor's tagName is lower-case 'a'.
  if (node.localName !== 'a') return;

  // SVG anchors cannot be relied on to honour rel, so they never open a new
  // browsing context.
  const target = node.getAttribute('target');
  if (target !== null && (target !== '_blank' || node.namespaceURI === SVG_NAMESPACE)) {
    node.removeAttribute('target');
  }
  node.setAttribute('rel', 'noopener noreferrer');

  // A `javascript:void(0)` href was removed above; give the action back a
  // focusable href so it stays reachable by keyboard. The widget's delegated
  // listener cancels the navigation.
  if (node.hasAttribute(ACTION_ATTR) && !node.hasAttribute('href')) {
    node.setAttribute('href', '#');
  }
}

let purifier: Purifier | null = null;

/**
 * A private DOMPurify instance, so these hooks never apply to other callers
 * of the shared default instance (GlobalBroadcast, etc.).
 */
function getPurifier(): Purifier {
  if (!purifier) {
    purifier = DOMPurify(window);
    purifier.addHook('beforeSanitizeAttributes', translateInlineHandlers);
    purifier.addHook('uponSanitizeAttribute', restrictWidgetAttributes);
    purifier.addHook('afterSanitizeAttributes', hardenElement);
  }
  return purifier;
}

/** Escape a string so inserting it as HTML yields the same text node. */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Sanitize an HTML string from the DNS widget's remote API for insertion into
 * the widget root. Returns markup with no script, no inline handlers and no
 * script-capable URLs; widget actions survive as `data-apxdns-action`.
 *
 * Where DOMPurify is unsupported (it would pass the input through), returns
 * the input escaped: plain text, as when no sanitizer is installed.
 */
export function sanitizeDnsWidgetHtml(html: string): string {
  const source = String(html);
  const instance = getPurifier();
  if (!instance.isSupported) return escapeHtml(source);
  return instance.sanitize(source, SANITIZE_CONFIG);
}
