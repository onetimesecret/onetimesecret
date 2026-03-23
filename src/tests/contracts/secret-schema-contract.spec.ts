// src/tests/contracts/secret-schema-contract.spec.ts
//
// Contract snapshot tests that verify the frontend Zod schema declares
// all fields the backend sends. Prevents silent field stripping (issue #2685).

import { secretSchema } from '@/schemas/shapes/v3/secret';
import { describe, expect, it } from 'vitest';

import { SECRET_SAFE_DUMP_FIELDS } from './secret-safe-dump-fields';

// Fields intentionally excluded from secretSchema.
// Each entry MUST have a comment explaining why it is excluded.
const INTENTIONAL_EXCLUSIONS: Record<string, string> = {
  // ─────────────────────────────────────────────────────────────────────────────
  // DEPRECATED FIELD ALIASES (V3 clean API exclusions)
  // ─────────────────────────────────────────────────────────────────────────────
  // V3 is the "clean" API without deprecated field aliases. Backend sends these
  // for V2 backward compatibility, but V3 clients should use canonical names.
  // See: lib/onetime/models/secret/features/safe_dump_fields.rb lines 51-53

  // Deprecated boolean alias (use 'is_previewed' instead)
  is_viewed: 'V3 clean API: use canonical "is_previewed" instead',

  // Deprecated boolean alias (use 'is_revealed' instead)
  is_received: 'V3 clean API: use canonical "is_revealed" instead',
};

describe('Secret schema contract (safe_dump_fields)', () => {
  const schemaKeys = Object.keys(secretSchema.shape);

  describe('field completeness', () => {
    // For each backend field, verify the Zod schema declares it
    // (or it appears in the explicit exclusion list).
    const backendFields = SECRET_SAFE_DUMP_FIELDS.filter(
      (f) => !(f in INTENTIONAL_EXCLUSIONS)
    );

    it.each(backendFields)(
      'secretSchema declares backend field "%s"',
      (field) => {
        expect(schemaKeys).toContain(field);
      }
    );

    it('all intentional exclusions reference real backend fields', () => {
      // Guard against stale exclusions: every key in INTENTIONAL_EXCLUSIONS
      // must actually exist in the backend field list.
      for (const excluded of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        expect(
          SECRET_SAFE_DUMP_FIELDS as readonly string[]
        ).toContain(excluded);
      }
    });

    it('no unaccounted backend fields are missing from the schema', () => {
      const missing = SECRET_SAFE_DUMP_FIELDS.filter(
        (f) => !schemaKeys.includes(f) && !(f in INTENTIONAL_EXCLUSIONS)
      );
      expect(missing).toEqual([]);
    });
  });

  describe('strict parsing (no unknown fields)', () => {
    // Build a realistic secret payload containing ALL safe_dump fields.
    // Parsing through secretSchema.strict() should succeed, confirming
    // the schema does not reject any fields the backend sends.
    //
    // Fields in INTENTIONAL_EXCLUSIONS are included here because the backend
    // sends them; .strict() only rejects fields NOT in the schema, so we
    // use .passthrough() for this particular test to avoid false negatives
    // from the excluded fields.

    const realisticPayload: Record<string, unknown> = {
      identifier: 'abc123def456',
      key: 'abc123def456',
      shortid: 'sec12345',
      state: 'new',
      secret_ttl: 3600,
      lifespan: 3600,
      has_passphrase: false,
      verification: false,
      created: 1735142814,
      updated: 1735204014,
      is_previewed: false,
      is_revealed: false,
      is_viewed: false,
      is_received: false,
    };

    it('parses a full backend payload without errors (passthrough mode)', () => {
      // passthrough keeps extra fields (the intentionally excluded ones)
      // so the parse focuses on whether declared fields are correct.
      const result = secretSchema.passthrough().safeParse(realisticPayload);
      expect(result.success).toBe(true);
    });

    it('strict parse succeeds for schema-declared fields only', () => {
      // Strip the intentionally excluded fields, then strict-parse.
      // This confirms the schema shape matches exactly what we expect.
      const declaredOnly = { ...realisticPayload };
      for (const key of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        delete declaredOnly[key];
      }
      const result = secretSchema.strict().safeParse(declaredOnly);
      if (!result.success) {
        // Surface the Zod issues for easier debugging
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });
});
