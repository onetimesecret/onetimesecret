// src/schemas/api/v2/responses/secrets.ts
//
// Response schemas for secret endpoints.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import { concealDataSchema } from '@/schemas/api/v2/endpoints/secrets';
import { secretResponsesSchema } from '@/schemas/models';
import { secretDetailsSchema, secretSchema } from '@/schemas/models/secret';
import { z } from 'zod';

export const concealDataResponseSchema = createApiResponseSchema(concealDataSchema);
export const secretResponseSchema = createApiResponseSchema(secretSchema, secretDetailsSchema);
export const secretListResponseSchema = createApiListResponseSchema(secretResponsesSchema);

export type ConcealDataResponse = z.infer<typeof concealDataResponseSchema>;
export type SecretResponse = z.infer<typeof secretResponseSchema>;
export type SecretListResponse = z.infer<typeof secretListResponseSchema>;
