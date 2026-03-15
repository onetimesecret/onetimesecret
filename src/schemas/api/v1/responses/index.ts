// src/schemas/api/v1/responses/index.ts
//
// V1 response schema registry.

import {
  v1ReceiptResponseSchema,
  v1ReceiptListResponseSchema,
  v1SecretRevealResponseSchema,
  v1BurnSecretResponseSchema,
} from './secrets';

// status and authcheck share the same shape as the V3 systemStatus schema
import { systemStatusResponseSchema } from '../../v3/responses/meta';

export const v1ResponseSchemas = {
  v1Status: systemStatusResponseSchema,
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
