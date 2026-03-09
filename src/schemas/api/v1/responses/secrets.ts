// src/schemas/api/v1/responses/secrets.ts
//
// V1 response schemas for secret and receipt endpoints.
// These reflect the receipt_hsh output shape (v0.23.x field names)
// and V1-specific response structures.

import { z } from 'zod';

// The receipt_hsh output (see V1::Controllers::ClassMethods#receipt_hsh).
// Fields are conditionally present based on state:
//   - state='received': secret_ttl and secret_key are removed, received is present
//   - other states: received is removed
const v1ReceiptBase = z.object({
  custid: z.string(),
  metadata_key: z.string(),
  secret_key: z.string().optional(),
  ttl: z.number().int().nullable(),
  metadata_ttl: z.number().int().nullable(),
  secret_ttl: z.number().int().nullable().optional(),
  state: z.string(),
  updated: z.number().int().nullable(),
  created: z.number().int().nullable(),
  received: z.number().int().optional(),
  recipient: z.array(z.string()),
  share_domain: z.string(),
  value: z.string().optional(),
  passphrase_required: z.boolean().optional(),
});

export const v1ReceiptResponseSchema = v1ReceiptBase;

export const v1ReceiptListResponseSchema = z.array(v1ReceiptBase);

// POST /secret/:key — reveal a secret's value
export const v1SecretRevealResponseSchema = z.object({
  value: z.string(),
  secret_key: z.string(),
  share_domain: z.string(),
});

// POST /receipt/:key/burn — burn a secret
export const v1BurnSecretResponseSchema = z.object({
  state: v1ReceiptBase,
  secret_shortid: z.string(),
});

export type V1ReceiptResponse = z.infer<typeof v1ReceiptResponseSchema>;
export type V1ReceiptListResponse = z.infer<typeof v1ReceiptListResponseSchema>;
export type V1SecretRevealResponse = z.infer<typeof v1SecretRevealResponseSchema>;
export type V1BurnSecretResponse = z.infer<typeof v1BurnSecretResponseSchema>;
