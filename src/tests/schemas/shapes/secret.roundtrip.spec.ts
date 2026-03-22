// src/tests/schemas/shapes/secret.roundtrip.spec.ts
//
// Round-trip tests for secret schemas.
// Verifies: canonical → wire format → schema parse → canonical (equality)
//
// These tests catch transforms that lose information during the parse cycle.

import { describe, it, expect } from 'vitest';
import {
  secretSchema,
  secretDetailsSchema,
  secretResponsesSchema,
} from '@/schemas/shapes/v2/secret';
import {
  secretBaseRecord,
  secretRecord,
  secretDetails,
} from '@/schemas/shapes/v3/secret';
import {
  createCanonicalSecretBase,
  createCanonicalSecret,
  createCanonicalSecretWithTimestamps,
  createCanonicalSecretDetails,
  createPreviewedSecret,
  createRevealedSecret,
  createBurnedSecret,
  createPassphraseProtectedSecret,
  createVerificationEnabledSecret,
  createSecretWithValue,
  createV2WireSecret,
  createV2WireSecretDetails,
  createV3WireSecretBase,
  createV3WireSecret,
  createV3WireSecretDetails,
  compareCanonicalSecret,
  compareCanonicalSecretWithTimestamps,
} from './fixtures/secret.fixtures';
import type { SecretCanonical, SecretWithTimestampsCanonical } from '@/schemas/contracts';

// ─────────────────────────────────────────────────────────────────────────────
// Test Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Asserts that two dates are equal by timestamp.
 */
function expectDatesEqual(actual: Date | null, expected: Date | null, fieldName: string) {
  if (expected === null) {
    expect(actual, `${fieldName} should be null`).toBeNull();
  } else {
    expect(actual, `${fieldName} should be a Date`).toBeInstanceOf(Date);
    expect(actual!.getTime(), `${fieldName} timestamp mismatch`).toBe(expected.getTime());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// V2 Round-Trip Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('V2 Secret Round-Trip', () => {
  describe('secretSchema', () => {
    it('round-trips a new secret', () => {
      const canonical = createCanonicalSecretWithTimestamps();
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      // Core fields
      expect(parsed.identifier).toBe(canonical.identifier);
      expect(parsed.key).toBe(canonical.key);
      expect(parsed.shortid).toBe(canonical.shortid);
      expect(parsed.state).toBe(canonical.state);

      // Timestamps
      expectDatesEqual(parsed.created, canonical.created, 'created');
      expectDatesEqual(parsed.updated, canonical.updated, 'updated');

      // Booleans
      expect(parsed.has_passphrase).toBe(canonical.has_passphrase);
      expect(parsed.verification).toBe(canonical.verification);
      expect(parsed.is_previewed).toBe(canonical.is_previewed);
      expect(parsed.is_revealed).toBe(canonical.is_revealed);

      // Numbers
      expect(parsed.secret_ttl).toBe(canonical.secret_ttl);
      expect(parsed.lifespan).toBe(canonical.lifespan);
    });

    it('round-trips a revealed secret', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        ...createRevealedSecret(),
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.state).toBe('revealed');
      expect(parsed.is_revealed).toBe(true);
      expect(parsed.is_previewed).toBe(true);
    });

    it('round-trips a burned secret', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        ...createBurnedSecret(),
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.state).toBe('burned');
    });

    it('round-trips a previewed secret', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        ...createPreviewedSecret(),
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.state).toBe('previewed');
      expect(parsed.is_previewed).toBe(true);
    });

    it('preserves boolean false values', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        has_passphrase: false,
        verification: false,
        is_previewed: false,
        is_revealed: false,
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.has_passphrase).toBe(false);
      expect(parsed.verification).toBe(false);
      expect(parsed.is_previewed).toBe(false);
      expect(parsed.is_revealed).toBe(false);
    });

    it('preserves boolean true values', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        has_passphrase: true,
        verification: true,
        is_previewed: true,
        is_revealed: true,
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.has_passphrase).toBe(true);
      expect(parsed.verification).toBe(true);
      expect(parsed.is_previewed).toBe(true);
      expect(parsed.is_revealed).toBe(true);
    });

    it('handles optional secret_value when present', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_value: 'This is my secret message',
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.secret_value).toBe('This is my secret message');
    });

    it('handles optional secret_value when absent', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_value: undefined,
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.secret_value).toBeUndefined();
    });

    it('preserves TTL field values', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_ttl: 7200,
        lifespan: 172800,
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.secret_ttl).toBe(7200);
      expect(parsed.lifespan).toBe(172800);
    });

    it('handles zero TTL edge case', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_ttl: 0,
        lifespan: 0,
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.secret_ttl).toBe(0);
      expect(parsed.lifespan).toBe(0);
    });
  });

  describe('secretDetailsSchema', () => {
    it('round-trips secret details', () => {
      const canonical = createCanonicalSecretDetails();
      const wire = createV2WireSecretDetails(canonical);
      const parsed = secretDetailsSchema.parse(wire);

      expect(parsed.continue).toBe(canonical.continue);
      expect(parsed.is_owner).toBe(canonical.is_owner);
      expect(parsed.show_secret).toBe(canonical.show_secret);
      expect(parsed.correct_passphrase).toBe(canonical.correct_passphrase);
      expect(parsed.display_lines).toBe(canonical.display_lines);
    });

    it('handles nullable one_liner field (null)', () => {
      const canonical = createCanonicalSecretDetails({
        one_liner: null,
      });
      const wire = createV2WireSecretDetails(canonical);
      const parsed = secretDetailsSchema.parse(wire);

      expect(parsed.one_liner).toBeNull();
    });

    it('handles nullable one_liner field (true)', () => {
      const canonical = createCanonicalSecretDetails({
        one_liner: true,
      });
      const wire = createV2WireSecretDetails(canonical);
      const parsed = secretDetailsSchema.parse(wire);

      expect(parsed.one_liner).toBe(true);
    });

    it('handles nullable one_liner field (false)', () => {
      const canonical = createCanonicalSecretDetails({
        one_liner: false,
      });
      const wire = createV2WireSecretDetails(canonical);
      const parsed = secretDetailsSchema.parse(wire);

      expect(parsed.one_liner).toBe(false);
    });
  });

  describe('state-specific round-trips', () => {
    it.each([
      ['new', createCanonicalSecretWithTimestamps()],
      ['previewed', createCanonicalSecretWithTimestamps({ ...createPreviewedSecret() })],
      ['revealed', createCanonicalSecretWithTimestamps({ ...createRevealedSecret() })],
      ['burned', createCanonicalSecretWithTimestamps({ ...createBurnedSecret() })],
    ] as const)('round-trips %s state', (expectedState, canonical) => {
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.state).toBe(expectedState);
    });

    it('round-trips passphrase-protected secret', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        ...createPassphraseProtectedSecret(),
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.has_passphrase).toBe(true);
    });

    it('round-trips verification-enabled secret', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        ...createVerificationEnabledSecret(),
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.verification).toBe(true);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// V3 Round-Trip Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('V3 Secret Round-Trip', () => {
  describe('secretRecord', () => {
    it('round-trips a new secret', () => {
      const canonical = createCanonicalSecretWithTimestamps();
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      // Core fields
      expect(parsed.identifier).toBe(canonical.identifier);
      expect(parsed.key).toBe(canonical.key);
      expect(parsed.shortid).toBe(canonical.shortid);
      expect(parsed.state).toBe(canonical.state);

      // Timestamps
      expectDatesEqual(parsed.created, canonical.created, 'created');
      expectDatesEqual(parsed.updated, canonical.updated, 'updated');

      // Booleans (native)
      expect(parsed.has_passphrase).toBe(canonical.has_passphrase);
      expect(parsed.verification).toBe(canonical.verification);
      expect(parsed.is_previewed).toBe(canonical.is_previewed);
      expect(parsed.is_revealed).toBe(canonical.is_revealed);

      // Numbers (native)
      expect(parsed.secret_ttl).toBe(canonical.secret_ttl);
      expect(parsed.lifespan).toBe(canonical.lifespan);
    });

    it('round-trips with created/updated timestamps', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        created: new Date('2024-02-20T15:30:00.000Z'),
        updated: new Date('2024-02-20T16:45:00.000Z'),
      });
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      expectDatesEqual(parsed.created, canonical.created, 'created');
      expectDatesEqual(parsed.updated, canonical.updated, 'updated');
    });

    it('preserves native boolean values', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        has_passphrase: true,
        verification: false,
        is_previewed: true,
        is_revealed: false,
      });
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      expect(parsed.has_passphrase).toBe(true);
      expect(parsed.verification).toBe(false);
      expect(parsed.is_previewed).toBe(true);
      expect(parsed.is_revealed).toBe(false);
    });

    it('preserves native number values', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_ttl: 14400,
        lifespan: 259200,
      });
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      expect(parsed.secret_ttl).toBe(14400);
      expect(parsed.lifespan).toBe(259200);
    });

    it('handles optional secret_value', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_value: 'Revealed secret content',
      });
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      expect(parsed.secret_value).toBe('Revealed secret content');
    });
  });

  describe('secretBaseRecord', () => {
    it('round-trips base without TTL (via secretRecord)', () => {
      const canonical = createCanonicalSecretWithTimestamps();
      const wire = createV3WireSecretBase(canonical);
      const parsed = secretBaseRecord.parse(wire);

      expect(parsed.identifier).toBe(canonical.identifier);
      expect(parsed.state).toBe(canonical.state);
      expectDatesEqual(parsed.created, canonical.created, 'created');
    });

    it('timestamp transforms preserve precision', () => {
      // Use round-second timestamp
      const canonical = createCanonicalSecretWithTimestamps({
        created: new Date('2024-01-15T10:00:00.000Z'),
        updated: new Date('2024-01-15T10:00:00.000Z'),
      });
      const wire = createV3WireSecretBase(canonical);
      const parsed = secretBaseRecord.parse(wire);

      // Round-trip should preserve exact timestamp
      expect(parsed.created.getTime()).toBe(canonical.created.getTime());
      expect(parsed.updated.getTime()).toBe(canonical.updated.getTime());
    });
  });

  describe('secretDetails', () => {
    it('uses contract directly (no transforms)', () => {
      const canonical = createCanonicalSecretDetails();
      const wire = createV3WireSecretDetails(canonical);
      const parsed = secretDetails.parse(wire);

      expect(parsed.continue).toBe(canonical.continue);
      expect(parsed.is_owner).toBe(canonical.is_owner);
      expect(parsed.show_secret).toBe(canonical.show_secret);
      expect(parsed.correct_passphrase).toBe(canonical.correct_passphrase);
      expect(parsed.display_lines).toBe(canonical.display_lines);
    });

    it('nullable one_liner handled correctly', () => {
      const withNull = createCanonicalSecretDetails({ one_liner: null });
      const withTrue = createCanonicalSecretDetails({ one_liner: true });
      const withFalse = createCanonicalSecretDetails({ one_liner: false });

      expect(secretDetails.parse(createV3WireSecretDetails(withNull)).one_liner).toBeNull();
      expect(secretDetails.parse(createV3WireSecretDetails(withTrue)).one_liner).toBe(true);
      expect(secretDetails.parse(createV3WireSecretDetails(withFalse)).one_liner).toBe(false);
    });
  });

  describe('state-specific round-trips', () => {
    it.each([
      ['new', createCanonicalSecretWithTimestamps()],
      ['previewed', createCanonicalSecretWithTimestamps({ ...createPreviewedSecret() })],
      ['revealed', createCanonicalSecretWithTimestamps({ ...createRevealedSecret() })],
      ['burned', createCanonicalSecretWithTimestamps({ ...createBurnedSecret() })],
    ] as const)('round-trips %s state', (expectedState, canonical) => {
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      expect(parsed.state).toBe(expectedState);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Boolean Edge Cases
// ─────────────────────────────────────────────────────────────────────────────

describe('Boolean Edge Cases', () => {
  describe('V2 string boolean parsing', () => {
    it.each([
      ['true', true],
      ['false', false],
      ['1', true],
      ['0', false],
    ])('V2 parseBoolean handles "%s" → %s', (input, expected) => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = input;

      const parsed = secretSchema.parse(wire);
      expect(parsed.has_passphrase).toBe(expected);
    });

    it('V2 parseBoolean coerces null to false', () => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = null;

      const parsed = secretSchema.parse(wire);
      expect(parsed.has_passphrase).toBe(false);
    });

    it('V2 parseBoolean coerces undefined to false', () => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = undefined;

      const parsed = secretSchema.parse(wire);
      expect(parsed.has_passphrase).toBe(false);
    });

    it('V2 parseBoolean coerces empty string to false', () => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = '';

      const parsed = secretSchema.parse(wire);
      expect(parsed.has_passphrase).toBe(false);
    });
  });

  describe('V3 native boolean', () => {
    it.each([
      [true, true],
      [false, false],
    ])('V3 native boolean %s → %s', (input, expected) => {
      const wire = createV3WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = input;

      const parsed = secretRecord.parse(wire);
      expect(parsed.has_passphrase).toBe(expected);
    });

    it('V3 rejects null for has_passphrase (strict boolean)', () => {
      const wire = createV3WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = null;

      // V3 secret schema expects native boolean, not nullable
      expect(() => secretRecord.parse(wire)).toThrow();
    });
  });

  describe('null vs false distinction in roundtrip', () => {
    it('V2 explicit false roundtrips to false', () => {
      const canonical = createCanonicalSecretWithTimestamps({ has_passphrase: false });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.has_passphrase).toBe(false);
      expect(typeof parsed.has_passphrase).toBe('boolean');
    });

    it('V2 explicit true roundtrips to true', () => {
      const canonical = createCanonicalSecretWithTimestamps({ has_passphrase: true });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      expect(parsed.has_passphrase).toBe(true);
      expect(typeof parsed.has_passphrase).toBe('boolean');
    });

    it('V3 explicit false roundtrips to false', () => {
      const canonical = createCanonicalSecretWithTimestamps({ has_passphrase: false });
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      expect(parsed.has_passphrase).toBe(false);
      expect(typeof parsed.has_passphrase).toBe('boolean');
    });

    it('V3 explicit true roundtrips to true', () => {
      const canonical = createCanonicalSecretWithTimestamps({ has_passphrase: true });
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      expect(parsed.has_passphrase).toBe(true);
      expect(typeof parsed.has_passphrase).toBe('boolean');
    });

    it('V2 all boolean fields roundtrip with explicit false', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        has_passphrase: false,
        verification: false,
        is_previewed: false,
        is_revealed: false,
      });
      const wire = createV2WireSecret(canonical);
      const parsed = secretSchema.parse(wire);

      // All should be boolean false, not null
      expect(parsed.has_passphrase).toStrictEqual(false);
      expect(parsed.verification).toStrictEqual(false);
      expect(parsed.is_previewed).toStrictEqual(false);
      expect(parsed.is_revealed).toStrictEqual(false);
    });

    it('V3 all boolean fields roundtrip with explicit false', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        has_passphrase: false,
        verification: false,
        is_previewed: false,
        is_revealed: false,
      });
      const wire = createV3WireSecret(canonical);
      const parsed = secretRecord.parse(wire);

      // All should be boolean false, not null
      expect(parsed.has_passphrase).toStrictEqual(false);
      expect(parsed.verification).toStrictEqual(false);
      expect(parsed.is_previewed).toStrictEqual(false);
      expect(parsed.is_revealed).toStrictEqual(false);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Number Edge Cases
// ─────────────────────────────────────────────────────────────────────────────

describe('Number Edge Cases', () => {
  describe('V2 string number parsing', () => {
    it.each([
      ['3600', 3600],
      ['0', 0],
    ])('V2 parseNumber handles "%s" → %s', (input, expected) => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).secret_ttl = input;

      const parsed = secretSchema.parse(wire);
      expect(parsed.secret_ttl).toBe(expected);
    });

    it('V2 parseNumber returns null for non-numeric string', () => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).secret_ttl = 'abc';

      const parsed = secretSchema.parse(wire);
      expect(parsed.secret_ttl).toBeNull();
    });
  });

  describe('V3 native number', () => {
    it.each([
      [3600, 3600],
      [0, 0],
    ])('V3 native number %s → %s', (input, expected) => {
      const wire = createV3WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).secret_ttl = input;

      const parsed = secretRecord.parse(wire);
      expect(parsed.secret_ttl).toBe(expected);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Comparison Helper Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('Comparison Helpers', () => {
  it('compareCanonicalSecret detects no differences for identical secrets', () => {
    const a = createCanonicalSecret();
    const b = createCanonicalSecret();

    const result = compareCanonicalSecret(a, b);
    expect(result.equal).toBe(true);
    expect(result.differences).toHaveLength(0);
  });

  it('compareCanonicalSecret detects field differences', () => {
    const a = createCanonicalSecret({ state: 'new' });
    const b = createCanonicalSecret({ state: 'revealed' });

    const result = compareCanonicalSecret(a, b);
    expect(result.equal).toBe(false);
    expect(result.differences).toContain('state: "new" !== "revealed"');
  });

  it('compareCanonicalSecretWithTimestamps handles Date comparison', () => {
    const a = createCanonicalSecretWithTimestamps({
      created: new Date('2024-01-15T10:00:00.000Z'),
    });
    const b = createCanonicalSecretWithTimestamps({
      created: new Date('2024-01-15T11:00:00.000Z'),
    });

    const result = compareCanonicalSecretWithTimestamps(a, b);
    expect(result.equal).toBe(false);
    expect(result.differences.some((d) => d.includes('created'))).toBe(true);
  });
});
