// src/tests/schemas/shapes/config/secret_options.spec.ts
//
// Coverage for the secret_options shape — the per-user-type boundaries
// schema (`secretOptionBoundariesShape`) carries every default and bound
// (TTL 60s..30d, size up to 10MB) and is composed via
// `z.record(UserTypeKeys, ...)` to form `secretOptionsShape`.

import { describe, it, expect } from 'vitest';
import { secretOptionBoundariesSchema } from '@/schemas/contracts/config/section/secret_options';
import {
  secretOptionBoundariesShape,
  secretOptionsShape,
} from '@/schemas/shapes/config/section/secret_options';

describe('secretOptionBoundariesShape — defaults', () => {
  it('applies default_ttl, ttl_options and size on empty input', () => {
    const result = secretOptionBoundariesShape.parse({});
    expect(result.default_ttl).toBe(604800);
    expect(result.ttl_options).toEqual([
      300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000,
    ]);
    expect(result.size).toBe(102400);
  });

  it('accepts null for default_ttl (preserves nullable wrapper)', () => {
    const result = secretOptionBoundariesShape.parse({ default_ttl: null });
    expect(result.default_ttl).toBeNull();
  });

  it('accepts null for ttl_options', () => {
    const result = secretOptionBoundariesShape.parse({ ttl_options: null });
    expect(result.ttl_options).toBeNull();
  });

  it('accepts null for size', () => {
    const result = secretOptionBoundariesShape.parse({ size: null });
    expect(result.size).toBeNull();
  });
});

describe('secretOptionBoundariesShape — TTL bounds', () => {
  it('rejects ttl_options entries below 60s', () => {
    expect(() => secretOptionBoundariesShape.parse({ ttl_options: [30] })).toThrow();
  });

  it('rejects ttl_options entries above 30 days', () => {
    expect(() => secretOptionBoundariesShape.parse({ ttl_options: [2592001] })).toThrow();
  });

  it('accepts boundary values 60s and 30 days', () => {
    const result = secretOptionBoundariesShape.parse({ ttl_options: [60, 2592000] });
    expect(result.ttl_options).toEqual([60, 2592000]);
  });

  it('rejects non-positive default_ttl', () => {
    expect(() => secretOptionBoundariesShape.parse({ default_ttl: 0 })).toThrow();
    expect(() => secretOptionBoundariesShape.parse({ default_ttl: -1 })).toThrow();
  });

  it('contract accepts the same bad TTL values', () => {
    expect(() => secretOptionBoundariesSchema.parse({ default_ttl: -1 })).not.toThrow();
    expect(() => secretOptionBoundariesSchema.parse({ ttl_options: [30] })).not.toThrow();
  });
});

describe('secretOptionBoundariesShape — size bounds (1..10MB)', () => {
  it('accepts the maximum size (10 MB)', () => {
    expect(secretOptionBoundariesShape.parse({ size: 10485760 }).size).toBe(10485760);
  });

  it('rejects sizes above 10 MB', () => {
    expect(() => secretOptionBoundariesShape.parse({ size: 10485761 })).toThrow();
  });

  it('rejects zero / negative sizes', () => {
    expect(() => secretOptionBoundariesShape.parse({ size: 0 })).toThrow();
    expect(() => secretOptionBoundariesShape.parse({ size: -1 })).toThrow();
  });
});

describe('secretOptionsShape — record over user types', () => {
  it('accepts a record keyed by every valid user type and applies per-entry defaults', () => {
    const result = secretOptionsShape.parse({
      anonymous: {},
      authenticated: { default_ttl: 86400 },
      standard: {},
      enhanced: {},
    });
    expect(result.anonymous?.default_ttl).toBe(604800);
    expect(result.anonymous?.size).toBe(102400);
    expect(result.authenticated?.default_ttl).toBe(86400);
    expect(result.standard?.size).toBe(102400);
  });

  it('rejects records missing a required user type', () => {
    // `z.record(z.enum([...]), ...)` requires every enum key to be present.
    expect(() => secretOptionsShape.parse({ anonymous: {} })).toThrow();
  });

  it('rejects records keyed by unknown user types', () => {
    expect(() =>
      secretOptionsShape.parse({
        anonymous: {},
        authenticated: {},
        standard: {},
        enhanced: {},
        unknown_type: {},
      })
    ).toThrow();
  });
});
