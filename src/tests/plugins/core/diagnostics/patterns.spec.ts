// src/tests/plugins/core/patterns.spec.ts
//
// Unit tests for regex pattern constants exported from enableDiagnostics.
// Tests SENSITIVE_PATH_PATTERN, VERIFIABLE_ID_PATTERN, and EMAIL_PATTERN.

import { beforeEach, describe, expect, it } from 'vitest';
import {
  EMAIL_PATTERN,
  SENSITIVE_PATH_PATTERN,
  VERIFIABLE_ID_PATTERN,
} from '@/plugins/core/enableDiagnostics';

describe('SENSITIVE_PATH_PATTERN', () => {
  beforeEach(() => {
    // Reset regex lastIndex since we use global flag
    SENSITIVE_PATH_PATTERN.lastIndex = 0;
  });

  it('matches /secret/ paths', () => {
    expect('/api/v3/secret/abc123'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
  });

  it('matches /private/ paths', () => {
    expect('/api/v3/private/xyz789'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
  });

  it('matches /receipt/ paths', () => {
    expect('/api/v3/receipt/def456'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
  });

  it('matches /incoming/ paths', () => {
    expect('/api/v3/incoming/ghi012'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
  });

  it('does not match /colonel/ paths', () => {
    SENSITIVE_PATH_PATTERN.lastIndex = 0;
    expect('/api/v3/colonel/admin123'.match(SENSITIVE_PATH_PATTERN)).toBeNull();
  });

  it('does not match /public/ paths', () => {
    SENSITIVE_PATH_PATTERN.lastIndex = 0;
    expect('/api/v3/public/something'.match(SENSITIVE_PATH_PATTERN)).toBeNull();
  });
});

describe('VERIFIABLE_ID_PATTERN', () => {
  beforeEach(() => {
    VERIFIABLE_ID_PATTERN.lastIndex = 0;
  });

  it('matches 62-character base62 identifiers', () => {
    const id62 = 'a'.repeat(62);
    expect(id62.match(VERIFIABLE_ID_PATTERN)).toBeTruthy();
  });

  it('matches mixed alphanumeric 62-char IDs', () => {
    // 62 lowercase alphanumeric characters (a-z, 0-9)
    const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
    expect(id62.length).toBe(62);
    expect(id62.match(VERIFIABLE_ID_PATTERN)).toBeTruthy();
  });

  it('does not match shorter identifiers', () => {
    const id61 = 'a'.repeat(61);
    VERIFIABLE_ID_PATTERN.lastIndex = 0;
    expect(id61.match(VERIFIABLE_ID_PATTERN)).toBeNull();
  });

  it('does not match longer identifiers as a single match', () => {
    const id63 = 'a'.repeat(63);
    VERIFIABLE_ID_PATTERN.lastIndex = 0;
    // Will match the first 62 chars, but the match itself is 62 chars
    const matches = id63.match(VERIFIABLE_ID_PATTERN);
    expect(matches?.[0].length).toBe(62);
  });
});

describe('EMAIL_PATTERN', () => {
  beforeEach(() => {
    EMAIL_PATTERN.lastIndex = 0;
  });

  it('matches standard email addresses', () => {
    expect('user@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
  });

  it('matches emails with subdomains', () => {
    expect('user@mail.example.com'.match(EMAIL_PATTERN)).toBeTruthy();
  });

  it('matches emails with plus addressing', () => {
    expect('user+tag@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
  });

  it('matches emails with dots in local part', () => {
    expect('first.last@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
  });

  it('matches emails with numbers', () => {
    expect('user123@example456.com'.match(EMAIL_PATTERN)).toBeTruthy();
  });

  it('does not match invalid email formats', () => {
    EMAIL_PATTERN.lastIndex = 0;
    expect('not-an-email'.match(EMAIL_PATTERN)).toBeNull();
  });

  it('does not match email without domain', () => {
    EMAIL_PATTERN.lastIndex = 0;
    expect('user@'.match(EMAIL_PATTERN)).toBeNull();
  });
});
