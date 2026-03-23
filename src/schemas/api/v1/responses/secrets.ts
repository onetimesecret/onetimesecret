// src/schemas/api/v1/responses/secrets.ts
//
// V1 response schemas for secret and receipt endpoints.
// These reflect the receipt_hsh output shape (v0.23.x field names)
// and V1-specific response structures.
//
// Architecture: contract → shapes → api responses
// - v1ReceiptSchema from shapes/v1/receipt defines the V1 wire format
// - Response schemas extend the base shape with required v0.24 additive fields
//
// The V1 API backend always emits BOTH old (v0.23) and new (v0.24) field names
// for migration support. The shape marks additive fields as optional for backward
// compatibility, but the response schema makes them required since the backend
// always includes them.

import { v1ReceiptSchema } from '@/schemas/shapes/v1/secret';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Receipt response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V1 receipt response.
 *
 * Extends v1ReceiptSchema from shapes with:
 * 1. Required additive fields (backend always emits them)
 * 2. Nullable overrides for fields that can be null in responses
 *
 * Note: The base shape has additive fields as optional for wire format flexibility,
 * but response validation requires them since the backend always emits them.
 */
export const v1ReceiptResponseSchema = v1ReceiptSchema.extend({
  // Nullable field overrides (backend can return null for these)
  ttl: z.number().int().nullable(),
  metadata_ttl: z.number().int().nullable(),
  created: z.number().int().nullable(),
  updated: z.number().int().nullable(),

  // v0.24 additive fields are required in actual responses
  identifier: z
    .string()
    .describe('v0.24 name for metadata_key. Prefer this field for new integrations.'),
  recipients: z.array(z.string()).describe('v0.24 name for recipient.'),
  receipt_ttl: z
    .number()
    .int()
    .nullable()
    .describe('v0.24 name for metadata_ttl. Seconds remaining before expiry.'),
  receipt_url: z
    .string()
    .nullable()
    .optional()
    .describe('v0.24 name for metadata_url. URL to view the receipt.'),
});

export const v1ReceiptListResponseSchema = z.array(v1ReceiptResponseSchema);

// ─────────────────────────────────────────────────────────────────────────────
// Secret operation response schemas
// ─────────────────────────────────────────────────────────────────────────────

// POST /secret/:key — reveal a secret's value
export const v1SecretRevealResponseSchema = z.object({
  value: z.string(),
  secret_key: z.string(),
  share_domain: z.string(),
});

// POST /receipt/:key/burn — burn a secret
// The Ruby controller sends secret_shortkey (v0.23 name), mapped from
// receipt.secret_shortid (v0.24 internal name). See controllers/index.rb:170.
export const v1BurnSecretResponseSchema = z.object({
  state: v1ReceiptResponseSchema,
  secret_shortkey: z.string(),
});

export type V1ReceiptResponse = z.infer<typeof v1ReceiptResponseSchema>;
export type V1ReceiptListResponse = z.infer<typeof v1ReceiptListResponseSchema>;
export type V1SecretRevealResponse = z.infer<typeof v1SecretRevealResponseSchema>;
export type V1BurnSecretResponse = z.infer<typeof v1BurnSecretResponseSchema>;
