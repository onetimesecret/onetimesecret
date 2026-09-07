// src/tests/plugins/core/diagnostics/noiseFilters.spec.ts
//
// Tests for the third-party noise filter lists (#4287): ignoreErrors,
// denyUrls, allowUrls. The message fixtures below are verbatim from live
// production events (FRONTEND-155, -154, -14J, -183, -180, -16W, -16D,
// -17Z, -18W) so a pattern edit that stops matching the real-world shape
// fails here, not in production.

import { describe, expect, it } from 'vitest';
import {
  FIRST_PARTY_ALLOW_URLS,
  THIRD_PARTY_DENY_URLS,
  THIRD_PARTY_IGNORE_ERRORS,
} from '@/plugins/core/enableDiagnostics';

/**
 * Mirrors Sentry's stringMatchesSomePattern semantics used by
 * eventFiltersIntegration: string patterns are substring matches, regex
 * patterns are tested. None of our regexes carry the `g` flag (which would
 * make `.test()` stateful via lastIndex); the guard below enforces that.
 */
function matchesSome(value: string, patterns: (string | RegExp)[]): boolean {
  return patterns.some((pattern) =>
    typeof pattern === 'string' ? value.includes(pattern) : pattern.test(value)
  );
}

describe('THIRD_PARTY_IGNORE_ERRORS', () => {
  it('has no stateful (g-flagged) regex patterns', () => {
    for (const pattern of THIRD_PARTY_IGNORE_ERRORS) {
      if (pattern instanceof RegExp) {
        expect(pattern.flags).not.toContain('g');
      }
    }
  });

  it.each([
    // Firefox iOS reader mode (FRONTEND-155, FRONTEND-154)
    "undefined is not an object (evaluating 'window.__firefox__.reader')",
    "Can't find variable: __firefox__",
    // Outlook SafeLinks — the Id number varies per event (FRONTEND-14J)
    'Non-Error promise rejection captured with value: Object Not Found Matching Id:4, MethodName:update, ParamCount:4',
    'Object Not Found Matching Id:5, MethodName:update, ParamCount:4',
    // Android WebView teardown in Meta in-app browsers (FRONTEND-183 et al.)
    'Error invoking postMessage: Java object is gone',
    // Zalo in-app browser, both browser wordings (FRONTEND-180, FRONTEND-16W)
    'zaloJSV2 is not defined',
    "Can't find variable: zaloJSV2",
    // iOS webview bridge never answered (FRONTEND-16D)
    'WKWebView API client did not respond to this postMessage',
    // Chrome extension messaging an unloaded counterpart (FRONTEND-17Z)
    'Could not establish connection. Receiving end does not exist.',
    // Extension redefining built-ins, Firefox wording (FRONTEND-18W)
    "can't redefine non-configurable property Symbol.hasInstance",
    // Same defect, Chrome wording
    'Cannot redefine non-configurable property',
  ])('matches third-party noise: %s', (message) => {
    expect(matchesSome(message, THIRD_PARTY_IGNORE_ERRORS)).toBe(true);
  });

  it.each([
    // First-party failure shapes must keep reporting
    'Failed to fetch',
    'Network Error',
    'Schema validation failed: bootstrap',
    'Object Not Found', // without the SafeLinks "Matching Id:N" suffix
    'postMessage handler threw',
    "undefined is not an object (evaluating 'secret.value')",
  ])('does not match first-party errors: %s', (message) => {
    expect(matchesSome(message, THIRD_PARTY_IGNORE_ERRORS)).toBe(false);
  });
});

describe('THIRD_PARTY_DENY_URLS', () => {
  it.each([
    'chrome-extension://gighmmpiobklfepjocnamgkkbiglidom/content.js',
    'moz-extension://5f3c1a2b/inject.js',
    'safari-extension://com.example/script.js',
    'safari-web-extension://ABC123/content.js',
    'webkit-masked-url://hidden/',
    'iabjs://navigation_performance_logger_android',
  ])('denies extension/webview scheme: %s', (url) => {
    expect(matchesSome(url, THIRD_PARTY_DENY_URLS)).toBe(true);
  });

  it.each([
    'https://eu.onetimesecret.com/dist/assets/main.BbCc7LVY.js',
    // Scheme must be anchored at the start: a path merely mentioning an
    // extension scheme is not extension code
    'https://eu.onetimesecret.com/docs/chrome-extension://faq',
  ])('does not deny first-party URLs: %s', (url) => {
    expect(matchesSome(url, THIRD_PARTY_DENY_URLS)).toBe(false);
  });
});

describe('FIRST_PARTY_ALLOW_URLS', () => {
  it.each([
    // Production bundle, canonical domain
    'https://eu.onetimesecret.com/dist/assets/main.BbCc7LVY.js',
    // Custom domains serve the same bundle path
    'https://secrets.example.ca/dist/assets/main.BbCc7LVY.js',
    // Dev server entry (see vite_manifest.rb)
    'https://dev.onetime.dev/dist/main.ts',
  ])('allows first-party bundle URL: %s', (url) => {
    expect(matchesSome(url, FIRST_PARTY_ALLOW_URLS)).toBe(true);
  });

  it.each([
    // Injected-at-document-scope code is attributed to the page URL itself
    'https://eu.onetimesecret.com/secret/abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz',
    'https://eu.onetimesecret.com/',
    'chrome-extension://abc/content.js',
  ])('does not allow non-bundle URL: %s', (url) => {
    expect(matchesSome(url, FIRST_PARTY_ALLOW_URLS)).toBe(false);
  });
});
