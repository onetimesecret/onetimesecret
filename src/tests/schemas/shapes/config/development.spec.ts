// src/tests/schemas/shapes/config/development.spec.ts
//
// Per-field coverage for the development shape. Every field on the
// contract is optional; the shape backfills five booleans/strings. The
// sections.spec.ts smoke test asserts the top-level defaults — this file
// covers the contract↔shape divergence for each field.

import { describe, it, expect } from 'vitest';
import { developmentSchema } from '@/schemas/contracts/config/section/development';
import { developmentShape } from '@/schemas/shapes/config/section/development';

describe('developmentShape — defaults applied on empty input', () => {
  it('fills every field with the documented default', () => {
    const result = developmentShape.parse({});
    expect(result).toEqual({
      enabled: false,
      debug: false,
      frontend_host: 'http://localhost:5173',
      domain_context_enabled: false,
      allow_nil_global_secret: false,
    });
  });

  it('preserves caller-provided values over defaults', () => {
    const result = developmentShape.parse({
      enabled: true,
      debug: true,
      frontend_host: 'http://dev.local:5174',
      domain_context_enabled: true,
      allow_nil_global_secret: true,
    });
    expect(result).toEqual({
      enabled: true,
      debug: true,
      frontend_host: 'http://dev.local:5174',
      domain_context_enabled: true,
      allow_nil_global_secret: true,
    });
  });
});

describe('developmentShape — contract vs shape', () => {
  it.each([
    ['enabled', undefined, false],
    ['debug', undefined, false],
    ['frontend_host', undefined, 'http://localhost:5173'],
    ['domain_context_enabled', undefined, false],
    ['allow_nil_global_secret', undefined, false],
  ])('contract leaves %s undefined; shape fills it', (field, contractExpected, shapeExpected) => {
    const c = developmentSchema.parse({}) as Record<string, unknown>;
    const s = developmentShape.parse({}) as Record<string, unknown>;
    expect(c[field]).toBe(contractExpected);
    expect(s[field]).toBe(shapeExpected);
  });
});
