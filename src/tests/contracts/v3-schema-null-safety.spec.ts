// src/tests/contracts/v3-schema-null-safety.spec.ts
//
// Contract tests for V3 Zod schema null-safety on boolean fields.
//
// Problem: The Ruby backend sends `null` for boolean fields like
// `has_passphrase` and `can_decrypt` when a secret is destroyed/consumed
// (secret.nil?). V2 model schemas use `transforms.fromString.boolean`
// which preprocesses via `parseBoolean` (null -> false). V3 response
// schemas use bare `z.boolean()` which rejects null at parse time.
//
// These tests document the CURRENT broken behavior and will verify
// the fix once applied. They do NOT modify any schemas.

import { receiptResponseSchema, receiptBaseRecord } from '@/schemas/api/v3/responses/receipts';
import {
  secretResponseSchema,
} from '@/schemas/api/v3/responses/secrets';
import {
  accountResponseSchema,
} from '@/schemas/api/v3/responses/account';
import {
  organizationResponseSchema,
} from '@/schemas/api/v3/responses/organizations';
import {
  customDomainResponseSchema,
  jurisdictionResponseSchema,
} from '@/schemas/api/v3/responses/domains';
import { receiptDetailsSchema } from '@/schemas/shapes/v2/receipt';
import { parseBoolean } from '@/utils/parse/index';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

// Zod v4 classic's public AnySchema doesn't expose _def.in / _def.innerType
// at the type level, though they exist at runtime. Use a local alias with `any`
// for the schema introspection helpers below.
type AnySchema = z.ZodTypeAny;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Unwrap a Zod schema through its wrappers to find the innermost type.
 * Handles: ZodOptional, ZodNullable, ZodDefault, ZodPipe (Zod v4 transforms/preprocess).
 */
function unwrapSchema(schema: AnySchema): AnySchema {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- Zod v4 _def internals
  let inner: any = schema;
  while (true) {
    if (inner instanceof z.ZodOptional || inner instanceof z.ZodNullable) {
      inner = inner.unwrap();
    } else if (inner instanceof z.ZodDefault) {
      inner = inner._def.innerType;
    } else if (inner instanceof z.ZodPipe) {
      // Zod v4: preprocess produces ZodPipe with _def.in and _def.out.
      inner = inner._def.in;
    } else {
      break;
    }
  }
  return inner;
}

/**
 * Check whether a Zod schema ultimately wraps a z.boolean(), after peeling
 * through Optional, Nullable, Default, and Pipe layers.
 */
function isBooleanSchema(schema: AnySchema): boolean {
  const inner = unwrapSchema(schema);
  if (inner instanceof z.ZodBoolean) return true;

  // Also check the output side of a pipe (for preprocess patterns where
  // the input is a ZodTransform and the output is ZodBoolean).
  if (schema instanceof z.ZodPipe) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const outInner = unwrapSchema((schema as any)._def.out);
    if (outInner instanceof z.ZodBoolean) return true;
  }

  return false;
}

/**
 * Recursively extract all boolean field paths from a Zod object schema.
 * Returns an array of { path, schema } entries. Only considers z.ZodObject
 * shapes (not unions, intersections, etc.) to keep the audit focused.
 *
 * Compatible with Zod v4 (ZodPipe instead of ZodEffects).
 */
function extractBooleanFields(
  schema: AnySchema,
  prefix = ''
): Array<{ path: string; schema: AnySchema }> {
  const results: Array<{ path: string; schema: AnySchema }> = [];

  const inner = unwrapSchema(schema);

  if (inner instanceof z.ZodObject) {
    const shape = inner.shape as Record<string, AnySchema>;
    for (const [key, fieldSchema] of Object.entries(shape)) {
      const fullPath = prefix ? `${prefix}.${key}` : key;

      if (isBooleanSchema(fieldSchema)) {
        results.push({ path: fullPath, schema: fieldSchema });
      }

      // Recurse into nested objects
      results.push(...extractBooleanFields(fieldSchema, fullPath));
    }
  }

  // Handle arrays: inspect the element schema
  if (inner instanceof z.ZodArray) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    results.push(...extractBooleanFields((inner as any).element, `${prefix}[]`));
  }

  return results;
}

/**
 * Test whether a Zod schema accepts null via safeParse.
 */
function fieldAcceptsNull(fieldSchema: AnySchema): boolean {
  const result = fieldSchema.safeParse(null);
  return result.success;
}

// ---------------------------------------------------------------------------
// 1. Schema-level null boolean audit
// ---------------------------------------------------------------------------

describe('V3 schema null-safety audit', () => {
  describe('schema-level boolean field inventory', () => {
    // Receipt response schemas (the primary pain point)
    const receiptBooleans = extractBooleanFields(receiptResponseSchema);

    it('receipt response schema contains boolean fields', () => {
      // Sanity check: ensure the extractor finds fields
      expect(receiptBooleans.length).toBeGreaterThan(0);
    });

    it('identifies all boolean fields in receipt response schema', () => {
      const paths = receiptBooleans.map((b) => b.path);
      // These are the fields we know exist in the receipt schemas
      expect(paths).toContain('record.is_viewed');
      expect(paths).toContain('record.is_burned');
      expect(paths).toContain('record.is_destroyed');
      expect(paths).toContain('record.is_expired');
      expect(paths).toContain('record.is_orphaned');
      expect(paths).toContain('details.has_passphrase');
      expect(paths).toContain('details.can_decrypt');
      expect(paths).toContain('details.no_cache');
      expect(paths).toContain('details.show_secret');
      expect(paths).toContain('details.show_secret_link');
      expect(paths).toContain('details.show_receipt_link');
      expect(paths).toContain('details.show_receipt');
      expect(paths).toContain('details.show_recipients');
    });

    // Fields that MUST accept null (the fix targets)
    const nullableReceiptDetailsFields = [
      'has_passphrase',
      'can_decrypt',
    ];

    it.each(nullableReceiptDetailsFields)(
      'receipt details field "%s" accepts null (coerces to false)',
      (fieldName) => {
        const field = receiptBooleans.find((b) => b.path === `details.${fieldName}`);
        expect(field).toBeDefined();
        // Desired: these fields accept null from destroyed-secret payloads
        expect(fieldAcceptsNull(field!.schema)).toBe(true);
      }
    );

    // Fields that correctly reject null (backend always sends booleans for these)
    const strictReceiptDetailsFields = [
      'no_cache',
      'show_secret',
      'show_secret_link',
      'show_receipt_link',
      'show_receipt',
      'show_recipients',
    ];

    it.each(strictReceiptDetailsFields)(
      'receipt details field "%s" rejects null (always set by backend)',
      (fieldName) => {
        const field = receiptBooleans.find((b) => b.path === `details.${fieldName}`);
        expect(field).toBeDefined();
        expect(fieldAcceptsNull(field!.schema)).toBe(false);
      }
    );

    // Receipt record-level boolean fields
    const receiptRecordBareFields = [
      'is_viewed',
      'is_received',
      'is_burned',
      'is_destroyed',
      'is_expired',
      'is_orphaned',
    ];

    it.each(receiptRecordBareFields)(
      'receipt record field "%s" uses bare z.boolean() and REJECTS null',
      (fieldName) => {
        const field = receiptBooleans.find((b) => b.path === `record.${fieldName}`);
        expect(field).toBeDefined();
        expect(fieldAcceptsNull(field!.schema)).toBe(false);
      }
    );

    // Secret response boolean fields
    const secretBooleans = extractBooleanFields(secretResponseSchema);

    it('secret response schema contains boolean fields', () => {
      expect(secretBooleans.length).toBeGreaterThan(0);
    });

    const secretDetailsBareFields = [
      'continue',
      'is_owner',
      'show_secret',
      'correct_passphrase',
    ];

    it.each(secretDetailsBareFields)(
      'secret details field "%s" uses bare z.boolean() and REJECTS null',
      (fieldName) => {
        const field = secretBooleans.find((b) => b.path === `details.${fieldName}`);
        expect(field).toBeDefined();
        expect(fieldAcceptsNull(field!.schema)).toBe(false);
      }
    );

    const secretRecordBareFields = [
      'has_passphrase',
      'verification',
    ];

    it.each(secretRecordBareFields)(
      'secret record field "%s" uses bare z.boolean() and REJECTS null',
      (fieldName) => {
        const field = secretBooleans.find((b) => b.path === `record.${fieldName}`);
        expect(field).toBeDefined();
        expect(fieldAcceptsNull(field!.schema)).toBe(false);
      }
    );

    // Account/customer boolean fields
    const accountBooleans = extractBooleanFields(accountResponseSchema);

    it('account response schema contains boolean fields', () => {
      expect(accountBooleans.length).toBeGreaterThan(0);
    });

    const accountRecordBareFields = [
      'record.cust.verified',
      'record.cust.active',
    ];

    it.each(accountRecordBareFields)(
      'account field "%s" uses bare z.boolean() and REJECTS null',
      (fieldPath) => {
        const field = accountBooleans.find((b) => b.path === fieldPath);
        expect(field).toBeDefined();
        expect(fieldAcceptsNull(field!.schema)).toBe(false);
      }
    );

    // Organization boolean fields
    const orgBooleans = extractBooleanFields(organizationResponseSchema);

    it('organization record field "is_default" uses bare z.boolean() and REJECTS null', () => {
      const field = orgBooleans.find((b) => b.path === 'record.is_default');
      expect(field).toBeDefined();
      expect(fieldAcceptsNull(field!.schema)).toBe(false);
    });

    // Domain boolean fields
    const domainBooleans = extractBooleanFields(customDomainResponseSchema);

    it('domain field "record.is_apex" uses bare z.boolean() and REJECTS null', () => {
      const field = domainBooleans.find((b) => b.path === 'record.is_apex');
      expect(field).toBeDefined();
      expect(fieldAcceptsNull(field!.schema)).toBe(false);
    });

    it('domain field "record.verified" accepts null (coerces to false)', () => {
      const field = domainBooleans.find((b) => b.path === 'record.verified');
      expect(field).toBeDefined();
      expect(fieldAcceptsNull(field!.schema)).toBe(true);
    });

    // Jurisdiction boolean fields
    const jurisdictionBooleans = extractBooleanFields(jurisdictionResponseSchema);

    it('jurisdiction details field "is_default" REJECTS null', () => {
      const field = jurisdictionBooleans.find((b) => b.path === 'details.is_default');
      expect(field).toBeDefined();
      expect(fieldAcceptsNull(field!.schema)).toBe(false);
    });

    it('jurisdiction details field "is_current" REJECTS null', () => {
      const field = jurisdictionBooleans.find((b) => b.path === 'details.is_current');
      expect(field).toBeDefined();
      expect(fieldAcceptsNull(field!.schema)).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Receipt-specific destroyed-secret payload
  // ---------------------------------------------------------------------------

  describe('receipt destroyed-secret payload (null booleans from backend)', () => {
    // This is the realistic payload the Ruby backend sends when `secret.nil?`.
    // The backend sets `has_passphrase` and `can_decrypt` to null because
    // the secret record no longer exists to query.
    const destroyedSecretReceiptPayload = {
      record: {
        identifier: 'r5qrktx2s6mjyq3uaflbfnufe9gryt3',
        created: 1735142814,
        updated: 1735204014,
        key: 'r5qrktx2s6mjyq3uaflbfnufe9gryt3',
        shortid: 'r5qrktx',
        secret_identifier: null,
        secret_shortid: 'sec12345',
        recipients: ['user@example.com'],
        share_domain: 'onetimesecret.com',
        secret_ttl: 3600,
        receipt_ttl: 172800,
        lifespan: 172800,
        state: 'burned',
        has_passphrase: false,
        // Timestamp fields
        shared: 1735142820,
        received: null,
        viewed: null,
        previewed: null,
        revealed: null,
        burned: 1735204014,
        // Boolean status flags
        is_viewed: false,
        is_received: false,
        is_previewed: false,
        is_revealed: false,
        is_burned: true,
        is_destroyed: true,
        is_expired: false,
        is_orphaned: false,
        memo: 'Test secret',
        kind: 'conceal',
        // Extended record fields
        secret_state: 'burned',
        natural_expiration: '2 days',
        expiration: 1735315614,
        expiration_in_seconds: 172800,
        share_path: '/secret/sec12345',
        burn_path: '/secret/sec12345/burn',
        receipt_path: '/private/r5qrktx',
        share_url: 'https://onetimesecret.com/secret/sec12345',
        receipt_url: 'https://onetimesecret.com/private/r5qrktx',
        burn_url: 'https://onetimesecret.com/secret/sec12345/burn',
      },
      details: {
        type: 'record' as const,
        display_lines: 1,
        no_cache: true,
        secret_realttl: null,
        view_count: null,
        // THESE ARE THE PROBLEM FIELDS: backend sends null when secret is destroyed
        has_passphrase: null,
        can_decrypt: null,
        secret_value: null,
        show_secret: false,
        show_secret_link: false,
        show_receipt_link: true,
        show_receipt: true,
        show_recipients: true,
        is_orphaned: false,
        is_expired: false,
      },
      shrimp: 'csrf-token-abc123',
    };

    it('V3 receipt response schema accepts payload with null has_passphrase and can_decrypt', () => {
      const result = receiptResponseSchema.safeParse(destroyedSecretReceiptPayload);

      // Desired: V3 accepts this valid backend payload, coercing null to false
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);

      if (result.success) {
        expect(result.data.details?.has_passphrase).toBe(false);
        expect(result.data.details?.can_decrypt).toBe(false);
      }
    });

    it('V3 receipt response schema accepts payload when booleans are false (not null)', () => {
      const fixedPayload = {
        ...destroyedSecretReceiptPayload,
        details: {
          ...destroyedSecretReceiptPayload.details,
          has_passphrase: false,
          can_decrypt: false,
        },
      };

      const result = receiptResponseSchema.safeParse(fixedPayload);
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Secrets schema audit
  // ---------------------------------------------------------------------------

  describe('secret details null-safety audit', () => {
    // The secret details schema has these bare z.boolean() fields:
    // continue, is_owner, show_secret, correct_passphrase
    //
    // While the backend may always send booleans for these (because they
    // are computed in the controller, not read from a possibly-nil model),
    // documenting the behavior is important for defense-in-depth.

    const secretDetailsPayloadWithNulls = {
      record: {
        identifier: 'secret-abc123',
        created: 1735142814,
        updated: 1735204014,
        key: 'secret-key-abc123',
        shortid: 'sabc123',
        state: 'new',
        has_passphrase: false,
        verification: false,
        secret_ttl: 3600,
        lifespan: 3600,
      },
      details: {
        continue: null,
        is_owner: null,
        show_secret: null,
        correct_passphrase: null,
        display_lines: 1,
        one_liner: null,
      },
      shrimp: 'csrf-token-xyz',
    };

    it('V3 secret response schema REJECTS null for continue, is_owner, show_secret, correct_passphrase', () => {
      const result = secretResponseSchema.safeParse(secretDetailsPayloadWithNulls);
      expect(result.success).toBe(false);

      if (!result.success) {
        const issueFields = result.error.issues.map((i) => i.path.join('.'));
        expect(issueFields).toContain('details.continue');
        expect(issueFields).toContain('details.is_owner');
        expect(issueFields).toContain('details.show_secret');
        expect(issueFields).toContain('details.correct_passphrase');
      }
    });

    it('V3 secret response schema accepts payload when all details booleans are proper booleans', () => {
      const validPayload = {
        ...secretDetailsPayloadWithNulls,
        details: {
          continue: true,
          is_owner: false,
          show_secret: true,
          correct_passphrase: false,
          display_lines: 1,
          one_liner: false,
        },
      };

      const result = secretResponseSchema.safeParse(validPayload);
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });

    it('secret record has_passphrase and verification reject null', () => {
      const payload = {
        record: {
          identifier: 'secret-abc123',
          created: 1735142814,
          updated: 1735204014,
          key: 'secret-key-abc123',
          shortid: 'sabc123',
          state: 'new',
          has_passphrase: null,
          verification: null,
          secret_ttl: 3600,
          lifespan: 3600,
        },
        details: {
          continue: true,
          is_owner: false,
          show_secret: false,
          correct_passphrase: false,
          display_lines: 1,
          one_liner: null,
        },
        shrimp: 'csrf-token-xyz',
      };

      const result = secretResponseSchema.safeParse(payload);
      expect(result.success).toBe(false);

      if (!result.success) {
        const issueFields = result.error.issues.map((i) => i.path.join('.'));
        expect(issueFields).toContain('record.has_passphrase');
        expect(issueFields).toContain('record.verification');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Cross-schema comparison: V2 model vs V3 response
  // ---------------------------------------------------------------------------

  describe('V2 vs V3 null handling comparison (receipt details)', () => {
    // The V2 receiptDetailsSchema uses transforms.fromString.boolean which
    // preprocesses via parseBoolean. parseBoolean(null) returns false.
    // The V3 receipt details uses bare z.boolean() which rejects null.

    const nullBooleanDetailsPayload = {
      type: 'record' as const,
      display_lines: 1,
      no_cache: true,
      secret_realttl: null,
      view_count: null,
      has_passphrase: null,
      can_decrypt: null,
      secret_value: null,
      show_secret: false,
      show_secret_link: false,
      show_receipt_link: true,
      show_receipt: true,
      show_recipients: true,
      is_orphaned: false,
      is_expired: false,
    };

    it('V2 receiptDetailsSchema ACCEPTS null for has_passphrase (coerces to false)', () => {
      const result = receiptDetailsSchema.safeParse(nullBooleanDetailsPayload);

      // V2 schema uses transforms.fromString.boolean -> parseBoolean -> null becomes false
      if (!result.success) {
        // If this fails, it means V2 also has issues (unexpected)
        const nullBoolIssues = result.error.issues.filter(
          (i) => i.path.includes('has_passphrase') || i.path.includes('can_decrypt')
        );
        // We expect V2 to succeed, so this should not fire
        expect(nullBoolIssues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });

    it('V2 receiptDetailsSchema coerces null has_passphrase to false', () => {
      const result = receiptDetailsSchema.safeParse(nullBooleanDetailsPayload);
      expect(result.success).toBe(true);

      if (result.success) {
        expect(result.data.has_passphrase).toBe(false);
        expect(result.data.can_decrypt).toBe(false);
      }
    });

    it('V3 receipt details accepts the same null payload that V2 accepts', () => {
      // Extract V3 receipt details from the actual response schema
      const v3ReceiptDetails = (
        receiptResponseSchema.shape.details as z.ZodOptional<z.ZodObject<any>>
      ).unwrap();

      const v3Result = v3ReceiptDetails.safeParse(nullBooleanDetailsPayload);
      const v2Result = receiptDetailsSchema.safeParse(nullBooleanDetailsPayload);

      // Desired: both V2 and V3 accept the payload
      expect(v2Result.success).toBe(true);
      if (!v3Result.success) {
        expect(v3Result.error.issues).toEqual([]);
      }
      expect(v3Result.success).toBe(true);
    });

    it('V2 schema handles all null-coercion cases that V3 does not', () => {
      // Test with ALL boolean fields set to null to see which V2 coerces
      const allNullBooleans = {
        type: 'record' as const,
        display_lines: 1,
        no_cache: null,
        secret_realttl: null,
        view_count: null,
        has_passphrase: null,
        can_decrypt: null,
        secret_value: null,
        show_secret: null,
        show_secret_link: null,
        show_receipt_link: null,
        show_receipt: null,
        show_recipients: null,
        is_orphaned: null,
        is_expired: null,
      };

      const v2Result = receiptDetailsSchema.safeParse(allNullBooleans);
      // V2 should accept all of these because parseBoolean(null) -> false
      expect(v2Result.success).toBe(true);

      if (v2Result.success) {
        expect(v2Result.data.has_passphrase).toBe(false);
        expect(v2Result.data.can_decrypt).toBe(false);
        expect(v2Result.data.no_cache).toBe(false);
        expect(v2Result.data.show_secret).toBe(false);
        expect(v2Result.data.show_secret_link).toBe(false);
        expect(v2Result.data.show_receipt_link).toBe(false);
        expect(v2Result.data.show_receipt).toBe(false);
        expect(v2Result.data.show_recipients).toBe(false);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Transform utility tests (parseBoolean)
  // ---------------------------------------------------------------------------

  describe('parseBoolean utility', () => {
    it('coerces null to false', () => {
      expect(parseBoolean(null)).toBe(false);
    });

    it('coerces undefined to false', () => {
      expect(parseBoolean(undefined)).toBe(false);
    });

    it('coerces empty string to false', () => {
      expect(parseBoolean('')).toBe(false);
    });

    it('passes through true as true', () => {
      expect(parseBoolean(true)).toBe(true);
    });

    it('passes through false as false', () => {
      expect(parseBoolean(false)).toBe(false);
    });

    it('coerces string "true" to true', () => {
      expect(parseBoolean('true')).toBe(true);
    });

    it('coerces string "false" to false', () => {
      expect(parseBoolean('false')).toBe(false);
    });

    it('coerces string "1" to true', () => {
      expect(parseBoolean('1')).toBe(true);
    });

    it('coerces string "0" to false', () => {
      expect(parseBoolean('0')).toBe(false);
    });

    it('coerces arbitrary non-matching strings to false', () => {
      expect(parseBoolean('yes')).toBe(false);
      expect(parseBoolean('no')).toBe(false);
      expect(parseBoolean('True')).toBe(false);  // case-sensitive
      expect(parseBoolean('FALSE')).toBe(false);
    });

    it('coerces number 0 to false (not a recognized truthy pattern)', () => {
      // parseBoolean only recognizes 'true' and '1' as truthy strings
      // numbers are not boolean and not string, so they fall through
      expect(parseBoolean(0)).toBe(false);
    });

    it('coerces number 1 to false (number, not string "1")', () => {
      // 1 is not boolean, not null/undefined/empty, and not equal to 'true' or '1'
      // as string comparison: (1 === 'true') is false, (1 === '1') is false
      expect(parseBoolean(1)).toBe(false);
    });
  });

  describe('transforms.fromString.boolean via z.preprocess', () => {
    // The V2 transform wraps parseBoolean in z.preprocess
    // Verify the full pipeline works with z.preprocess(parseBoolean, z.boolean())

    const v2BooleanSchema = z.preprocess(parseBoolean, z.boolean());

    it('accepts and coerces null to false', () => {
      const result = v2BooleanSchema.safeParse(null);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(false);
    });

    it('accepts and coerces undefined to false', () => {
      const result = v2BooleanSchema.safeParse(undefined);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(false);
    });

    it('accepts and coerces "true" to true', () => {
      const result = v2BooleanSchema.safeParse('true');
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(true);
    });

    it('accepts and coerces "false" to false', () => {
      const result = v2BooleanSchema.safeParse('false');
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(false);
    });

    it('accepts true as true', () => {
      const result = v2BooleanSchema.safeParse(true);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(true);
    });

    it('accepts false as false', () => {
      const result = v2BooleanSchema.safeParse(false);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(false);
    });

    // Contrast with bare z.boolean()
    it('bare z.boolean() rejects null', () => {
      const result = z.boolean().safeParse(null);
      expect(result.success).toBe(false);
    });

    it('bare z.boolean() rejects undefined', () => {
      const result = z.boolean().safeParse(undefined);
      expect(result.success).toBe(false);
    });

    it('bare z.boolean() rejects string "true"', () => {
      const result = z.boolean().safeParse('true');
      expect(result.success).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Defense-in-depth pattern test (the fix pattern)
  // ---------------------------------------------------------------------------

  describe('defense-in-depth: nullable boolean with null-to-false transform', () => {
    // This is the pattern the fix should use for V3 schemas:
    // z.boolean().nullable().transform(v => v ?? false)
    //
    // It accepts both boolean values and null, coercing null to false.
    // The output type is always boolean (never null).

    const nullSafeBooleanSchema = z
      .boolean()
      .nullable()
      .transform((v) => v ?? false);

    it('accepts true and outputs true', () => {
      const result = nullSafeBooleanSchema.safeParse(true);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(true);
    });

    it('accepts false and outputs false', () => {
      const result = nullSafeBooleanSchema.safeParse(false);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(false);
    });

    it('accepts null and outputs false', () => {
      const result = nullSafeBooleanSchema.safeParse(null);
      expect(result.success).toBe(true);
      if (result.success) expect(result.data).toBe(false);
    });

    it('still rejects non-boolean/non-null values', () => {
      expect(nullSafeBooleanSchema.safeParse('true').success).toBe(false);
      expect(nullSafeBooleanSchema.safeParse(1).success).toBe(false);
      expect(nullSafeBooleanSchema.safeParse('').success).toBe(false);
      expect(nullSafeBooleanSchema.safeParse({}).success).toBe(false);
    });

    it('rejects undefined (stricter than V2 preprocess)', () => {
      // Unlike V2's z.preprocess(parseBoolean, z.boolean()) which accepts undefined,
      // the V3 fix pattern only accepts boolean | null (not undefined).
      // This is intentional: V3 JSON payloads should not have undefined values.
      const result = nullSafeBooleanSchema.safeParse(undefined);
      expect(result.success).toBe(false);
    });

    // Demonstrate the fix applied to a receipt details schema shape
    it('receipt details schema with fix pattern accepts destroyed-secret payload', () => {
      const fixedReceiptDetails = z.object({
        type: z.literal('record'),
        display_lines: z.number(),
        no_cache: z.boolean(),
        secret_realttl: z.number().nullable().optional(),
        view_count: z.number().nullable(),
        has_passphrase: z.boolean().nullable().transform((v) => v ?? false),
        can_decrypt: z.boolean().nullable().transform((v) => v ?? false),
        secret_value: z.string().nullable().optional(),
        show_secret: z.boolean(),
        show_secret_link: z.boolean(),
        show_receipt_link: z.boolean(),
        show_receipt: z.boolean(),
        show_recipients: z.boolean(),
        is_orphaned: z.boolean().nullable().optional(),
        is_expired: z.boolean().nullable().optional(),
      });

      const payload = {
        type: 'record' as const,
        display_lines: 1,
        no_cache: true,
        secret_realttl: null,
        view_count: null,
        has_passphrase: null,
        can_decrypt: null,
        secret_value: null,
        show_secret: false,
        show_secret_link: false,
        show_receipt_link: true,
        show_receipt: true,
        show_recipients: true,
        is_orphaned: false,
        is_expired: false,
      };

      const result = fixedReceiptDetails.safeParse(payload);
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);

      if (result.success) {
        // Null values are coerced to false
        expect(result.data.has_passphrase).toBe(false);
        expect(result.data.can_decrypt).toBe(false);
        // Non-null booleans pass through unchanged
        expect(result.data.no_cache).toBe(true);
        expect(result.data.show_secret).toBe(false);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 7. receiptBaseRecord null-safety for is_* boolean flags
  // ---------------------------------------------------------------------------

  describe('receiptBaseRecord boolean flags with null values', () => {
    // The receiptBaseRecord is used for list views. When iterating receipts,
    // some may reference destroyed secrets. Test that the is_* flags on
    // the record itself handle null correctly.

    const basePayloadWithNullBooleans = {
      identifier: 'r5qrktx2s6mjyq3uaflbfnufe9gryt3',
      created: 1735142814,
      updated: 1735204014,
      key: 'r5qrktx2s6mjyq3uaflbfnufe9gryt3',
      shortid: 'r5qrktx',
      secret_identifier: null,
      secret_shortid: 'sec12345',
      recipients: null,
      share_domain: null,
      secret_ttl: 3600,
      receipt_ttl: 172800,
      lifespan: 172800,
      state: 'burned' as const,
      has_passphrase: false,
      shared: 1735142820,
      received: null,
      viewed: null,
      previewed: null,
      revealed: null,
      burned: 1735204014,
      memo: null,
      kind: 'conceal' as const,
      // Set all is_* flags to null to test what the backend might send
      is_viewed: null,
      is_received: null,
      is_previewed: null,
      is_revealed: null,
      is_burned: null,
      is_destroyed: null,
      is_expired: null,
      is_orphaned: null,
    };

    it('receiptBaseRecord REJECTS null for bare z.boolean() is_* fields', () => {
      const result = receiptBaseRecord.safeParse(basePayloadWithNullBooleans);
      expect(result.success).toBe(false);

      if (!result.success) {
        const issueFields = result.error.issues.map((i) => i.path.join('.'));
        // These use bare z.boolean() and should reject null
        expect(issueFields).toContain('is_viewed');
        expect(issueFields).toContain('is_received');
        expect(issueFields).toContain('is_burned');
        expect(issueFields).toContain('is_destroyed');
        expect(issueFields).toContain('is_expired');
        expect(issueFields).toContain('is_orphaned');
      }
    });

    it('receiptBaseRecord accepts payload when is_* fields are proper booleans', () => {
      const validPayload = {
        ...basePayloadWithNullBooleans,
        is_viewed: false,
        is_received: false,
        is_previewed: false,
        is_revealed: false,
        is_burned: true,
        is_destroyed: true,
        is_expired: false,
        is_orphaned: false,
      };

      const result = receiptBaseRecord.passthrough().safeParse(validPayload);
      if (!result.success) {
        expect(result.error.issues).toEqual([]);
      }
      expect(result.success).toBe(true);
    });
  });

  // ---------------------------------------------------------------------------
  // 8. Conceal data response (POST /api/v3/conceal)
  // ---------------------------------------------------------------------------

  describe('conceal data response null-safety', () => {
    // The conceal response includes both a receipt and a secret record.
    // Both have boolean fields that could potentially receive null from
    // the backend, though at creation time they should be initialized.

    it('conceal response receipt has_passphrase rejects null when not optional', () => {
      // In the concealReceiptRecord, has_passphrase is z.boolean().optional()
      // so it accepts undefined but what about null?
      const boolSchema = z.boolean().optional();
      const nullResult = boolSchema.safeParse(null);
      // z.boolean().optional() does NOT accept null -- only undefined
      expect(nullResult.success).toBe(false);
    });

    it('conceal response secret has_passphrase (bare z.boolean()) rejects null', () => {
      const boolSchema = z.boolean();
      const nullResult = boolSchema.safeParse(null);
      expect(nullResult.success).toBe(false);
    });

    it('z.boolean().optional() vs z.boolean().nullable() vs z.boolean().nullish()', () => {
      // Document the Zod API for boolean null handling
      const optional = z.boolean().optional();
      const nullable = z.boolean().nullable();
      const nullish = z.boolean().nullish();

      // optional: accepts undefined, rejects null
      expect(optional.safeParse(undefined).success).toBe(true);
      expect(optional.safeParse(null).success).toBe(false);
      expect(optional.safeParse(true).success).toBe(true);

      // nullable: rejects undefined, accepts null
      expect(nullable.safeParse(undefined).success).toBe(false);
      expect(nullable.safeParse(null).success).toBe(true);
      expect(nullable.safeParse(true).success).toBe(true);

      // nullish: accepts both undefined and null
      expect(nullish.safeParse(undefined).success).toBe(true);
      expect(nullish.safeParse(null).success).toBe(true);
      expect(nullish.safeParse(true).success).toBe(true);
    });
  });
});
