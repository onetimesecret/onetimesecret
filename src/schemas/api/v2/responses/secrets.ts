// src/schemas/api/v2/responses/secrets.ts
//
// Response schemas for secret endpoints.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import { concealDataSchema } from './content/secrets';
import { secretResponsesSchema } from '@/schemas/shapes/v2';
import { secretDetailsSchema, secretSchema } from '@/schemas/shapes/v2/secret';
import { z } from 'zod';

export const concealDataResponseSchema = createApiResponseSchema(concealDataSchema);
export const secretResponseSchema = createApiResponseSchema(secretSchema, secretDetailsSchema);
export const secretListResponseSchema = createApiListResponseSchema(secretResponsesSchema);

// Secret status response has two possible shapes:
// 1. When secret exists: { record: secretSchema, details: { current_expiration } }
// 2. When secret doesn't exist: { record: { state: 'unknown' } }
const secretStatusUnknownSchema = z.object({
  record: z.object({ state: z.literal('unknown') }),
});

const secretStatusDetailsSchema = z.object({
  current_expiration: z.number().nullable(),
});

const secretStatusFoundSchema = z.object({
  record: secretSchema,
  details: secretStatusDetailsSchema,
});

export const secretStatusResponseSchema = z.union([
  secretStatusUnknownSchema,
  secretStatusFoundSchema,
]);

export type ConcealDataResponse = z.infer<typeof concealDataResponseSchema>;
export type SecretResponse = z.infer<typeof secretResponseSchema>;
export type SecretListResponse = z.infer<typeof secretListResponseSchema>;
export type SecretStatusResponse = z.infer<typeof secretStatusResponseSchema>;
