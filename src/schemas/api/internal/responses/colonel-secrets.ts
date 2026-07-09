// src/schemas/api/internal/responses/colonel-secrets.ts
//
// Per-resource colonel/admin schemas for the Secrets screen (ticket #30).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are untouched
// (the Zod tripwire, epic non-goal). The secrets LIST reuses the existing
// `colonelSecretsResponseSchema` / `colonelSecretSchema` from ./colonel.ts; this
// file adds only the two shapes that had no frontend schema yet:
//
//   - GetSecretReceipt → GET    /api/colonel/secrets/:secret_id  (receipt drawer)
//   - DeleteSecret     → DELETE /api/colonel/secrets/:secret_id  (guarded delete ack)
//
// Shapes verified against the live logic classes
// (apps/api/colonel/logic/colonel/get_secret_receipt.rb, delete_secret.rb):
// timestamps arrive as Unix-epoch numbers and are transformed to Date, mirroring
// the existing `colonelSecretSchema`.

import { createApiResponseSchema } from '@/schemas/api/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ============================================================================
// GetSecretReceipt — receipt/detail drawer
// ============================================================================

/**
 * The core secret record on the receipt drawer (GetSecretReceipt `record`).
 * `secret_id` is the secret's objid (the id used for routing + delete);
 * `shortid` is the human-facing short id shown in the list. No ciphertext is
 * ever transmitted — only `has_ciphertext` + `ciphertext_length`.
 */
export const colonelSecretReceiptRecordSchema = z.object({
  secret_id: z.string(),
  shortid: z.string(),
  state: z.string(),
  lifespan: z.number().nullable(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDateNullable,
  expiration: transforms.fromNumber.toDateNullable,
  age: z.number(),
  owner_id: z.string().nullable(),
  receipt_id: z.string().nullable(),
  has_ciphertext: z.boolean(),
  ciphertext_length: z.number(),
});

/**
 * Associated receipt metadata (GetSecretReceipt `details.metadata`). Null when
 * the secret has no receipt (`receipt_identifier` unset). `secret_ttl` is a
 * Familia field that may arrive as a string or number; `recipients` may be a
 * plain string or an array depending on how the receipt was created — both are
 * accepted so a data-drift edge never crashes a read-only inspector.
 */
export const colonelSecretReceiptMetadataSchema = z.object({
  receipt_id: z.string(),
  shortid: z.string(),
  state: z.string(),
  secret_ttl: z.union([z.number(), z.string()]).nullable(),
  recipients: z.union([z.array(z.string()), z.string()]).nullable(),
  has_passphrase: z.boolean(),
  share_domain: z.string().nullable(),
  created: transforms.fromNumber.toDate,
  secret_expired: z.boolean(),
});

/**
 * Owner read-out (GetSecretReceipt `details.owner`). Null for anonymous secrets
 * (`owner_id` == 'anon' / unset). `email` is the OBSCURED email; `user_id` is
 * the owner's objid.
 */
export const colonelSecretReceiptOwnerSchema = z.object({
  user_id: z.string(),
  email: z.string(),
  role: z.string(),
  verified: z.boolean(),
});

/** The `details` payload of GetSecretReceipt: receipt metadata + owner. */
export const colonelSecretReceiptDetailsSchema = z.object({
  metadata: colonelSecretReceiptMetadataSchema.nullable(),
  owner: colonelSecretReceiptOwnerSchema.nullable(),
});

// ============================================================================
// DeleteSecret — guarded delete ack
// ============================================================================

/** The deleted secret summary (DeleteSecret `record.secret`). */
export const colonelSecretDeleteSecretSchema = z.object({
  secret_id: z.string(),
  shortid: z.string(),
  state: z.string(),
  owner_id: z.string().nullable(),
});

/** The deleted receipt summary (DeleteSecret `record.metadata`), null if none. */
export const colonelSecretDeleteMetadataSchema = z.object({
  receipt_id: z.string(),
  shortid: z.string(),
});

/**
 * DeleteSecret `record`: a delete confirmation carrying the destroyed secret's
 * public identity + the associated receipt (when one existed). The UI treats a
 * 2xx as success and refreshes the list, so this schema is a live tripwire
 * rather than a routing source.
 */
export const colonelSecretDeleteRecordSchema = z.object({
  deleted: z.boolean(),
  secret: colonelSecretDeleteSecretSchema,
  metadata: colonelSecretDeleteMetadataSchema.nullable(),
});

/** DeleteSecret `details`: a human-readable ack message. */
export const colonelSecretDeleteDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelSecretReceiptRecord = z.infer<typeof colonelSecretReceiptRecordSchema>;
export type ColonelSecretReceiptMetadata = z.infer<typeof colonelSecretReceiptMetadataSchema>;
export type ColonelSecretReceiptOwner = z.infer<typeof colonelSecretReceiptOwnerSchema>;
export type ColonelSecretReceiptDetails = z.infer<typeof colonelSecretReceiptDetailsSchema>;
export type ColonelSecretDeleteRecord = z.infer<typeof colonelSecretDeleteRecordSchema>;
export type ColonelSecretDeleteDetails = z.infer<typeof colonelSecretDeleteDetailsSchema>;

// Wrapped response schemas for the colonel Secrets screen (ticket #30).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The secrets LIST endpoint keeps its existing `colonelSecretsResponseSchema`
// in ./colonel.ts (registry-only since the browse-all UI was removed — the
// screen is lookup-first). This file wraps ONLY the two single-record
// envelopes: the receipt read-out + the guarded-delete ack.
//
// The view imports these DIRECTLY (CONTRACT 3) so it typechecks independently of
// the registry; the Integrate step adds the registry keys from wiringInstructions.

// GET /api/colonel/secrets/:secret_id → GetSecretReceipt
export const colonelSecretReceiptResponseSchema = createApiResponseSchema(
  colonelSecretReceiptRecordSchema,
  colonelSecretReceiptDetailsSchema
);

// DELETE /api/colonel/secrets/:secret_id → DeleteSecret
export const colonelSecretDeleteResponseSchema = createApiResponseSchema(
  colonelSecretDeleteRecordSchema,
  colonelSecretDeleteDetailsSchema
);

export type ColonelSecretReceiptResponse = z.infer<typeof colonelSecretReceiptResponseSchema>;
export type ColonelSecretDeleteResponse = z.infer<typeof colonelSecretDeleteResponseSchema>;
