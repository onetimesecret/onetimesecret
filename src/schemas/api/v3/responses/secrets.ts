// src/schemas/api/v3/responses/secrets.ts
//
// V3 API response schemas for secret endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiListResponseSchema, createApiResponseSchema } from '@/schemas/api/base';
import {
  concealDataSchema,
  secretBaseSchema,
  secretDetailsSchema,
  secretSchema,
} from '@/schemas/shapes/v3/secret';
import { z } from 'zod';
import { secretStatusRecordSchema } from './producer-records';

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const concealDataResponseSchema = createApiResponseSchema(concealDataSchema);
export const secretResponseSchema = createApiResponseSchema(secretSchema, secretDetailsSchema);
export const secretListResponseSchema = createApiListResponseSchema(secretBaseSchema);

/** Status has its own found/missing contract, not reveal-page details. */
export const secretStatusResponseSchema = z.union([
  z.strictObject({ record: z.strictObject({ state: z.literal('unknown') }) }),
  z.strictObject({
    record: secretStatusRecordSchema,
    details: z.strictObject({ current_expiration: z.number().nullable() }),
  }),
]);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ConcealDataResponse = z.infer<typeof concealDataResponseSchema>;
export type SecretResponse = z.infer<typeof secretResponseSchema>;
export type SecretListResponse = z.infer<typeof secretListResponseSchema>;
export type SecretStatusResponse = z.infer<typeof secretStatusResponseSchema>;
