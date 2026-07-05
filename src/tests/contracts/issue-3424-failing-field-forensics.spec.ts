// src/tests/contracts/issue-3424-failing-field-forensics.spec.ts
//
// Empirical forensics for issue #3424 ("secret immediately shows 'no longer
// available' / marked previewed, never viewable").
//
// WHY THIS FILE EXISTS
// --------------------
// Three fixes shipped against #3424 (#3268 → #3434 → #3477) and the bug stayed
// open, because *nobody ever captured the field that actually fails* — the
// frontend's `gracefulParse` discards the Zod error in production (see
// docs/specs/recipient-disclosure/unviewable-state-root-cause.md and src/utils/schemaValidation.ts).
// Every fix so far was an inference.
//
// This spec ends the guessing by doing on our side what production hides: it
// runs the REAL v3 response schemas (the exact objects `secretStore` validates)
// against payloads built to mirror what the Ruby backend actually puts on the
// wire — `secret.safe_dump`, `receipt.safe_dump`, and the raw values merged on
// top of them in the logic classes — and asserts precisely which `issues[].path`
// fails in each scenario.
//
// It is also the "legacy-fixture" contract gate the systemic plan calls for:
// every existing v3 schema test uses `state: 'new'` on a pristine record, which
// is exactly the gap that let a legacy-`state` / uncast-field regression reach
// production. These fixtures deliberately exercise legacy and poisoned shapes.
//
// References: #3424, #3268, #3299, #3434, #3477, #3496
// Backend wire sources mirrored here:
//   - lib/onetime/models/secret/features/safe_dump_fields.rb
//   - lib/onetime/models/receipt/features/safe_dump_fields.rb
//   - apps/api/v2/logic/secrets/show_secret.rb      (#success_data)
//   - apps/api/v2/logic/secrets/show_receipt.rb     (#_receipt_attributes, #ancillary_attributes)
//   - apps/api/v2/logic/secrets/list_receipts.rb    (#success_data)

import { secretResponseSchema } from '@/schemas/api/v3/responses/secrets';
import {
  receiptResponseSchema,
  receiptListResponseSchema,
} from '@/schemas/api/v3/responses/receipts';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

interface FieldIssue {
  path: string;
  code: string;
  message: string;
}

/** Return the list of failing field paths (empty array == valid). */
function failingFields(schema: z.ZodType, payload: unknown): FieldIssue[] {
  const result = schema.safeParse(payload);
  if (result.success) return [];
  return result.error.issues.map((i) => ({
    path: i.path.join('.') || '(root)',
    code: i.code,
    message: i.message,
  }));
}

function paths(issues: FieldIssue[]): string[] {
  return issues.map((i) => i.path);
}

// ─────────────────────────────────────────────────────────────────────────────
// Wire-faithful payload builders
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A healthy, freshly-previewed Secret as it is actually emitted by
 * `secret.safe_dump` on v0.25.11 (numerics cast: lifespan/secret_ttl → Integer,
 * created/updated → Float; booleans method-computed; state guarded to
 * 'new'/'previewed' by `viewable?` before a 200 is returned).
 */
function healthySecretRecord(overrides: Record<string, unknown> = {}) {
  return {
    identifier: 'abc123secretxyz',
    key: 'abc123secretxyz',
    shortid: 'abc123se',
    state: 'previewed',
    lifespan: 604800, // .to_i
    secret_ttl: 604800, // m.lifespan.to_i
    has_passphrase: false,
    verification: false,
    created: 1735142814.71047, // .to_f
    updated: 1735142890.10312, // .to_f
    is_previewed: true,
    is_revealed: false,
    // backward-compat extras the v3 schema strips:
    is_viewed: true,
    is_received: false,
    ...overrides,
  };
}

function secretShowResponse(recordOverrides: Record<string, unknown> = {}) {
  // Mirrors ShowSecret#success_data: { record: secret.safe_dump, details: {...} }
  // secret_value is omitted on a GET preview (added only when show_secret).
  return {
    record: healthySecretRecord(recordOverrides),
    details: {
      continue: false,
      is_owner: false,
      show_secret: false,
      correct_passphrase: true,
      display_lines: 4,
      one_liner: null,
    },
    shrimp: '',
  };
}

/**
 * A healthy Receipt list row as emitted by `receipt.safe_dump` (ListReceipts).
 * Note: unset timestamp fields (revealed/burned/shared) are modeled as `null`
 * here — that is the benign case. Whether Familia hydrates an unset field to
 * `null` vs the empty string `""` is the hinge tested explicitly below.
 */
function healthyReceiptRecord(overrides: Record<string, unknown> = {}) {
  return {
    identifier: 'recpt123xyz',
    key: 'recpt123xyz',
    custid: 'user@example.com',
    owner_id: 'user@example.com',
    state: 'previewed',
    secret_shortid: 'abc123se',
    secret_identifier: 'abc123secretxyz',
    secret_ttl: 604800, // .to_i
    metadata_ttl: 604800, // .to_i
    receipt_ttl: 604800, // .to_i
    lifespan: 604800, // .to_i
    share_domain: '',
    created: 1735142814.71047, // .to_f
    updated: 1735142890.10312, // .to_f
    shared: null,
    recipients: '',
    recipient_name: '',
    memo: '',
    shortid: 'recpt123',
    show_recipients: false,
    previewed: 1735142890, // Familia.now.to_i (Integer) once previewed
    revealed: null,
    burned: null,
    is_previewed: true,
    is_revealed: false,
    is_burned: false,
    is_expired: false,
    is_orphaned: false,
    is_destroyed: false,
    // backward-compat extras the v3 schema strips:
    is_viewed: true,
    is_received: false,
    viewed: 1735142890,
    received: null,
    has_passphrase: false,
    kind: 'conceal',
    ...overrides,
  };
}

function receiptListResponse(records: Array<Record<string, unknown>>) {
  // Mirrors ListReceipts#success_data.
  return {
    records,
    count: records.length,
    details: {
      type: 'list',
      scope: null,
      scope_label: null,
      since: 1732550890, // (Familia.now - 30.days).to_i  → Integer
      now: 1735142890.5, // Familia.now → Float
      has_items: records.length > 0,
    },
    shrimp: '',
  };
}

/**
 * A healthy single Receipt as emitted by ShowReceipt#_receipt_attributes:
 * receipt.safe_dump MERGED with raw, uncast logic-class values
 * (expiration, expiration_in_seconds, secret_state, *_path, *_url, ...).
 */
function healthyShowReceiptResponse(
  recordOverrides: Record<string, unknown> = {},
  detailOverrides: Record<string, unknown> = {}
) {
  const base = healthyReceiptRecord();
  const record = {
    ...base,
    // merged in _receipt_attributes (these BYPASS safe_dump casts):
    secret_state: 'new', // raw secret.state — can be nil/legacy
    natural_expiration: '7 days',
    expiration: 1735747690, // receipt.secret_expiration — can be nil
    expiration_in_seconds: 604800, // receipt.secret_ttl — RAW, no .to_i
    share_path: '/secret/abc123secretxyz',
    burn_path: '/private/recpt123xyz/burn',
    receipt_path: '/private/recpt123xyz',
    metadata_path: '/private/recpt123xyz', // extra (stripped)
    share_url: 'https://example.com/secret/abc123secretxyz',
    receipt_url: 'https://example.com/private/recpt123xyz',
    metadata_url: 'https://example.com/private/recpt123xyz', // extra (stripped)
    burn_url: 'https://example.com/private/recpt123xyz/burn',
    ...recordOverrides,
  };
  return {
    record,
    details: {
      type: 'record',
      display_lines: 4,
      no_cache: true,
      secret_realttl: 604800,
      view_count: null,
      has_passphrase: false,
      can_decrypt: false,
      secret_value: null,
      show_secret: false,
      show_secret_link: false,
      show_receipt_link: true,
      show_receipt: true,
      show_recipients: false,
      ...detailOverrides,
    },
    shrimp: '',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. The recipient path (GET /api/v3/guest/secret/:id) — ShowSecret
// ─────────────────────────────────────────────────────────────────────────────

describe('#3424 forensics — recipient ShowSecret path', () => {
  it('CONTROL: a healthy, freshly-previewed secret VALIDATES (recipient path is clean on v0.25.11)', () => {
    // This is the load-bearing proof: with the #3434/#3477 safe_dump casts in
    // place, the recipient reveal payload for a healthy record passes. So a
    // *fresh* secret on a true v0.25.11 backend cannot produce "no longer
    // available" via a parse failure — the persisting report is therefore
    // legacy/at-rest data or a stale deployment, not this code path.
    expect(failingFields(secretResponseSchema, secretShowResponse())).toEqual([]);
  });

  it('REGRESSION (pre-#3434): string-typed lifespan/secret_ttl break the strict z.number()', () => {
    // The ORIGINAL #3424 payload. Reproduces only if safe_dump does NOT cast —
    // i.e. an old backend or a code path that bypasses safe_dump. The current
    // backend casts these via to_i, which is why this is now a no-op there.
    const issues = failingFields(
      secretResponseSchema,
      secretShowResponse({ lifespan: '604800', secret_ttl: '604800' })
    );
    expect(paths(issues)).toEqual(
      expect.arrayContaining(['record.lifespan', 'record.secret_ttl'])
    );
  });

  it('the safe_dump to_i cast (Integer wire value) makes the same record VALIDATE', () => {
    // Demonstrates the #3434 fix resolves the secret path: once cast, pass.
    expect(
      failingFields(secretResponseSchema, secretShowResponse({ lifespan: 604800, secret_ttl: 604800 }))
    ).toEqual([]);
  });

  it('string-typed created/updated break (timestamps are strict z.number() too)', () => {
    const issues = failingFields(
      secretResponseSchema,
      secretShowResponse({ created: '1735142814', updated: '1735142890' })
    );
    expect(paths(issues)).toEqual(expect.arrayContaining(['record.created', 'record.updated']));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. The dashboard path (GET /api/v3/receipts) — ListReceipts
//    The "Previewed but never Viewed" sender-side symptom lives here.
// ─────────────────────────────────────────────────────────────────────────────

describe('#3424 forensics — sender ListReceipts (dashboard) path', () => {
  it('CONTROL: a healthy receipt list VALIDATES', () => {
    expect(
      failingFields(receiptListResponseSchema, receiptListResponse([healthyReceiptRecord()]))
    ).toEqual([]);
  });

  it('LEGACY STATE: a receipt with state="viewed" breaks the enum (no data migration exists)', () => {
    // The 'viewed'→'previewed' / 'received'→'revealed' rename shipped with NO
    // migration (the "MIGRATION SCRIPT REQUIREMENTS" blocks in safe_dump are
    // comments only). The receipt list path has NO viewable? guard, so a
    // pre-rename receipt returns 200 and fails the enum — and one bad row nulls
    // the WHOLE list. Best structural fit for the dashboard symptom.
    const issues = failingFields(
      receiptListResponseSchema,
      receiptListResponse([healthyReceiptRecord({ state: 'viewed' })])
    );
    expect(paths(issues)).toContain('records.0.state');
  });

  it('LEGACY STATE: state="received" also breaks the enum', () => {
    const issues = failingFields(
      receiptListResponseSchema,
      receiptListResponse([healthyReceiptRecord({ state: 'received' })])
    );
    expect(paths(issues)).toContain('records.0.state');
  });

  it('UNCAST TIMESTAMP: the schema still rejects a string "previewed" (backend now casts it via to_i)', () => {
    // #3434/#3477 cast lifespan/secret_ttl/created/updated only; previewed/
    // revealed/burned/shared were emitted RAW. They are now coerced in receipt
    // safe_dump (to_i → Integer|nil), so a String can no longer reach the wire.
    // The schema stays strict z.number().nullish() as the read-time backstop,
    // pinned here.
    const issues = failingFields(
      receiptListResponseSchema,
      receiptListResponse([healthyReceiptRecord({ previewed: '1735142890' })])
    );
    expect(paths(issues)).toContain('records.0.previewed');
  });

  it('EMPTY-STRING HINGE: the schema still rejects "" (backend safe_dump cast maps "".to_i → null)', () => {
    // Familia can hydrate an unset field as "". The receipt safe_dump cast now
    // maps "".to_i (0) → null, which the nullish transform accepts; the schema
    // itself still rejects a raw "" as the backstop, pinned here.
    const issues = failingFields(
      receiptListResponseSchema,
      receiptListResponse([healthyReceiptRecord({ revealed: '' })])
    );
    expect(paths(issues)).toContain('records.0.revealed');
  });

  it('one bad row nulls the entire list (all-or-nothing gate)', () => {
    const issues = failingFields(
      receiptListResponseSchema,
      receiptListResponse([
        healthyReceiptRecord(), // fine
        healthyReceiptRecord({ state: 'viewed' }), // legacy
        healthyReceiptRecord(), // fine
      ])
    );
    // The failure is isolated to row 1, but gracefulParse rejects the whole
    // response, so the user sees an empty/failed dashboard, not 2 good rows.
    expect(paths(issues)).toContain('records.1.state');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. The single-receipt path (GET /api/v3/guest/receipt/:id) — ShowReceipt
//    `_receipt_attributes` merges RAW values on top of safe_dump.
// ─────────────────────────────────────────────────────────────────────────────

describe('#3424 forensics — ShowReceipt (_receipt_attributes) path', () => {
  it('CONTROL: a healthy single receipt VALIDATES', () => {
    expect(failingFields(receiptResponseSchema, healthyShowReceiptResponse())).toEqual([]);
  });

  it('NULL EXPIRATION: a consumed/expired secret yields expiration=null → now ACCEPTED (#3424 fix)', () => {
    // receipt.secret_expiration returns nil when secret_ttl is falsey (consumed
    // or expired secret). The contract previously required expiration: z.number()
    // (non-null) and nulled the whole receipt. It is now z.date().nullable(): a
    // consumed receipt legitimately has no live secret to expire.
    expect(
      failingFields(receiptResponseSchema, healthyShowReceiptResponse({ expiration: null }))
    ).toEqual([]);
  });

  it('UNCAST RAW TTL: the schema still rejects a string expiration_in_seconds (backend now casts it via to_i)', () => {
    // The schema intentionally stays strict z.number(); the fix is the backend
    // .to_i in ShowReceipt#_receipt_attributes, so a string can no longer reach
    // the wire. This row pins that the contract is the read-time backstop.
    const issues = failingFields(
      receiptResponseSchema,
      healthyShowReceiptResponse({ expiration_in_seconds: '604800' })
    );
    expect(paths(issues)).toContain('record.expiration_in_seconds');
  });

  it('LEGACY secret_state: a raw legacy "viewed" breaks the nullish enum', () => {
    const issues = failingFields(
      receiptResponseSchema,
      healthyShowReceiptResponse({ secret_state: 'viewed' })
    );
    expect(paths(issues)).toContain('record.secret_state');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. Forensic summary — printed once for the record.
// ─────────────────────────────────────────────────────────────────────────────

describe('#3424 forensics — summary report', () => {
  it('prints the field-level failure matrix', () => {
    const scenarios: Array<{ name: string; schema: z.ZodType; payload: unknown }> = [
      { name: 'ShowSecret  | healthy fresh secret', schema: secretResponseSchema, payload: secretShowResponse() },
      { name: 'ShowSecret  | string lifespan/secret_ttl (pre-#3434)', schema: secretResponseSchema, payload: secretShowResponse({ lifespan: '604800', secret_ttl: '604800' }) },
      { name: 'ListReceipts| healthy', schema: receiptListResponseSchema, payload: receiptListResponse([healthyReceiptRecord()]) },
      { name: 'ListReceipts| legacy state="viewed"', schema: receiptListResponseSchema, payload: receiptListResponse([healthyReceiptRecord({ state: 'viewed' })]) },
      { name: 'ListReceipts| poisoned string previewed', schema: receiptListResponseSchema, payload: receiptListResponse([healthyReceiptRecord({ previewed: '1735142890' })]) },
      { name: 'ListReceipts| unset timestamp as ""', schema: receiptListResponseSchema, payload: receiptListResponse([healthyReceiptRecord({ revealed: '' })]) },
      { name: 'ShowReceipt | healthy', schema: receiptResponseSchema, payload: healthyShowReceiptResponse() },
      { name: 'ShowReceipt | expiration=null', schema: receiptResponseSchema, payload: healthyShowReceiptResponse({ expiration: null }) },
      { name: 'ShowReceipt | raw string expiration_in_seconds', schema: receiptResponseSchema, payload: healthyShowReceiptResponse({ expiration_in_seconds: '604800' }) },
      { name: 'ShowReceipt | legacy secret_state="viewed"', schema: receiptResponseSchema, payload: healthyShowReceiptResponse({ secret_state: 'viewed' }) },
    ];

    // eslint-disable-next-line no-console
    console.log('\n┌─ #3424 field-level failure matrix ' + '─'.repeat(40));
    for (const s of scenarios) {
      const issues = failingFields(s.schema, s.payload);
      const verdict = issues.length === 0 ? 'PASS' : `FAIL → ${paths(issues).join(', ')}`;
      // eslint-disable-next-line no-console
      console.log(`│ ${s.name.padEnd(48)} ${verdict}`);
    }
    // eslint-disable-next-line no-console
    console.log('└' + '─'.repeat(74) + '\n');

    expect(true).toBe(true);
  });
});
