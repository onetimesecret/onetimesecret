// src/tests/schemas/i18n/locale-entry.spec.ts

import { describe, it, expect } from 'vitest';
import {
  localeCodeSchema,
  sourceLocaleEntrySchema,
  translationLocaleEntrySchema,
  localeContentEntrySchema,
  localeFileSchema,
} from '@/schemas/i18n/locale';

describe('localeCodeSchema', () => {
  it('accepts 2-letter codes', () => {
    expect(localeCodeSchema.parse('en')).toBe('en');
    expect(localeCodeSchema.parse('fr')).toBe('fr');
  });

  it('accepts language_region codes', () => {
    expect(localeCodeSchema.parse('pt_BR')).toBe('pt_BR');
    expect(localeCodeSchema.parse('fr-CA')).toBe('fr-CA');
  });

  it('rejects invalid formats', () => {
    expect(() => localeCodeSchema.parse('english')).toThrow();
    expect(() => localeCodeSchema.parse('')).toThrow();
    expect(() => localeCodeSchema.parse('e')).toThrow();
  });
});

describe('sourceLocaleEntrySchema', () => {
  it('parses entry with content_hash', () => {
    const entry = sourceLocaleEntrySchema.parse({
      text: 'Hello world',
      content_hash: '9da7aece',
    });
    expect(entry.text).toBe('Hello world');
    expect(entry.content_hash).toBe('9da7aece');
    expect(entry.renderer).toBe('vue');
  });

  it('allows missing content_hash', () => {
    const entry = sourceLocaleEntrySchema.parse({ text: 'Hello' });
    expect(entry.content_hash).toBeUndefined();
  });

  it('validates hash length is exactly 8', () => {
    expect(() =>
      sourceLocaleEntrySchema.parse({ text: 'Hi', content_hash: 'abc' })
    ).toThrow();
    expect(() =>
      sourceLocaleEntrySchema.parse({ text: 'Hi', content_hash: '123456789' })
    ).toThrow();
  });

  it('accepts erb renderer for email entries', () => {
    const entry = sourceLocaleEntrySchema.parse({
      text: 'Welcome %{name}',
      content_hash: 'abcd1234',
      renderer: 'erb',
    });
    expect(entry.renderer).toBe('erb');
  });
});

describe('translationLocaleEntrySchema', () => {
  it('parses entry with source_hash', () => {
    const entry = translationLocaleEntrySchema.parse({
      text: 'Bonjour le monde',
      source_hash: '9da7aece',
    });
    expect(entry.text).toBe('Bonjour le monde');
    expect(entry.source_hash).toBe('9da7aece');
  });

  it('allows missing source_hash', () => {
    const entry = translationLocaleEntrySchema.parse({ text: 'Bonjour' });
    expect(entry.source_hash).toBeUndefined();
  });
});

describe('localeContentEntrySchema', () => {
  it('accepts source-style entries with content_hash', () => {
    const entry = localeContentEntrySchema.parse({
      text: 'Hello',
      content_hash: 'abcd1234',
    });
    expect(entry.content_hash).toBe('abcd1234');
    expect(entry.source_hash).toBeUndefined();
  });

  it('accepts translation-style entries with source_hash', () => {
    const entry = localeContentEntrySchema.parse({
      text: 'Hola',
      source_hash: 'abcd1234',
    });
    expect(entry.source_hash).toBe('abcd1234');
    expect(entry.content_hash).toBeUndefined();
  });

  it('accepts entries with both hashes (edge case)', () => {
    const entry = localeContentEntrySchema.parse({
      text: 'Test',
      content_hash: '11111111',
      source_hash: '22222222',
    });
    expect(entry.content_hash).toBe('11111111');
    expect(entry.source_hash).toBe('22222222');
  });

  it('defaults renderer to vue', () => {
    const entry = localeContentEntrySchema.parse({ text: 'Test' });
    expect(entry.renderer).toBe('vue');
  });
});

describe('localeFileSchema', () => {
  it('parses a minimal locale file', () => {
    const file = localeFileSchema.parse({
      'web.COMMON.tagline': {
        text: 'Secure links that only work once',
        content_hash: '9da7aece',
      },
    });
    expect(file['web.COMMON.tagline'].text).toBe('Secure links that only work once');
  });

  it('parses a file with mixed entry types', () => {
    const file = localeFileSchema.parse({
      'web.COMMON.tagline': {
        text: 'Secure links',
        content_hash: '9da7aece',
      },
      'email.subject': {
        text: 'Welcome %{name}',
        source_hash: 'abcd1234',
        renderer: 'erb',
      },
    });
    expect(Object.keys(file)).toHaveLength(2);
  });

  it('rejects non-object values', () => {
    expect(() =>
      localeFileSchema.parse({
        'some.key': 'just a string',
      })
    ).toThrow();
  });
});
