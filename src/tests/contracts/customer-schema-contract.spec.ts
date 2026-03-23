// src/tests/contracts/customer-schema-contract.spec.ts
//
// Contract snapshot tests that verify the frontend Zod schema declares
// all fields the backend sends. Prevents silent field stripping (issue #2685).

import { customerSchema } from '@/schemas/shapes/v3/customer';
import { describe, expect, it } from 'vitest';

import { CUSTOMER_SAFE_DUMP_FIELDS } from './customer-safe-dump-fields';

// Fields intentionally excluded from customerSchema.
// Each entry MUST have a comment explaining why it is excluded.
const INTENTIONAL_EXCLUSIONS: Record<string, string> = {
  // Currently no intentional exclusions for customer schema.
  // All backend fields are consumed by the frontend.
};

// Fields in the frontend schema that are NOT in safe_dump_fields.
// These are frontend-only additions or derived from other sources.
const FRONTEND_ONLY_FIELDS: Record<string, string> = {
  // contributor is an optional field in the frontend schema but not
  // currently in Ruby safe_dump_fields. May be computed or from another source.
  contributor: 'Frontend-only optional field; not in backend safe_dump_fields',

  // feature_flags is assembled separately in the API response, not via safe_dump_fields.
  feature_flags: 'Assembled separately in API response, not from safe_dump_fields',
};

describe('Customer schema contract (safe_dump_fields)', () => {
  const schemaKeys = Object.keys(customerSchema.shape);

  describe('field completeness', () => {
    // For each backend field, verify the Zod schema declares it
    // (or it appears in the explicit exclusion list).
    const backendFields = CUSTOMER_SAFE_DUMP_FIELDS.filter(
      (f) => !(f in INTENTIONAL_EXCLUSIONS)
    );

    it.each(backendFields)(
      'customerSchema declares backend field "%s"',
      (field) => {
        expect(schemaKeys).toContain(field);
      }
    );

    it('all intentional exclusions reference real backend fields', () => {
      // Guard against stale exclusions: every key in INTENTIONAL_EXCLUSIONS
      // must actually exist in the backend field list.
      for (const excluded of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        expect(
          CUSTOMER_SAFE_DUMP_FIELDS as readonly string[]
        ).toContain(excluded);
      }
    });

    it('no unaccounted backend fields are missing from the schema', () => {
      const missing = CUSTOMER_SAFE_DUMP_FIELDS.filter(
        (f) => !schemaKeys.includes(f) && !(f in INTENTIONAL_EXCLUSIONS)
      );
      expect(missing).toEqual([]);
    });

    it('frontend-only fields are documented', () => {
      // Verify that any schema fields not in backend are documented
      const extraFields = schemaKeys.filter(
        (f) =>
          !CUSTOMER_SAFE_DUMP_FIELDS.includes(f as any) &&
          !(f in FRONTEND_ONLY_FIELDS)
      );
      expect(extraFields).toEqual([]);
    });
  });

  describe('strict parsing (no unknown fields)', () => {
    // Build a realistic customer payload containing ALL safe_dump fields.
    // Parsing through customerSchema.strict() should succeed, confirming
    // the schema does not reject any fields the backend sends.
    //
    // Fields in INTENTIONAL_EXCLUSIONS are included here because the backend
    // sends them; .strict() only rejects fields NOT in the schema, so we
    // use .passthrough() for this particular test to avoid false negatives
    // from the excluded fields.

    const realisticPayload: Record<string, unknown> = {
      identifier: 'cust123abc',
      objid: '01234567-89ab-cdef-0123-456789abcdef',
      extid: 'ur1a2b3c4d',
      email: 'user@example.com',
      role: 'customer',
      verified: true,
      last_login: 1735142814,
      locale: 'en',
      updated: 1735204014,
      created: 1735142814,
      secrets_created: 5,
      secrets_burned: 1,
      secrets_shared: 4,
      emails_sent: 3,
      active: true,
      notify_on_reveal: false,
      // Frontend-only fields (not from safe_dump_fields but in schema)
      contributor: false,
      feature_flags: { allow_public_homepage: true },
    };

    it('parses a full backend payload without errors (passthrough mode)', () => {
      // passthrough keeps extra fields (the intentionally excluded ones)
      // so the parse focuses on whether declared fields are correct.
      const result = customerSchema.passthrough().safeParse(realisticPayload);
      expect(result.success).toBe(true);
    });

    it('strict parse succeeds for schema-declared fields only', () => {
      // Strip the intentionally excluded fields, then strict-parse.
      // This confirms the schema shape matches exactly what we expect.
      const declaredOnly = { ...realisticPayload };
      for (const key of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        delete declaredOnly[key];
      }
      const result = customerSchema.strict().safeParse(declaredOnly);
      if (!result.success) {
        // Surface the Zod issues for easier debugging
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });
});
