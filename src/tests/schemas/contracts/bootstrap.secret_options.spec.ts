// src/tests/schemas/contracts/bootstrap.secret_options.spec.ts
//
// Bounds coverage for the bootstrap contract's secretOptionsSchema.
//
// #4008 regression: this schema validates the payload Rhales renders into
// the page, so its ttl_options max is a second, independent copy of the
// TTL bound — the shapes/config schema alone raising to 365 days is not
// enough. When the two drift, an operator-configured option between 30 and
// 365 days passes config validation but fails bootstrap validation, and
// the whole secret_options block falls back to defaults.

import { describe, expect, it } from 'vitest';
import { secretOptionsSchema } from '@/schemas/contracts/bootstrap';

describe('bootstrap secretOptionsSchema — ttl_options bounds', () => {
  it('accepts entries between 30 and 365 days (#4008)', () => {
    const ninetyDays = 90 * 86400;
    const result = secretOptionsSchema.parse({ ttl_options: [ninetyDays] });
    expect(result.ttl_options).toEqual([ninetyDays]);
  });

  it('accepts boundary values 60s and 365 days', () => {
    const result = secretOptionsSchema.parse({ ttl_options: [60, 31536000] });
    expect(result.ttl_options).toEqual([60, 31536000]);
  });

  it('rejects entries above 365 days (MAX_TTL)', () => {
    expect(() => secretOptionsSchema.parse({ ttl_options: [31536001] })).toThrow();
  });

  it('rejects entries below 60s', () => {
    expect(() => secretOptionsSchema.parse({ ttl_options: [30] })).toThrow();
  });
});
