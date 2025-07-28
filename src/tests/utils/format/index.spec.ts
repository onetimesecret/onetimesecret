import { ttlToNaturalLanguage } from '@/utils';
import { describe, expect, it } from 'vitest';

describe('ttlToNaturalLanguage', () => {
  it('preserves formatted strings', () => {
    expect(ttlToNaturalLanguage('24 hours')).toBe('24 hours');
    expect(ttlToNaturalLanguage('2 days')).toBe('2 days');
    expect(ttlToNaturalLanguage('custom format')).toBe('custom format');
  });

  it('transforms numeric values', () => {
    expect(ttlToNaturalLanguage(86400)).toMatch(/\d+\s+\w+/);
    expect(ttlToNaturalLanguage('86400')).toMatch(/\d+\s+\w+/);
  });

  it('handles null/undefined', () => {
    expect(ttlToNaturalLanguage(null)).toBeNull();
    expect(ttlToNaturalLanguage(undefined)).toBeNull();
  });

  it('handles leading zeros in string numbers', () => {
    expect(ttlToNaturalLanguage('08')).toBe('8 seconds from now');
    expect(ttlToNaturalLanguage('0042')).toBe('42 seconds from now');
    expect(ttlToNaturalLanguage('000360')).toBe('6 minutes from now');
  });

  it('preserves formatted strings', () => {
    expect(ttlToNaturalLanguage('24 hours')).toBe('24 hours');
    expect(ttlToNaturalLanguage('2 days')).toBe('2 days');
    expect(ttlToNaturalLanguage('custom format')).toBe('custom format');
  });

  it('transforms numeric values', () => {
    expect(ttlToNaturalLanguage(86400)).toBe('1 day from now');
    expect(ttlToNaturalLanguage('86400')).toBe('1 day from now');
    expect(ttlToNaturalLanguage(3600)).toBe('1 hour from now');
  });

  it('handles edge cases', () => {
    expect(ttlToNaturalLanguage(null)).toBeNull();
    expect(ttlToNaturalLanguage(undefined)).toBeNull();
    expect(ttlToNaturalLanguage(-1)).toBeNull();
    expect(ttlToNaturalLanguage('invalid')).toBe('invalid');
    expect(ttlToNaturalLanguage('123abc')).toBe('123abc');
    expect(ttlToNaturalLanguage('')).toBeNull();
  });

  it('handles decimal numbers', () => {
    expect(ttlToNaturalLanguage(60.5)).toBe('1 minute from now');
    expect(ttlToNaturalLanguage('60.5')).toBe('1 minute from now');
  });
});
