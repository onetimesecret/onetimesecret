// src/tests/schemas/shapes/config/features.spec.ts
//
// Coverage for the features shape — regions, incoming, and domains. The
// `jurisdictions` union added in PR #3206 lives on the contract because
// `z.union(...)` is a type-format helper; this file exercises all three
// branches there to lock that down.
//
// The domains contract is the allowlisted subset ConfigSerializer emits:
// the `approximated` (proxy credentials) and `acme` (internal listener)
// blocks are server-side only and are asserted absent here so they cannot
// quietly rejoin the client-facing contract.

import { describe, it, expect } from 'vitest';
import {
  featuresIncomingSchema,
  featuresDomainsSchema,
  featuresRegionsSchema,
} from '@/schemas/contracts/config/section/features';
import {
  featuresShape,
  featuresRegionsShape,
  featuresIncomingShape,
  featuresDomainsShape,
} from '@/schemas/shapes/config/section/features';

describe('featuresIncomingShape — defaults and bounds', () => {
  it('defaults enabled/memo_max_length/default_ttl on empty input', () => {
    const result = featuresIncomingShape.parse({});
    expect(result.enabled).toBe(false);
    expect(result.memo_max_length).toBe(50);
    expect(result.default_ttl).toBe(604800);
  });

  it('rejects non-positive memo_max_length', () => {
    expect(() => featuresIncomingShape.parse({ memo_max_length: 0 })).toThrow();
    expect(() => featuresIncomingShape.parse({ memo_max_length: -1 })).toThrow();
  });

  it('rejects non-integer memo_max_length', () => {
    expect(() => featuresIncomingShape.parse({ memo_max_length: 12.5 })).toThrow();
  });

  it('rejects non-positive default_ttl', () => {
    expect(() => featuresIncomingShape.parse({ default_ttl: 0 })).toThrow();
  });

  it('contract accepts the same bad values the shape rejects', () => {
    expect(() => featuresIncomingSchema.parse({ memo_max_length: 0 })).not.toThrow();
    expect(() => featuresIncomingSchema.parse({ default_ttl: -5 })).not.toThrow();
  });
});

describe('featuresRegionsShape — defaults', () => {
  it('enabled defaults to false', () => {
    expect(featuresRegionsShape.parse({}).enabled).toBe(false);
  });
});

describe('featuresRegions jurisdictions union (contract-side)', () => {
  it('accepts an array of structured jurisdictions', () => {
    const value = [{ identifier: 'eu', display_name: 'Europe', domain: 'eu.example.com' }];
    expect(featuresRegionsSchema.parse({ jurisdictions: value }).jurisdictions).toEqual(value);
    expect(featuresRegionsShape.parse({ jurisdictions: value }).jurisdictions).toEqual(value);
  });

  it('accepts a CSV string (raw ENV value)', () => {
    expect(featuresRegionsShape.parse({ jurisdictions: 'eu,us' }).jurisdictions).toBe('eu,us');
  });

  it('accepts null (unset ENV)', () => {
    expect(featuresRegionsShape.parse({ jurisdictions: null }).jurisdictions).toBeNull();
  });

  it('rejects values that match none of the union branches', () => {
    expect(() => featuresRegionsShape.parse({ jurisdictions: 42 })).toThrow();
  });
});

describe('featuresDomainsShape — composed defaults', () => {
  it('defaults enabled/require_verified/validation_strategy', () => {
    const result = featuresDomainsShape.parse({});
    expect(result.enabled).toBe(false);
    expect(result.require_verified).toBe(false);
    expect(result.validation_strategy).toBe('passthrough');
  });

  it('rejects validation_strategy values outside the enum', () => {
    expect(() => featuresDomainsShape.parse({ validation_strategy: 'made_up' })).toThrow();
  });

  it('does not declare the server-side approximated/acme blocks', () => {
    expect(featuresDomainsSchema.shape).not.toHaveProperty('approximated');
    expect(featuresDomainsSchema.shape).not.toHaveProperty('acme');
  });

  it('strips server-side blocks if they ever appear in input', () => {
    const result = featuresDomainsShape.parse({
      approximated: { api_key: 'leaked' },
      acme: { listen_address: '127.0.0.1' },
    });
    expect(result).not.toHaveProperty('approximated');
    expect(result).not.toHaveProperty('acme');
  });
});

describe('featuresShape — composed defaults', () => {
  it('applies defaults to every nested sub-tree provided as empty objects', () => {
    const result = featuresShape.parse({
      regions: {},
      incoming: {},
      domains: {},
    });
    expect(result.regions?.enabled).toBe(false);
    expect(result.incoming?.enabled).toBe(false);
    expect(result.incoming?.memo_max_length).toBe(50);
    expect(result.incoming?.default_ttl).toBe(604800);
    expect(result.domains?.enabled).toBe(false);
  });
});
