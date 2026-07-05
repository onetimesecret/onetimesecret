// src/tests/utils/pii.spec.ts

/**
 * Tests for the PII helpers that back the "no PII in the URL" policy:
 *  - sanitizeDisplayEmail: a display gate, not a validator.
 *  - findPiiQueryKeys: powers the dev-time navigation guard.
 *  - PII_QUERY_KEYS: the shared key list.
 */

import { describe, it, expect } from 'vitest';
import {
  PII_QUERY_KEYS,
  MAX_EMAIL_LENGTH,
  sanitizeDisplayEmail,
  findPiiQueryKeys,
} from '@/utils/pii';

describe('sanitizeDisplayEmail', () => {
  it('returns a plausible address unchanged', () => {
    expect(sanitizeDisplayEmail('tom@myspace.com')).toBe('tom@myspace.com');
    expect(sanitizeDisplayEmail('a+b.c_d%e@sub.example.co.uk')).toBe('a+b.c_d%e@sub.example.co.uk');
  });

  it('rejects non-strings', () => {
    expect(sanitizeDisplayEmail(undefined)).toBe('');
    expect(sanitizeDisplayEmail(null)).toBe('');
    expect(sanitizeDisplayEmail(12345)).toBe('');
    expect(sanitizeDisplayEmail({ email: 'x@y.com' })).toBe('');
    expect(sanitizeDisplayEmail(['x@y.com'])).toBe('');
  });

  it('rejects empty and whitespace-only-of-length-zero input', () => {
    expect(sanitizeDisplayEmail('')).toBe('');
  });

  it('rejects strings without an @', () => {
    expect(sanitizeDisplayEmail('not-an-email')).toBe('');
    expect(sanitizeDisplayEmail('plainaddress')).toBe('');
  });

  it('rejects over-long input (> RFC max) to avoid rendering junk verbatim', () => {
    const tooLong = 'x'.repeat(MAX_EMAIL_LENGTH) + '@e.com'; // length > 254
    expect(tooLong.length).toBeGreaterThan(MAX_EMAIL_LENGTH);
    expect(sanitizeDisplayEmail(tooLong)).toBe('');

    const atMax = 'x'.repeat(MAX_EMAIL_LENGTH - 'a@e.com'.length) + 'a@e.com';
    expect(atMax.length).toBe(MAX_EMAIL_LENGTH);
    expect(sanitizeDisplayEmail(atMax)).toBe(atMax); // exactly at the limit is allowed
  });
});

describe('PII_QUERY_KEYS', () => {
  it('includes email and the common secret-bearing keys', () => {
    expect(PII_QUERY_KEYS).toContain('email');
    expect(PII_QUERY_KEYS).toContain('token');
    expect(PII_QUERY_KEYS).toContain('password');
    expect(PII_QUERY_KEYS).toContain('key');
    expect(PII_QUERY_KEYS).toContain('code');
  });
});

describe('findPiiQueryKeys', () => {
  it('returns the PII keys present with a non-empty value', () => {
    expect(findPiiQueryKeys({ email: 'x@y.com', product: 'identity' })).toEqual(['email']);
    expect(findPiiQueryKeys({ token: 'abc', code: '123' }).sort()).toEqual(['code', 'token']);
  });

  it('ignores non-PII keys entirely', () => {
    expect(findPiiQueryKeys({ product: 'identity', interval: 'month', redirect: '/x' })).toEqual([]);
  });

  it('treats empty / null values as absent', () => {
    expect(findPiiQueryKeys({ email: '' })).toEqual([]);
    expect(findPiiQueryKeys({ email: null })).toEqual([]);
    expect(findPiiQueryKeys({ email: undefined })).toEqual([]);
  });

  it('detects array-valued PII params (?email[]=a&email[]=b)', () => {
    expect(findPiiQueryKeys({ email: ['a@b.com', 'c@d.com'] })).toEqual(['email']);
    expect(findPiiQueryKeys({ email: [] })).toEqual([]);
    expect(findPiiQueryKeys({ email: ['', null] })).toEqual([]);
  });

  it('handles null / undefined / empty query objects', () => {
    expect(findPiiQueryKeys(null)).toEqual([]);
    expect(findPiiQueryKeys(undefined)).toEqual([]);
    expect(findPiiQueryKeys({})).toEqual([]);
  });
});
