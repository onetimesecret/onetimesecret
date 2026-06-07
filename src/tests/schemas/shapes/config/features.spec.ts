// src/tests/schemas/shapes/config/features.spec.ts
//
// Coverage for the features shape — regions, incoming, domains (incl. the
// ACME endpoint and proxy sub-trees). The `jurisdictions` union added in
// PR #3206 lives on the contract because `z.union(...)` is a type-format
// helper; this file exercises all three branches there to lock that down.

import { describe, it, expect } from 'vitest';
import {
  featuresIncomingSchema,
  featuresDomainsAcmeSchema,
  featuresRegionsSchema,
} from '@/schemas/contracts/config/section/features';
import {
  featuresShape,
  featuresRegionsShape,
  featuresIncomingShape,
  featuresDomainsShape,
  featuresDomainsProxyShape,
  featuresDomainsAcmeShape,
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
    const value = [
      { identifier: 'eu', display_name: 'Europe', domain: 'eu.example.com' },
    ];
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

describe('featuresDomainsAcmeShape — defaults', () => {
  it('defaults enabled/listen_address/port on empty input', () => {
    const result = featuresDomainsAcmeShape.parse({});
    expect(result.enabled).toBe(false);
    expect(result.listen_address).toBe('127.0.0.1');
    expect(result.port).toBe('12020');
  });

  it('accepts both string and number forms of port', () => {
    expect(featuresDomainsAcmeShape.parse({ port: 12020 }).port).toBe(12020);
    expect(featuresDomainsAcmeShape.parse({ port: '8443' }).port).toBe('8443');
  });

  it('contract leaves enabled/port undefined', () => {
    const result = featuresDomainsAcmeSchema.parse({});
    expect(result.enabled).toBeUndefined();
    expect(result.port).toBeUndefined();
  });
});

describe('featuresDomainsProxyShape — passthrough', () => {
  it('is a re-export of the contract (no augmentation)', () => {
    expect(featuresDomainsProxyShape.parse({})).toEqual({});
  });

  it('preserves nullable string fields', () => {
    const result = featuresDomainsProxyShape.parse({ api_key: null, proxy_ip: '10.0.0.1' });
    expect(result.api_key).toBeNull();
    expect(result.proxy_ip).toBe('10.0.0.1');
  });
});

describe('featuresDomainsShape — composed defaults', () => {
  it('defaults enabled/require_verified/validation_strategy and nested acme', () => {
    const result = featuresDomainsShape.parse({ acme: {} });
    expect(result.enabled).toBe(false);
    expect(result.require_verified).toBe(false);
    expect(result.validation_strategy).toBe('passthrough');
    expect(result.acme?.enabled).toBe(false);
    expect(result.acme?.listen_address).toBe('127.0.0.1');
    expect(result.acme?.port).toBe('12020');
  });

  it('rejects validation_strategy values outside the enum', () => {
    expect(() => featuresDomainsShape.parse({ validation_strategy: 'made_up' })).toThrow();
  });
});

describe('featuresShape — composed defaults', () => {
  it('applies defaults to every nested sub-tree provided as empty objects', () => {
    const result = featuresShape.parse({
      regions: {},
      incoming: {},
      domains: { acme: {} },
    });
    expect(result.regions?.enabled).toBe(false);
    expect(result.incoming?.enabled).toBe(false);
    expect(result.incoming?.memo_max_length).toBe(50);
    expect(result.incoming?.default_ttl).toBe(604800);
    expect(result.domains?.enabled).toBe(false);
    expect(result.domains?.acme?.port).toBe('12020');
  });
});
