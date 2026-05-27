// src/tests/schemas/shapes/config/capabilities.spec.ts
//
// The capabilities shape has no defaults or value constraints — it is a
// pure re-export of the contract. This is a convention guard: if anyone
// adds augmentation in the shape file, the identity assertion fails and
// forces a re-read of whether per-section coverage now applies.

import { describe, it, expect } from 'vitest';
import {
  capabilitiesSchema,
  capabilityFlagsSchema,
} from '@/schemas/contracts/config/section/capabilities';
import {
  capabilitiesShape,
  capabilityFlagsShape,
} from '@/schemas/shapes/config/section/capabilities';

describe('capabilities shape — re-export convention', () => {
  it('capabilitiesShape is the contract schema (no augmentation)', () => {
    expect(capabilitiesShape).toBe(capabilitiesSchema);
  });

  it('capabilityFlagsShape is the contract schema (no augmentation)', () => {
    expect(capabilityFlagsShape).toBe(capabilityFlagsSchema);
  });

  it('parses a populated capability flag block', () => {
    const result = capabilityFlagsShape.parse({
      api: true,
      email: false,
      custom_domains: true,
    });
    expect(result).toEqual({ api: true, email: false, custom_domains: true });
  });

  it('requires every flag (no defaults backfill missing keys)', () => {
    expect(() => capabilityFlagsShape.parse({ api: true })).toThrow();
  });
});
