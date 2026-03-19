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

export type ConcealDataResponse = z.infer<typeof concealDataResponseSchema>;
export type SecretResponse = z.infer<typeof secretResponseSchema>;
export type SecretListResponse = z.infer<typeof secretListResponseSchema>;
