// src/tests/contracts/organization-schema-contract.spec.ts
//
// Contract snapshot tests that verify the frontend Zod schema declares
// all fields the backend sends. Prevents silent field stripping (issue #2685).

import { organizationRecord } from '@/schemas/shapes/v3/organization';
import { describe, expect, it } from 'vitest';

import { ORGANIZATION_SAFE_DUMP_FIELDS } from './organization-safe-dump-fields';

// Fields intentionally excluded from organizationRecord.
// Each entry MUST have a comment explaining why it is excluded.
const INTENTIONAL_EXCLUSIONS: Record<string, string> = {
  // billing_email is a separate contact field for billing purposes.
  // Frontend currently uses contact_email for all communications.
  billing_email: 'Billing-specific field; frontend uses contact_email for display',

  // member_count is computed dynamically from the members relation.
  // Not stored in the record, calculated at response time.
  member_count: 'Computed field from members relation; not stored in schema',

  // domain_count is computed dynamically from the domains relation.
  // Not stored in the record, calculated at response time.
  domain_count: 'Computed field from domains relation; not stored in schema',

  // entitlements is a nested object with plan feature flags.
  // Frontend currently reads these via a separate API call.
  entitlements: 'Plan feature flags; fetched separately in frontend',

  // limits is a nested object with quota limits.
  // Frontend currently reads these via a separate API call.
  limits: 'Plan quota limits; fetched separately in frontend',
};

describe('Organization schema contract (safe_dump_fields)', () => {
  const schemaKeys = Object.keys(organizationRecord.shape);

  describe('field completeness', () => {
    // For each backend field, verify the Zod schema declares it
    // (or it appears in the explicit exclusion list).
    const backendFields = ORGANIZATION_SAFE_DUMP_FIELDS.filter(
      (f) => !(f in INTENTIONAL_EXCLUSIONS)
    );

    it.each(backendFields)(
      'organizationRecord declares backend field "%s"',
      (field) => {
        expect(schemaKeys).toContain(field);
      }
    );

    it('all intentional exclusions reference real backend fields', () => {
      // Guard against stale exclusions: every key in INTENTIONAL_EXCLUSIONS
      // must actually exist in the backend field list.
      for (const excluded of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        expect(
          ORGANIZATION_SAFE_DUMP_FIELDS as readonly string[]
        ).toContain(excluded);
      }
    });

    it('no unaccounted backend fields are missing from the schema', () => {
      const missing = ORGANIZATION_SAFE_DUMP_FIELDS.filter(
        (f) => !schemaKeys.includes(f) && !(f in INTENTIONAL_EXCLUSIONS)
      );
      expect(missing).toEqual([]);
    });
  });

  describe('strict parsing (no unknown fields)', () => {
    // Build a realistic organization payload containing ALL safe_dump fields.
    // Parsing through organizationRecord.strict() should succeed, confirming
    // the schema does not reject any fields the backend sends.
    //
    // Fields in INTENTIONAL_EXCLUSIONS are included here because the backend
    // sends them; .strict() only rejects fields NOT in the schema, so we
    // use .passthrough() for this particular test to avoid false negatives
    // from the excluded fields.

    const realisticPayload: Record<string, unknown> = {
      identifier: 'org123abc',
      objid: '01234567-89ab-cdef-0123-456789abcdef',
      extid: 'on1a2b3c4d',
      display_name: 'Acme Corporation',
      description: 'A great company building great things',
      owner_id: 'cust456def',
      contact_email: 'contact@acme.com',
      billing_email: 'billing@acme.com',
      is_default: false,
      planid: 'pro',
      member_count: 5,
      domain_count: 2,
      created: 1609372800,
      updated: 1609459200,
      entitlements: {
        custom_domains: true,
        api_access: true,
        sso: false,
      },
      limits: {
        teams: 10,
        members_per_team: 25,
        custom_domains: 5,
      },
    };

    it('parses a full backend payload without errors (passthrough mode)', () => {
      // passthrough keeps extra fields (the intentionally excluded ones)
      // so the parse focuses on whether declared fields are correct.
      const result = organizationRecord.passthrough().safeParse(realisticPayload);
      expect(result.success).toBe(true);
    });

    it('strict parse succeeds for schema-declared fields only', () => {
      // Strip the intentionally excluded fields, then strict-parse.
      // This confirms the schema shape matches exactly what we expect.
      const declaredOnly = { ...realisticPayload };
      for (const key of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        delete declaredOnly[key];
      }
      const result = organizationRecord.strict().safeParse(declaredOnly);
      if (!result.success) {
        // Surface the Zod issues for easier debugging
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });
});
