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
  metadata_url: z.string().nullable().optional(),
  state: z.string(),
  updated: z.number().int().nullable(),
  created: z.number().int().nullable(),
  received: z.number().int().optional(),
  recipient: z.array(z.string()),
  share_domain: z.string(),
  value: z.string().optional(),
  passphrase_required: z.boolean().optional(),

  // Additive v0.24 field names (#2617) — aliases for v0.23 fields above.
  // Emitted alongside their v0.23 counterparts so clients can migrate
  // incrementally. See V1_ADDITIVE_FIELD_MAP in class_methods.rb.
  identifier: z.string()
    .describe('v0.24 name for metadata_key. Prefer this field for new integrations.'),
  secret_identifier: z.string().optional()
    .describe('v0.24 name for secret_key. Absent when state is received.'),
  has_passphrase: z.boolean().optional()
    .describe('v0.24 name for passphrase_required. Present only when a passphrase was set.'),
  recipients: z.array(z.string())
    .describe('v0.24 name for recipient.'),
  receipt_ttl: z.number().int().nullable()
    .describe('v0.24 name for metadata_ttl. Seconds remaining before expiry.'),
  receipt_url: z.string().nullable().optional()
    .describe('v0.24 name for metadata_url. URL to view the receipt.'),
  secret_value: z.string().optional()
    .describe('v0.24 name for value. Present only when the secret content is included.'),
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
// The Ruby controller sends secret_shortkey (v0.23 name), mapped from
// receipt.secret_shortid (v0.24 internal name). See controllers/index.rb:170.
export const v1BurnSecretResponseSchema = z.object({
  state: v1ReceiptBase,
  secret_shortkey: z.string(),
});

export type V1ReceiptResponse = z.infer<typeof v1ReceiptResponseSchema>;
export type V1ReceiptListResponse = z.infer<typeof v1ReceiptListResponseSchema>;
export type V1SecretRevealResponse = z.infer<typeof v1SecretRevealResponseSchema>;
export type V1BurnSecretResponse = z.infer<typeof v1BurnSecretResponseSchema>;
