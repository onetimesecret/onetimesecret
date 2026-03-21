// src/tests/contracts/receipt-schema-contract.spec.ts
//
// Contract snapshot tests that verify the frontend Zod schema declares
// all fields the backend sends. Prevents silent field stripping (issue #2685).

import { receiptBaseRecord } from '@/schemas/api/v3/responses/receipts';
import { describe, expect, it } from 'vitest';

import { RECEIPT_SAFE_DUMP_FIELDS } from './receipt-safe-dump-fields';

// Fields intentionally excluded from receiptBaseRecord.
// Each entry MUST have a comment explaining why it is excluded.
const INTENTIONAL_EXCLUSIONS: Record<string, string> = {
  // custid is sent by the backend but not consumed by any frontend component.
  // useRecentSecrets.transformApiRecord() intentionally omits it from RecentSecretRecord.
  custid: 'Backend-only field; not consumed by frontend components',

  // owner_id is an internal backend identifier not exposed to the frontend UI.
  owner_id: 'Internal backend identifier; not used by frontend',

  // metadata_ttl duplicates receipt_ttl/lifespan; backend includes it for legacy reasons.
  metadata_ttl: 'Redundant with receipt_ttl and lifespan; legacy backend field',

  // show_recipients is a computed display flag added by receiptListRecord and receiptDetails.
  show_recipients: 'Display flag added in receiptListRecord and receiptDetails, not base',

  // ─────────────────────────────────────────────────────────────────────────────
  // DEPRECATED FIELD ALIASES (V3 clean API exclusions)
  // ─────────────────────────────────────────────────────────────────────────────
  // V3 is the "clean" API without deprecated field aliases. Backend sends these
  // for V2 backward compatibility, but V3 clients should use canonical names.
  // See: lib/onetime/models/receipt/features/safe_dump_fields.rb lines 94-97

  // Deprecated timestamp field aliases (use 'previewed' instead)
  viewed: 'V3 clean API: use canonical "previewed" timestamp instead',

  // Deprecated timestamp field aliases (use 'revealed' instead)
  received: 'V3 clean API: use canonical "revealed" timestamp instead',

  // Deprecated boolean aliases (use 'is_previewed' instead)
  is_viewed: 'V3 clean API: use canonical "is_previewed" instead',

  // Deprecated boolean aliases (use 'is_revealed' instead)
  is_received: 'V3 clean API: use canonical "is_revealed" instead',
};

describe('Receipt schema contract (safe_dump_fields)', () => {
  const schemaKeys = Object.keys(receiptBaseRecord.shape);

  describe('field completeness', () => {
    // For each backend field, verify the Zod schema declares it
    // (or it appears in the explicit exclusion list).
    const backendFields = RECEIPT_SAFE_DUMP_FIELDS.filter(
      (f) => !(f in INTENTIONAL_EXCLUSIONS)
    );

    it.each(backendFields)(
      'receiptBaseRecord declares backend field "%s"',
      (field) => {
        expect(schemaKeys).toContain(field);
      }
    );

    it('all intentional exclusions reference real backend fields', () => {
      // Guard against stale exclusions: every key in INTENTIONAL_EXCLUSIONS
      // must actually exist in the backend field list.
      for (const excluded of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        expect(
          RECEIPT_SAFE_DUMP_FIELDS as readonly string[]
        ).toContain(excluded);
      }
    });

    it('no unaccounted backend fields are missing from the schema', () => {
      const missing = RECEIPT_SAFE_DUMP_FIELDS.filter(
        (f) => !schemaKeys.includes(f) && !(f in INTENTIONAL_EXCLUSIONS)
      );
      expect(missing).toEqual([]);
    });
  });

  describe('strict parsing (no unknown fields)', () => {
    // Build a realistic receipt payload containing ALL safe_dump fields.
    // Parsing through receiptBaseRecord.strict() should succeed, confirming
    // the schema does not reject any fields the backend sends.
    //
    // Fields in INTENTIONAL_EXCLUSIONS are included here because the backend
    // sends them; .strict() only rejects fields NOT in the schema, so we
    // use .passthrough() for this particular test to avoid false negatives
    // from the excluded fields.

    const realisticPayload: Record<string, unknown> = {
      identifier: 'abc123def456',
      key: 'abc123def456',
      custid: 'cust:user@example.com',
      owner_id: 'cust:user@example.com',
      state: 'new',
      secret_shortid: 'sec12345',
      secret_identifier: 'secret-full-identifier-abc123',
      secret_ttl: 3600,
      metadata_ttl: 7200,
      receipt_ttl: 7200,
      lifespan: 7200,
      share_domain: 'example.com',
      created: 1735142814,
      updated: 1735204014,
      shared: null,
      recipients: ['recipient@example.com'],
      memo: 'Test memo',
      shortid: 'abc12345',
      show_recipients: true,
      previewed: null,
      revealed: null,
      viewed: null,
      received: null,
      burned: null,
      is_previewed: false,
      is_viewed: false,
      is_received: false,
      is_revealed: false,
      is_burned: false,
      is_expired: false,
      is_orphaned: false,
      is_destroyed: false,
      has_passphrase: false,
      kind: 'conceal',
    };

    it('parses a full backend payload without errors (passthrough mode)', () => {
      // passthrough keeps extra fields (the intentionally excluded ones)
      // so the parse focuses on whether declared fields are correct.
      const result = receiptBaseRecord.passthrough().safeParse(realisticPayload);
      expect(result.success).toBe(true);
    });

    it('strict parse succeeds for schema-declared fields only', () => {
      // Strip the intentionally excluded fields, then strict-parse.
      // This confirms the schema shape matches exactly what we expect.
      const declaredOnly = { ...realisticPayload };
      for (const key of Object.keys(INTENTIONAL_EXCLUSIONS)) {
        delete declaredOnly[key];
      }
      const result = receiptBaseRecord.strict().safeParse(declaredOnly);
      if (!result.success) {
        // Surface the Zod issues for easier debugging
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });
});
