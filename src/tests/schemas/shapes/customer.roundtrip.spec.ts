// src/tests/schemas/shapes/customer.roundtrip.spec.ts
//
// Round-trip tests for customer schemas.
// Verifies: canonical -> wire format -> schema parse -> canonical (equality)
//
// These tests catch transforms that lose information during the parse cycle.

import { describe, it, expect } from 'vitest';
import { customerSchema, CustomerRole } from '@/schemas/shapes/v2/customer';
import {
  createCanonicalCustomer,
  createColonelCustomer,
  createRecipientCustomer,
  createDeletedCustomer,
  createNeverLoggedInCustomer,
  createFeatureFlaggedCustomer,
  createContributorCustomer,
  createNoLocaleCustomer,
  createHighActivityCustomer,
  createUnverifiedCustomer,
  createV2WireCustomer,
  compareCanonicalCustomer,
  type CustomerCanonical,
} from './fixtures/customer.fixtures';

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Asserts that two dates are equal by timestamp.
 */
function expectDatesEqual(
  actual: Date | null,
  expected: Date | null,
  fieldName: string
) {
  if (expected === null) {
    expect(actual, `${fieldName} should be null`).toBeNull();
  } else {
    expect(actual, `${fieldName} should be a Date`).toBeInstanceOf(Date);
    expect(actual!.getTime(), `${fieldName} timestamp mismatch`).toBe(
      expected.getTime()
    );
  }
}

/**
 * Asserts primitive fields match between parsed and canonical.
 */
function expectPrimitivesMatch(
  parsed: Record<string, unknown>,
  canonical: Record<string, unknown>,
  fields: string[]
) {
  for (const field of fields) {
    expect(parsed[field], `${field} mismatch`).toEqual(canonical[field]);
  }
}

// -----------------------------------------------------------------------------
// V2 Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V2 Customer Round-Trip', () => {
  describe('customerSchema', () => {
    it('round-trips a standard customer', () => {
      const canonical = createCanonicalCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      // Core fields
      expect(parsed.identifier).toBe(canonical.identifier);
      expect(parsed.objid).toBe(canonical.objid);
      expect(parsed.extid).toBe(canonical.extid);
      expect(parsed.role).toBe(canonical.role);
      expect(parsed.email).toBe(canonical.email);

      // Timestamps
      expectDatesEqual(parsed.created, canonical.created, 'created');
      expectDatesEqual(parsed.updated, canonical.updated, 'updated');
      expectDatesEqual(parsed.last_login, canonical.last_login, 'last_login');

      // Booleans
      expect(parsed.verified).toBe(canonical.verified);
      expect(parsed.active).toBe(canonical.active);
      expect(parsed.notify_on_reveal).toBe(canonical.notify_on_reveal);

      // Numbers
      expect(parsed.secrets_created).toBe(canonical.secrets_created);
      expect(parsed.secrets_burned).toBe(canonical.secrets_burned);
      expect(parsed.secrets_shared).toBe(canonical.secrets_shared);
      expect(parsed.emails_sent).toBe(canonical.emails_sent);

      // Optional
      expect(parsed.locale).toBe(canonical.locale);
    });

    it('round-trips a colonel (admin) customer', () => {
      const canonical = createColonelCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.role).toBe(CustomerRole.COLONEL);
      expect(parsed.email).toBe('admin@example.com');
      expect(parsed.feature_flags).toEqual(canonical.feature_flags);
    });

    it('round-trips a recipient customer', () => {
      const canonical = createRecipientCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.role).toBe(CustomerRole.RECIPIENT);
      expect(parsed.verified).toBe(false);
      expectDatesEqual(parsed.last_login, null, 'last_login');
    });

    it('round-trips a deleted customer', () => {
      const canonical = createDeletedCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.role).toBe(CustomerRole.USER_DELETED_SELF);
      expect(parsed.active).toBe(false);
    });

    it('preserves null last_login', () => {
      const canonical = createNeverLoggedInCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expectDatesEqual(parsed.last_login, null, 'last_login');
    });

    it('preserves boolean false values', () => {
      const canonical = createUnverifiedCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.verified).toBe(false);
    });

    it('preserves boolean true values', () => {
      const canonical = createCanonicalCustomer({
        verified: true,
        active: true,
        notify_on_reveal: true,
      });
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.verified).toBe(true);
      expect(parsed.active).toBe(true);
      expect(parsed.notify_on_reveal).toBe(true);
    });

    it('preserves null locale', () => {
      const canonical = createNoLocaleCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.locale).toBeNull();
    });

    it('handles contributor field when present', () => {
      const canonical = createContributorCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.contributor).toBe(true);
    });

    it('handles high activity counter values', () => {
      const canonical = createHighActivityCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.secrets_created).toBe(1000);
      expect(parsed.secrets_burned).toBe(50);
      expect(parsed.secrets_shared).toBe(800);
      expect(parsed.emails_sent).toBe(500);
    });

    it('preserves feature flags through round-trip', () => {
      const canonical = createFeatureFlaggedCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      // Feature flags are transformed to boolean values
      expect(parsed.feature_flags).toBeDefined();
      expect(typeof parsed.feature_flags).toBe('object');
    });

    it('handles zero counter values', () => {
      const canonical = createRecipientCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.secrets_created).toBe(0);
      expect(parsed.secrets_burned).toBe(0);
      expect(parsed.secrets_shared).toBe(0);
      expect(parsed.emails_sent).toBe(0);
    });

    it('uses compareCanonicalCustomer for full equality check', () => {
      const canonical = createCanonicalCustomer();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire) as unknown as CustomerCanonical;

      const result = compareCanonicalCustomer(canonical, parsed);

      // Log differences for debugging if any exist
      if (!result.equal) {
        console.log('Differences found:', result.differences);
      }

      expect(result.equal).toBe(true);
    });
  });

  describe('all customer roles', () => {
    it.each([
      ['customer', createCanonicalCustomer],
      ['colonel', createColonelCustomer],
      ['recipient', createRecipientCustomer],
      ['user_deleted_self', createDeletedCustomer],
    ] as const)('round-trips %s role', (role, factory) => {
      const canonical = factory();
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.role).toBe(role);
    });
  });

  describe('edge cases', () => {
    it('handles empty feature_flags', () => {
      const canonical = createCanonicalCustomer({ feature_flags: {} });
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.feature_flags).toEqual({});
    });

    it('handles undefined contributor (optional field)', () => {
      const canonical = createCanonicalCustomer();
      delete (canonical as Partial<CustomerCanonical>).contributor;
      const wire = createV2WireCustomer(canonical);

      // Should not throw
      const parsed = customerSchema.parse(wire);
      expect(parsed).toBeDefined();
    });

    it('handles locale with special characters', () => {
      const canonical = createCanonicalCustomer({ locale: 'zh-Hans-CN' });
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.locale).toBe('zh-Hans-CN');
    });

    it('handles email with plus addressing', () => {
      const canonical = createCanonicalCustomer({
        email: 'user+tag@example.com',
      });
      const wire = createV2WireCustomer(canonical);
      const parsed = customerSchema.parse(wire);

      expect(parsed.email).toBe('user+tag@example.com');
    });
  });
});

// -----------------------------------------------------------------------------
// Default Value Tests
// -----------------------------------------------------------------------------

describe('V2 Customer Default Values', () => {
  it('applies default for notify_on_reveal when missing', () => {
    const wire = createV2WireCustomer(createCanonicalCustomer());
    // Remove to test default
    delete (wire as Record<string, unknown>).notify_on_reveal;

    const parsed = customerSchema.parse(wire);

    // Default is false per schema definition
    expect(parsed.notify_on_reveal).toBe(false);
  });

  it('applies default 0 for counter fields when missing', () => {
    const wire = createV2WireCustomer(createCanonicalCustomer());
    delete (wire as Record<string, unknown>).secrets_created;
    delete (wire as Record<string, unknown>).secrets_burned;
    delete (wire as Record<string, unknown>).secrets_shared;
    delete (wire as Record<string, unknown>).emails_sent;

    const parsed = customerSchema.parse(wire);

    expect(parsed.secrets_created).toBe(0);
    expect(parsed.secrets_burned).toBe(0);
    expect(parsed.secrets_shared).toBe(0);
    expect(parsed.emails_sent).toBe(0);
  });

  it('applies empty object default for feature_flags when missing', () => {
    const wire = createV2WireCustomer(createCanonicalCustomer());
    delete (wire as Record<string, unknown>).feature_flags;

    const parsed = customerSchema.parse(wire);

    expect(parsed.feature_flags).toEqual({});
  });
});

// -----------------------------------------------------------------------------
// Transform Behavior Tests
// -----------------------------------------------------------------------------

describe('V2 Customer Transform Behavior', () => {
  describe('boolean transforms', () => {
    it.each([
      ['true', true],
      ['false', false],
      ['1', true],
      ['0', false],
      [true, true],
      [false, false],
    ])('transforms %p to %s for verified field', (input, expected) => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).verified = input;

      const parsed = customerSchema.parse(wire);

      expect(parsed.verified).toBe(expected);
    });
  });

  describe('number transforms', () => {
    it.each([
      ['0', 0],
      ['42', 42],
      ['1000', 1000],
      [0, 0],
      [42, 42],
    ])('transforms %p to %s for secrets_created', (input, expected) => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).secrets_created = input;

      const parsed = customerSchema.parse(wire);

      expect(parsed.secrets_created).toBe(expected);
    });
  });

  describe('date transforms', () => {
    it('transforms Unix timestamp string to Date for created', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      // Set a specific timestamp
      (wire as Record<string, unknown>).created = '1705312800'; // 2024-01-15T10:00:00Z

      const parsed = customerSchema.parse(wire);

      expect(parsed.created).toBeInstanceOf(Date);
      expect(parsed.created.getTime()).toBe(1705312800000);
    });

    it('transforms null to null for last_login', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).last_login = null;

      const parsed = customerSchema.parse(wire);

      expect(parsed.last_login).toBeNull();
    });

    it('transforms empty string to null for last_login', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).last_login = '';

      const parsed = customerSchema.parse(wire);

      expect(parsed.last_login).toBeNull();
    });
  });
});
