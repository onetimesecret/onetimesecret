// src/tests/schemas/i18n/locale.spec.ts
//
// Unit tests for localeCodeSchema (#4284): the schema must accept every
// well-formed BCP 47 tag browsers actually send, not just xx / xx-XX. The
// supported-locales gate lives in languageStore, not here — this schema only
// answers "is this a locale-shaped string at all".

import { describe, expect, it } from 'vitest';
import { localeCodeSchema } from '@/schemas/i18n/locale';

describe('localeCodeSchema', () => {
  describe('accepts well-formed BCP 47 tags', () => {
    it.each([
      'en',
      'fr',
      'eo',
      'en-CA',
      'pt-BR',
      'DE-at', // case-insensitive
      'it_IT', // server-side underscore form
      'IT_IT',
      'es-419', // UN M.49 region (#4284)
      'zh-Hant-TW', // script subtag (#4284)
      'en-US-POSIX', // variant subtag (#4284)
      'sr-Cyrl-RS',
      'de-DE-u-co-phonebk', // extension subtags survive canonicalization
    ])('%s', (tag) => {
      const result = localeCodeSchema.safeParse(tag);
      expect(result.success).toBe(true);
    });
  });

  describe('rejects malformed input', () => {
    it.each([
      '', // too short
      'e', // too short
      'invalid!', // illegal character
      'en US', // space is not a separator
      'a-DE', // one-letter primary subtag is not a language
      '123', // digits are not a language subtag
      'en-', // dangling separator
      'abcdefghij-US', // primary subtag over 8 chars
      'en-US-'.repeat(10), // over the 35-char bound
    ])('%s', (tag) => {
      const result = localeCodeSchema.safeParse(tag);
      expect(result.success).toBe(false);
    });
  });

  it('does not transform the input value', () => {
    // Consumers (languageStore, brand settings) rely on getting back the
    // exact string they passed in; normalization to the server's it_IT
    // format happens in validateAndNormalizeLocale, not in the schema.
    expect(localeCodeSchema.parse('it_IT')).toBe('it_IT');
    expect(localeCodeSchema.parse('zh-Hant-TW')).toBe('zh-Hant-TW');
  });
});
