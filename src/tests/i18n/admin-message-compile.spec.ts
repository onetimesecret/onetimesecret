// src/tests/i18n/admin-message-compile.spec.ts

/**
 * Compile-check every admin locale bundle through the real vue-i18n message
 * compiler.
 *
 * Regression guard for QA 2026-07-07: a raw `@` in a message value
 * (`web.admin.emailtools.test.toPlaceholder` = "you@example.com") is linked-
 * message syntax to vue-i18n, so the compiler threw a SyntaxError at t() time
 * and the error boundary took the ENTIRE /colonel/email-tools page down. The
 * unit suite never noticed because `createTestI18n()` is a pass-through with
 * empty messages (ADR-014) — no admin message was ever actually compiled.
 *
 * This spec reads the SOURCE bundles (locales/content/en/admin-*.json, so no
 * `locales:sync` step is required) and calls `t()` on every key with the real
 * messages loaded. Any message the compiler rejects — a raw `@` or `|`, an
 * unbalanced `{`/`}` — fails the test naming the exact key. Literal syntax
 * like `{'@'}` compiles fine.
 */

import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { createI18n } from 'vue-i18n';
import { describe, expect, it } from 'vitest';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/** Source-of-truth content bundles (flat dotted keys, {text, content_hash}). */
const CONTENT_DIR = path.resolve(__dirname, '../../../locales/content/en');

interface ContentEntry {
  text?: string;
  content_hash?: string;
}

const adminBundles = fs
  .readdirSync(CONTENT_DIR)
  .filter((file) => file.startsWith('admin-') && file.endsWith('.json'))
  .sort();

/** Nest a flat dotted-key map the way `locales:sync` does for the app. */
function nestMessages(flat: Record<string, string>): Record<string, unknown> {
  const nested: Record<string, unknown> = {};
  for (const [dottedKey, text] of Object.entries(flat)) {
    const segments = dottedKey.split('.');
    let cursor = nested;
    for (const segment of segments.slice(0, -1)) {
      cursor[segment] = (cursor[segment] as Record<string, unknown>) ?? {};
      cursor = cursor[segment] as Record<string, unknown>;
    }
    cursor[segments[segments.length - 1]] = text;
  }
  return nested;
}

describe('admin locale bundles compile under the vue-i18n message compiler', () => {
  expect(adminBundles.length).toBeGreaterThan(0);

  it.each(adminBundles)('%s: every message compiles', (bundle) => {
    const raw = JSON.parse(fs.readFileSync(path.join(CONTENT_DIR, bundle), 'utf-8')) as Record<
      string,
      ContentEntry
    >;

    const flat: Record<string, string> = {};
    for (const [key, entry] of Object.entries(raw)) {
      if (entry && typeof entry.text === 'string') flat[key] = entry.text;
    }

    // The generated DefineLocaleMessage augmentation types `messages` (and the
    // composer's t()) to the full app key schema; this spec deliberately loads
    // one raw bundle at a time, so opt this instance out of that structural
    // check with a minimal shape of its own.
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      missingWarn: false,
      fallbackWarn: false,
      messages: { en: nestMessages(flat) as never },
    }) as unknown as { global: { t: (key: string) => string } };

    const translate = i18n.global.t;

    const failures: string[] = [];
    for (const key of Object.keys(flat)) {
      try {
        // t() compiles the message lazily; a syntax error (raw @, raw |,
        // unbalanced braces) throws here — exactly what crashed the page.
        translate(key);
      } catch (error) {
        failures.push(`${key}: ${(error as Error).message}`);
      }
    }

    expect(failures, `uncompilable messages in ${bundle}:\n${failures.join('\n')}`).toEqual([]);
  });
});
