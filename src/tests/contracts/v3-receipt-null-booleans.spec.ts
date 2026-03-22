// src/tests/contracts/v3-receipt-null-booleans.spec.ts
//
// TDD tests for V3 receipt schema null-boolean bug (#2686).
//
// These tests assert the DESIRED behavior: V3 schemas should accept null
// for has_passphrase and can_decrypt (coercing to false), matching the
// V2 model schema's behavior. Tests FAIL until the fix is applied.

import { receiptBaseRecord, receiptResponseSchema } from '@/schemas/api/v3/responses/receipts';
import { receiptDetailsSchema } from '@/schemas/shapes/v2/receipt';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

// Extract the inner receiptDetails schema from the response envelope.
// receiptResponseSchema.shape.details is ZodOptional<receiptDetails>.
const v3ReceiptDetails = (receiptResponseSchema.shape.details as z.ZodOptional<z.ZodObject<any>>).unwrap();

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/** Realistic V3 receiptDetails payload — secret is active, all booleans are proper values. */
const activeSecretDetails = {
  type: 'record' as const,
  display_lines: 1,
  no_cache: false,
  secret_realttl: 3600,
  view_count: 0,
  has_passphrase: false,
  can_decrypt: true,
  secret_value: null,
  show_secret: false,
  show_secret_link: true,
  show_receipt_link: true,
  show_receipt: true,
  show_recipients: false,
  is_orphaned: false,
  is_expired: false,
};

/**
 * Realistic V3 receiptDetails payload — secret has been consumed/destroyed.
 * The backend sends null for has_passphrase and can_decrypt because the
 * secret no longer exists and these properties are no longer meaningful.
 */
const consumedSecretDetails = {
  ...activeSecretDetails,
  has_passphrase: null,
  can_decrypt: null,
  secret_realttl: null,
  view_count: null,
  show_secret: false,
  show_secret_link: false,
  show_receipt_link: false,
  show_receipt: true,
  show_recipients: false,
};

/** Realistic receiptBaseRecord payload with null for has_passphrase. */
const baseRecordWithNullPassphrase = {
  identifier: 'abc123def456',
  created: 1735142814,
  updated: 1735204014,
  key: 'abc123def456',
  shortid: 'abc12345',
  secret_identifier: 'secret-full-identifier-abc123',
  secret_shortid: 'sec12345',
  recipients: ['recipient@example.com'],
  share_domain: 'example.com',
  secret_ttl: 3600,
  receipt_ttl: 7200,
  lifespan: 7200,
  state: 'new' as const,
  has_passphrase: null, // <-- the problematic value
  shared: null,
  received: null,
  viewed: null,
  previewed: null,
  revealed: null,
  burned: null,
  is_viewed: false,
  is_received: false,
  is_previewed: false,
  is_revealed: false,
  is_burned: false,
  is_destroyed: false,
  is_expired: false,
  is_orphaned: false,
  memo: 'Test memo',
  kind: 'conceal' as const,
};

// ---------------------------------------------------------------------------
// V3 receiptDetails — desired null-boolean behavior
// ---------------------------------------------------------------------------

describe('V3 receiptDetails null-boolean fix (#2686)', () => {
  describe('baseline: proper boolean values accepted', () => {
    it('parses active secret details with boolean values', () => {
      const result = v3ReceiptDetails.safeParse(activeSecretDetails);
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });

  describe('schema must accept null booleans from destroyed secrets', () => {
    it('accepts has_passphrase: null and coerces to false', () => {
      const payload = { ...activeSecretDetails, has_passphrase: null };
      const result = v3ReceiptDetails.safeParse(payload);

      // Desired: schema accepts null and coerces to false
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.has_passphrase).toBe(false);
      }
    });

    it('accepts can_decrypt: null and coerces to false', () => {
      const payload = { ...activeSecretDetails, can_decrypt: null };
      const result = v3ReceiptDetails.safeParse(payload);

      // Desired: schema accepts null and coerces to false
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.can_decrypt).toBe(false);
      }
    });

    it('accepts consumed/destroyed secret payload with null booleans', () => {
      const result = v3ReceiptDetails.safeParse(consumedSecretDetails);

      // Desired: a real backend payload for a consumed secret parses successfully
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.has_passphrase).toBe(false);
        expect(result.data.can_decrypt).toBe(false);
      }
    });
  });
});

// ---------------------------------------------------------------------------
// V3 receiptBaseRecord — null boolean test
// ---------------------------------------------------------------------------

describe('V3 receiptBaseRecord null-boolean fix (#2686)', () => {
  it('accepts has_passphrase: null in base record', () => {
    const result = receiptBaseRecord.passthrough().safeParse(baseRecordWithNullPassphrase);

    // Desired: has_passphrase accepts null (backend sends null for consumed secrets)
    expect(result.success).toBe(true);
  });

  describe('baseline: receiptBaseRecord accepts boolean values', () => {
    it('parses has_passphrase: false in base record', () => {
      const payload = { ...baseRecordWithNullPassphrase, has_passphrase: false };
      const result = receiptBaseRecord.passthrough().safeParse(payload);
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });

    it('parses has_passphrase: undefined (omitted) in base record', () => {
      const { has_passphrase: _, ...payloadWithout } = baseRecordWithNullPassphrase;
      const result = receiptBaseRecord.passthrough().safeParse(payloadWithout);
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });
});

// ---------------------------------------------------------------------------
// V2 receiptDetailsSchema — reference (these should always pass)
// ---------------------------------------------------------------------------

describe('V2 receiptDetailsSchema null coercion (reference)', () => {
  const v2ConsumedDetails = {
    type: 'record',
    display_lines: '1',
    no_cache: 'false',
    secret_realttl: null,
    view_count: null,
    has_passphrase: null,
    can_decrypt: null,
    secret_value: null,
    show_secret: 'false',
    show_secret_link: 'false',
    show_receipt_link: 'false',
    show_receipt: 'true',
    show_recipients: 'false',
    is_orphaned: null,
    is_expired: null,
  };

  it('coerces has_passphrase: null to false', () => {
    const result = receiptDetailsSchema.safeParse(v2ConsumedDetails);
    if (!result.success) {
      expect(result.error.issues).toEqual([]);
    }
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.has_passphrase).toBe(false);
      expect(result.data.can_decrypt).toBe(false);
    }
  });

  it('coerces all null booleans to false', () => {
    const allNulls = {
      ...v2ConsumedDetails,
      no_cache: null,
      show_secret: null,
      show_secret_link: null,
      show_receipt_link: null,
      show_receipt: null,
      show_recipients: null,
    };

    const result = receiptDetailsSchema.safeParse(allNulls);
    if (!result.success) {
      expect(result.error.issues).toEqual([]);
    }
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.no_cache).toBe(false);
      expect(result.data.has_passphrase).toBe(false);
      expect(result.data.can_decrypt).toBe(false);
      expect(result.data.show_secret).toBe(false);
      expect(result.data.show_secret_link).toBe(false);
      expect(result.data.show_receipt_link).toBe(false);
      expect(result.data.show_receipt).toBe(false);
      expect(result.data.show_recipients).toBe(false);
    }
  });
});
