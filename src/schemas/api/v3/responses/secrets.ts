// src/schemas/api/v3/responses/secrets.ts
//
// V3 API response schemas for secret endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  secretBaseSchema,
  secretSchema,
  secretDetailsSchema,
  concealDataSchema,
} from '@/schemas/shapes/v3/secret';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const concealDataResponseSchema = createApiResponseSchema(concealDataSchema);
export const secretResponseSchema = createApiResponseSchema(secretSchema, secretDetailsSchema);
export const secretListResponseSchema = createApiListResponseSchema(secretBaseSchema);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ConcealDataResponse = z.infer<typeof concealDataResponseSchema>;
export type SecretResponse = z.infer<typeof secretResponseSchema>;
export type SecretListResponse = z.infer<typeof secretListResponseSchema>;
