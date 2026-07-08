// src/schemas/api/internal/responses/colonel-secrets.ts
//
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

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  colonelSecretReceiptRecordSchema,
  colonelSecretReceiptDetailsSchema,
  colonelSecretDeleteRecordSchema,
  colonelSecretDeleteDetailsSchema,
} from '@/schemas/api/account/responses/colonel-secrets';
import { z } from 'zod';

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
