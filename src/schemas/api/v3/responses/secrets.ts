// src/schemas/api/v3/responses/secrets.ts
//
// V3 JSON wire-format schemas for secret endpoints.
// Derives from canonical schemas, adding V3-specific timestamp transforms.
//
// Timestamps use transforms.fromNumber.toDate so that .parse() returns
// Date objects for the frontend while io:"input" still documents them
// as numbers in OpenAPI.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  secretBaseCanonical,
  secretCanonical,
  secretDetailsCanonical,
} from '@/schemas/api/canonical/records';
import { receiptBaseRecord } from '@/schemas/api/v3/responses/receipts';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas (V3 wire format: canonical + timestamp transforms)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 secret base record.
 *
 * Derives from canonical, adds V3 timestamp transforms (number → Date).
 */
const secretBaseRecord = secretBaseCanonical.extend({
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
});

/**
 * V3 full secret record with TTL fields.
 */
const secretRecord = secretCanonical.extend({
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
});

/**
 * V3 secret details.
 *
 * Uses canonical directly — all fields are native JSON types in V3.
 */
const secretDetails = secretDetailsCanonical;

// ─────────────────────────────────────────────────────────────────────────────
// Conceal response schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Combined receipt + secret returned by POST /api/v3/conceal and /api/v3/generate.
 *
 * Uses receiptBaseRecord from receipts.ts to eliminate duplication.
 */
const concealDataRecord = z.object({
  receipt: receiptBaseRecord,
  secret: secretRecord,
  share_domain: z.string().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const concealDataResponseSchema = createApiResponseSchema(concealDataRecord);
export const secretResponseSchema = createApiResponseSchema(secretRecord, secretDetails);
export const secretListResponseSchema = createApiListResponseSchema(secretBaseRecord);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ConcealDataResponse = z.infer<typeof concealDataResponseSchema>;
export type SecretResponse = z.infer<typeof secretResponseSchema>;
export type SecretListResponse = z.infer<typeof secretListResponseSchema>;
