// src/tests/schemas/shapes/config/limits.spec.ts
//
// The limits shape has no defaults or value constraints — each rate limit
// is an optional number with a catchall for unknown keys. This is a
// convention guard against silent drift.

import { describe, it, expect } from 'vitest';
import { limitsSchema } from '@/schemas/contracts/config/section/limits';
import { limitsShape } from '@/schemas/shapes/config/section/limits';

describe('limits shape — re-export convention', () => {
  it('limitsShape is the contract schema (no augmentation)', () => {
    expect(limitsShape).toBe(limitsSchema);
  });

  it('accepts known rate-limit keys with numeric values', () => {
    const result = limitsShape.parse({
      create_secret: 10,
      show_secret: 100,
    });
    expect(result.create_secret).toBe(10);
    expect(result.show_secret).toBe(100);
  });

  it('passes unknown keys through the catchall as numbers', () => {
    const result = limitsShape.parse({ custom_op: 5 });
    expect((result as Record<string, number>).custom_op).toBe(5);
  });

  it('rejects non-numeric values on catchall keys', () => {
    expect(() => limitsShape.parse({ custom_op: 'lots' })).toThrow();
  });
});
