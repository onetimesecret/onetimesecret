// src/schemas/api/v3/responses/secrets.ts
//
// V3 JSON wire-format schemas for secret endpoints.
// Timestamps use transforms.fromNumber.toDate so that .parse() returns
// Date objects for the frontend while io:"input" still documents them
// as numbers in OpenAPI.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas (JSON wire shapes)
// ─────────────────────────────────────────────────────────────────────────────

const secretStateValues = ['new', 'received', 'revealed', 'burned', 'viewed', 'previewed'] as const;

/** Core secret fields shared between list and detail views. */
const secretBaseRecord = z.object({
  identifier: z.string(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  key: z.string(),
  shortid: z.string(),
  state: z.enum(secretStateValues),
  has_passphrase: z.boolean(),
  verification: z.boolean(),
  secret_value: z.string().optional(),
});

/** Full secret record with TTL fields. */
const secretRecord = secretBaseRecord.extend({
  secret_ttl: z.number(),         // seconds (duration, not timestamp)
  lifespan: z.number(),           // seconds
});

/** Secret detail fields (metadata alongside the record). */
const secretDetails = z.object({
  continue: z.boolean(),
  is_owner: z.boolean(),
  show_secret: z.boolean(),
  correct_passphrase: z.boolean(),
  display_lines: z.number(),
  one_liner: z.boolean().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Receipt schema for conceal response (creation-time receipt, no URLs)
// ─────────────────────────────────────────────────────────────────────────────

const receiptStateValues = [
  'new', 'shared', 'received', 'revealed', 'burned',
  'viewed', 'previewed', 'expired', 'orphaned',
] as const;

const concealReceiptRecord = z.object({
  identifier: z.string(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  key: z.string(),
  shortid: z.string(),
  secret_shortid: z.string().optional(),
  recipients: z.array(z.string()).or(z.string()).nullable().optional(),
  share_domain: z.string().nullable().optional(),
  secret_ttl: z.number(),
  receipt_ttl: z.number(),
  lifespan: z.number(),
  state: z.enum(receiptStateValues),
  has_passphrase: z.boolean().optional(),
  shared: transforms.fromNumber.toDateNullish,
  received: transforms.fromNumber.toDateNullish,
  viewed: transforms.fromNumber.toDateNullish,
  previewed: transforms.fromNumber.toDateNullish,
  revealed: transforms.fromNumber.toDateNullish,
  burned: transforms.fromNumber.toDateNullish,
  is_viewed: z.boolean(),
  is_received: z.boolean(),
  is_previewed: z.boolean().optional(),
  is_revealed: z.boolean().optional(),
  is_burned: z.boolean(),
  is_destroyed: z.boolean(),
  is_expired: z.boolean(),
  is_orphaned: z.boolean(),
  memo: z.string().nullable().optional(),
  kind: z.enum(['generate', 'conceal']).or(z.literal('')).nullable().optional(),
});

/** Combined receipt + secret returned by POST /api/v3/conceal and /api/v3/generate. */
const concealDataRecord = z.object({
  receipt: concealReceiptRecord,
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
