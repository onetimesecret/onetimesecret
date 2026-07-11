// src/tests/schemas/api/domains/update-domain-brand-roundtrip.spec.ts
//
// API-boundary round-trip for the #3646 extended brand tokens
// (secondary_color, background_color, text_color, heading_font, border_radius).
//
// Guards the C2 schema-hygiene fix at the request/response boundary (the
// contracts-layer round-trip lives in
// src/tests/schemas/contracts/custom-domain/brand-roundtrip.spec.ts):
//   1. PUT /:extid/brand REQUEST schema now targets the canonical contract, so
//      callers can send the extended tokens (the v2 wire shape stripped them).
//   2. The v3 brand RESPONSE envelope retains them — this is what the Pinia
//      stores (brandStore, domainsStore) parse via `@/schemas/api/v3/responses`.
//   3. The v2 lane INTENTIONALLY still drops them (its string-boolean clients
//      cannot consume the native-boolean canonical shape) — pinned so nobody
//      "fixes" the v2 lane and breaks it.

import { describe, it, expect } from 'vitest';

import { updateDomainBrandRequestSchema } from '@/schemas/api/domains/requests/update-domain-brand';
import { brandSettingschema } from '@/schemas/shapes/v2/custom-domain/brand';
import { brandSettingsResponseSchema as brandSettingsResponseSchemaV3 } from '@/schemas/api/v3/responses/domains';
import { brandSettingsResponseSchema as brandSettingsResponseSchemaV2 } from '@/schemas/api/domains/responses/domains';

// Already normalized (uppercase 6-digit hex) so hex transforms are identity.
const EXTENDED = {
  secondary_color: '#10B981',
  background_color: '#0F172A',
  text_color: '#F8FAFC',
  heading_font: 'slab',
  border_radius: 12,
} as const;

const EXTENDED_KEYS = Object.keys(EXTENDED);

describe('updateDomainBrandRequestSchema (canonical-targeted) — request round-trip', () => {
  it('retains all five extended tokens under `brand`', () => {
    const parsed = updateDomainBrandRequestSchema.parse({
      brand: { primary_color: '#3B82F6', ...EXTENDED },
    });
    expect(parsed.brand).toMatchObject(EXTENDED);
  });

  it('accepts a brand payload of ONLY extended tokens (PATCH-style)', () => {
    const parsed = updateDomainBrandRequestSchema.parse({ brand: { ...EXTENDED } });
    for (const key of EXTENDED_KEYS) {
      expect(parsed.brand).toHaveProperty(key);
    }
  });

  it('regression guard: the v2 wire shape STRIPS the extended tokens', () => {
    // Documents why the request schema was retargeted off the v2 shape: the v2
    // shape declares none of the extended tokens, so it silently drops them.
    const parsedV2 = brandSettingschema
      .partial()
      .parse({ primary_color: '#3B82F6', ...EXTENDED });
    for (const key of EXTENDED_KEYS) {
      expect(parsedV2).not.toHaveProperty(key);
    }
  });
});

describe('v3 brand response envelope — retains extended tokens', () => {
  it('parses an envelope and keeps all five on `record`', () => {
    const result = brandSettingsResponseSchemaV3.parse({
      record: {
        primary_color: '#3B82F6',
        button_text_light: true, // v3 lane = native boolean
        ...EXTENDED,
      },
    });
    expect(result.record).toMatchObject(EXTENDED);
  });
});

describe('v2 brand response envelope — intentionally drops extended tokens', () => {
  it('parses an envelope but strips all five from `record` (string-boolean lane)', () => {
    const result = brandSettingsResponseSchemaV2.parse({
      record: {
        primary_color: '#3B82F6',
        button_text_light: 'true', // v2 lane = string-encoded boolean
        ...EXTENDED,
      },
    });
    for (const key of EXTENDED_KEYS) {
      expect(result.record).not.toHaveProperty(key);
    }
  });
});
