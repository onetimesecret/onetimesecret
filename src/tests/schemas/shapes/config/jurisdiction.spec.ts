// src/tests/schemas/shapes/config/jurisdiction.spec.ts
//
// Coverage for the jurisdiction shape — the identifier length bounds
// (2–24) and the `enabled` default. The contract carries neither.

import { describe, it, expect } from 'vitest';
import {
  jurisdictionSchema,
  regionsConfigSchema,
} from '@/schemas/contracts/config/section/jurisdiction';
import {
  jurisdictionShape,
  regionsConfigShape,
  jurisdictionIconShape,
  jurisdictionDetailsShape,
} from '@/schemas/shapes/config/section/jurisdiction';

const minimal = {
  identifier: 'eu',
  display_name_i18n_key: 'web.regions.eu',
  domain: 'eu.example.com',
};

describe('jurisdictionShape — defaults', () => {
  it('enabled defaults to true', () => {
    expect(jurisdictionShape.parse(minimal).enabled).toBe(true);
  });

  it('contract leaves enabled undefined', () => {
    expect(jurisdictionSchema.parse(minimal).enabled).toBeUndefined();
  });

  it('preserves caller-supplied enabled=false', () => {
    expect(jurisdictionShape.parse({ ...minimal, enabled: false }).enabled).toBe(false);
  });
});

describe('jurisdictionShape — identifier bounds (min 2, max 24)', () => {
  it('accepts a two-character identifier (lower bound)', () => {
    expect(() => jurisdictionShape.parse({ ...minimal, identifier: 'eu' })).not.toThrow();
  });

  it('accepts a 24-character identifier (upper bound)', () => {
    expect(() =>
      jurisdictionShape.parse({ ...minimal, identifier: 'a'.repeat(24) })
    ).not.toThrow();
  });

  it('rejects a one-character identifier', () => {
    expect(() => jurisdictionShape.parse({ ...minimal, identifier: 'x' })).toThrow();
  });

  it('rejects a 25-character identifier', () => {
    expect(() =>
      jurisdictionShape.parse({ ...minimal, identifier: 'a'.repeat(25) })
    ).toThrow();
  });

  it('contract accepts the out-of-range identifiers the shape rejects', () => {
    expect(() => jurisdictionSchema.parse({ ...minimal, identifier: 'x' })).not.toThrow();
    expect(() =>
      jurisdictionSchema.parse({ ...minimal, identifier: 'a'.repeat(25) })
    ).not.toThrow();
  });
});

describe('regionsConfigShape — identifier bounds (no enabled default)', () => {
  const minimalRegion = {
    identifier: 'eu',
    enabled: true,
    current_jurisdiction: 'eu',
    jurisdictions: [minimal],
  };

  it('rejects one-character identifier on the shape', () => {
    expect(() =>
      regionsConfigShape.parse({ ...minimalRegion, identifier: 'x' })
    ).toThrow();
  });

  it('contract accepts the same one-character identifier', () => {
    expect(() =>
      regionsConfigSchema.parse({ ...minimalRegion, identifier: 'x' })
    ).not.toThrow();
  });
});

describe('jurisdiction passthrough shapes', () => {
  it('jurisdictionIconShape parses a populated icon', () => {
    const result = jurisdictionIconShape.parse({ collection: 'flag', name: 'eu' });
    expect(result).toEqual({ collection: 'flag', name: 'eu' });
  });

  it('jurisdictionDetailsShape parses booleans', () => {
    const result = jurisdictionDetailsShape.parse({ is_default: true, is_current: false });
    expect(result).toEqual({ is_default: true, is_current: false });
  });
});
