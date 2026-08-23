// src/tests/utils/format/currency.spec.ts

/**
 * Unit tests for the locale-aware currency formatting wrapper (#4048).
 *
 * The wrapper reads the ACTIVE app i18n locale (globalComposer) so the
 * language switcher affects price formatting — previously formatCurrency
 * always used the browser locale, so two visitors saw different strings
 * for the same price and switching app language had no effect.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ref } from 'vue';

// Mutable locale the '@/i18n' mock exposes; specs set it per test.
const mockLocale = ref<string | null>('en');

vi.mock('@/i18n', () => ({
  globalComposer: {
    get locale() {
      return mockLocale.value === '__THROW__'
        ? (() => {
            throw new Error('i18n not initialized');
          })()
        : { value: mockLocale.value };
    },
  },
}));

import { activeIntlLocale, formatCurrency } from '@/utils/format/currency';

const intl = (locale: string | undefined, currency: string, amount: number) =>
  new Intl.NumberFormat(locale, { style: 'currency', currency }).format(amount);

describe('activeIntlLocale', () => {
  beforeEach(() => {
    mockLocale.value = 'en';
  });

  it('returns the active app locale', () => {
    mockLocale.value = 'de';
    expect(activeIntlLocale()).toBe('de');
  });

  it('normalizes underscore locale codes to BCP-47 hyphens', () => {
    mockLocale.value = 'de_AT';
    expect(activeIntlLocale()).toBe('de-AT');
    mockLocale.value = 'fr_CA';
    expect(activeIntlLocale()).toBe('fr-CA');
  });

  it('returns undefined when no app locale is set', () => {
    mockLocale.value = null;
    expect(activeIntlLocale()).toBeUndefined();
  });

  it('returns undefined when reading the composer throws', () => {
    mockLocale.value = '__THROW__';
    expect(activeIntlLocale()).toBeUndefined();
  });
});

describe('formatCurrency (locale-aware wrapper)', () => {
  beforeEach(() => {
    mockLocale.value = 'en';
  });

  it('formats using the active app locale, not the browser locale', () => {
    mockLocale.value = 'de';
    expect(formatCurrency(123456, 'EUR')).toBe(intl('de', 'EUR', 1234.56));
  });

  it('changes output when the app locale changes (language switcher)', () => {
    mockLocale.value = 'en';
    const enResult = formatCurrency(123456, 'EUR');
    mockLocale.value = 'de';
    const deResult = formatCurrency(123456, 'EUR');
    expect(enResult).toBe(intl('en', 'EUR', 1234.56));
    expect(deResult).toBe(intl('de', 'EUR', 1234.56));
    expect(enResult).not.toBe(deResult);
  });

  it('handles underscore app locales (de_AT) end to end', () => {
    mockLocale.value = 'de_AT';
    expect(formatCurrency(2900, 'EUR')).toBe(intl('de-AT', 'EUR', 29));
  });

  it('falls back to browser locale when no app locale is available', () => {
    mockLocale.value = null;
    expect(formatCurrency(2900, 'USD')).toBe(intl(undefined, 'USD', 29));
  });

  it('coerces null currency to USD instead of crashing (defect 3)', () => {
    mockLocale.value = 'en';
    expect(formatCurrency(2900, null)).toBe(intl('en', 'USD', 29));
  });

  it('degrades to plain rendering for a garbage currency code', () => {
    mockLocale.value = 'de';
    expect(formatCurrency(1999, 'NOTREAL')).toBe('19.99 NOTREAL');
  });
});
