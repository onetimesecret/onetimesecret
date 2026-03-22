// src/schemas/api/v3/responses/secrets.ts
//
// V3 API response schemas for secret endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  secretBaseRecord,
  secretRecord,
  secretDetails,
  concealDataRecord,
} from '@/schemas/shapes/v3/secret';
import { z } from 'zod';

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
