// src/tests/schemas/shapes/config/i18n.spec.ts
//
// Per-field coverage for the i18n shape. The contract requires
// `fallback_locale` (no .optional()), so every test supplies it.

import { describe, it, expect } from 'vitest';
import { i18nSchema } from '@/schemas/contracts/config/section/i18n';
import { i18nShape } from '@/schemas/shapes/config/section/i18n';

const fallback = { en: ['en'] };

describe('i18nShape — defaults applied on minimal input', () => {
  it('fills every optional field with the documented default', () => {
    const result = i18nShape.parse({ fallback_locale: fallback });
    expect(result.enabled).toBe(false);
    expect(result.default_locale).toBe('en');
    expect(result.locales).toEqual([]);
    expect(result.incomplete).toEqual([]);
    expect(result.date_format).toBe('locale');
    expect(result.datetime_format).toBe('locale');
  });

  it('preserves caller-provided values over defaults', () => {
    const result = i18nShape.parse({
      enabled: true,
      default_locale: 'fr',
      locales: ['en', 'fr'],
      incomplete: ['zh'],
      date_format: 'iso',
      datetime_format: 'iso',
      fallback_locale: fallback,
    });
    expect(result.default_locale).toBe('fr');
    expect(result.locales).toEqual(['en', 'fr']);
    expect(result.incomplete).toEqual(['zh']);
    expect(result.date_format).toBe('iso');
    expect(result.datetime_format).toBe('iso');
  });
});

describe('i18nShape — fallback_locale shape', () => {
  it('accepts a string value (single fallback)', () => {
    expect(() => i18nShape.parse({ fallback_locale: { fr: 'en' } })).not.toThrow();
  });

  it('accepts an array of locale codes', () => {
    expect(() => i18nShape.parse({ fallback_locale: { fr: ['en', 'de'] } })).not.toThrow();
  });

  it('rejects non-string/array values', () => {
    expect(() => i18nShape.parse({ fallback_locale: { fr: 1 } })).toThrow();
  });

  it('rejects missing fallback_locale entirely', () => {
    expect(() => i18nShape.parse({})).toThrow();
  });
});

describe('i18nShape — contract vs shape', () => {
  it('contract leaves all optional fields undefined', () => {
    const c = i18nSchema.parse({ fallback_locale: fallback });
    expect(c.enabled).toBeUndefined();
    expect(c.default_locale).toBeUndefined();
    expect(c.locales).toBeUndefined();
    expect(c.incomplete).toBeUndefined();
    expect(c.date_format).toBeUndefined();
    expect(c.datetime_format).toBeUndefined();
  });
});
