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
 * `onclick="window.apxDns.verifyRecords()"`. Inline handlers cannot run under
 * the nonce-only script-src, and keeping them would mean trusting remote
 * script. They are never evaluated: a call to a known widget function with
 * the expected argument shape becomes `data-apxdns-action` (and
 * `data-apxdns-arg`), which the widget dispatches from one delegated listener
 * on its root. Every other `on*` attribute is dropped.
 *
 * Beyond DOMPurify's defaults the config:
 * - allows only the tags an instructions fragment needs (no form, style,
 *   media, or embedding elements);
 * - drops `style`, `form` and `formaction`, so markup cannot restyle the page
 *   or submit one of the app's own forms;
 * - restricts URL schemes to https and mailto (relative URLs carry no scheme
 *   and pass), so javascript:, data: (except image sources), vbscript: etc.
 *   are removed;
 * - keeps only the widget's own `apxdns*` class and id names, so remote markup
 *   cannot borrow the app's utility classes to overlay the page or claim ids
 *   the app looks up;
 * - allows `target` only as `_blank` and forces rel="noopener noreferrer".
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

// `window.apxDns.fn(` with optional `return` and optional `window.` prefix.
const CALL_HEAD = /^\s*(?:return\s+)?(?:window\.)?apxDns\.([A-Za-z]+)\s*\(/;
// After the call: an optional `;` and an optional `return false|true;`.
const CALL_TAIL = /^\s*;?\s*(?:return\s+(?:true|false)\s*;?\s*)?$/;
// A single quoted identifier, e.g. 'manual-abc123'.
const IDENTIFIER_ARG = /^\s*(['"])([\w-]{1,128})\1\s*$/;

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
  FORBID_ATTR: ['style', 'form', 'formaction'],
  ALLOWED_URI_REGEXP,
};

function isActionName(name: string): name is DnsWidgetActionName {
  return (DNS_WIDGET_ACTIONS as readonly string[]).includes(name);
}

/** Index of the `)` closing a call whose `(` ends just before `from`, or -1. */
function findClosingParen(code: string, from: number): number {
  let depth = 1;
  let quote: string | null = null;
  for (let i = from; i < code.length; i++) {
    const ch = code[i];
    if (quote) {
      if (ch === '\\') i++;
      else if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === '`') quote = ch;
    else if (ch === '(') depth++;
    else if (ch === ')' && --depth === 0) return i;
  }
  return -1;
}

/**
 * Recognise an inline handler that is exactly one call to a known widget
 * function. Returns null for anything else; the handler text is never
 * evaluated either way.
 */
export function parseInlineAction(code: string): DnsWidgetAction | null {
  if (code.length > MAX_HANDLER_LENGTH) return null;

  const head = CALL_HEAD.exec(code);
  if (!head || !isActionName(head[1])) return null;
  const name = head[1];

  const close = findClosingParen(code, head[0].length);
  if (close === -1 || !CALL_TAIL.test(code.slice(close + 1))) return null;
  const args = code.slice(head[0].length, close);

  switch (name) {
    case 'restart':
    case 'verifyRecords':
      return args.trim() === '' ? { name } : null;
    case 'showManualInstructions': {
      const match = IDENTIFIER_ARG.exec(args);
      return match ? { name, arg: match[2] } : null;
    }
    case 'copyInputText':
      // The argument names the field to copy (e.g. `this.previousElementSibling`).
      // The widget's delegated handler finds that field from the clicked
      // button's copy container instead, so the argument is not needed.
      return { name };
  }
}

/** beforeSanitizeAttributes: turn allowlisted inline handlers into data attributes. */
function translateInlineHandlers(node: Element): void {
  if (node.nodeType !== 1 || !node.attributes) return;

  const handlers = Array.from(node.attributes).filter((attr) =>
    attr.name.toLowerCase().startsWith('on')
  );
  if (handlers.length === 0) return;

  for (const attr of handlers) {
    node.removeAttribute(attr.name);
    const action = attr.name.toLowerCase() === 'onclick' ? parseInlineAction(attr.value) : null;
    if (action) {
      node.setAttribute(ACTION_ATTR, action.name);
      if (action.arg !== undefined) node.setAttribute(ACTION_ARG_ATTR, action.arg);
    } else if (attr.value.includes('apxDns')) {
      // The widget's markup changed shape; the control it drives will be inert.
      loggingService.warn('[dnsWidgetHtml] dropped unrecognised widget handler', {
        attribute: attr.name,
      });
    }
  }
}

/** uponSanitizeAttribute: keep only the widget's own class and id names. */
function restrictWidgetNames(
  _node: Element,
  event: { attrName: string; attrValue: string; keepAttr: boolean }
): void {
  if (event.attrName === 'class') {
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
  if (node.tagName !== 'A') return;

  const target = node.getAttribute('target');
  if (target !== null && target !== '_blank') node.removeAttribute('target');
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
    purifier.addHook('uponSanitizeAttribute', restrictWidgetNames);
    purifier.addHook('afterSanitizeAttributes', hardenElement);
  }
  return purifier;
}

/**
 * Sanitize an HTML string from the DNS widget's remote API for insertion into
 * the widget root. Returns markup with no script, no inline handlers and no
 * script-capable URLs; widget actions survive as `data-apxdns-action`.
 */
export function sanitizeDnsWidgetHtml(html: string): string {
  return getPurifier().sanitize(String(html), SANITIZE_CONFIG);
}
