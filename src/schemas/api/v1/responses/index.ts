// src/schemas/api/v1/responses/index.ts
//
// V1 response schema registry.

import { z } from 'zod';

import {
  v1ReceiptResponseSchema,
  v1ReceiptListResponseSchema,
  v1SecretRevealResponseSchema,
  v1BurnSecretResponseSchema,
} from './secrets';

// V1 status returns {status, locale} without a `success` field.
// V3 systemStatusResponseSchema requires `success`, so V1 needs its own schema.
export const v1StatusResponseSchema = z.object({
  status: z.string(),
  locale: z.string(),
});

export type V1StatusResponse = z.infer<typeof v1StatusResponseSchema>;

export const v1ResponseSchemas = {
  v1Status: v1StatusResponseSchema,
  v1Receipt: v1ReceiptResponseSchema,
  v1ReceiptList: v1ReceiptListResponseSchema,
  v1SecretReveal: v1SecretRevealResponseSchema,
  v1BurnSecret: v1BurnSecretResponseSchema,
} as const;

export {
  v1ReceiptResponseSchema,
  v1ReceiptListResponseSchema,
  v1SecretRevealResponseSchema,
  v1BurnSecretResponseSchema,
};

export type {
  V1ReceiptResponse,
  V1ReceiptListResponse,
  V1SecretRevealResponse,
  V1BurnSecretResponse,
} from './secrets';
