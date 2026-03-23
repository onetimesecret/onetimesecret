// src/schemas/api/v2/responses/account.ts
//
// V2 response schemas for account endpoints.
// Wraps the shared account/customer schemas in API response envelopes.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  accountSchema,
  apiTokenSchema,
  checkAuthDetailsSchema,
} from '@/schemas/api/account/responses/account';
import { customerSchema } from '@/schemas/shapes/v2/customer';
import { z } from 'zod';

// -----------------------------------------------------------------------------
// Response schemas
// -----------------------------------------------------------------------------

export const accountResponseSchema = createApiResponseSchema(accountSchema);
export const apiTokenResponseSchema = createApiResponseSchema(apiTokenSchema);
export const checkAuthResponseSchema = createApiResponseSchema(
  z.object({}),
  checkAuthDetailsSchema
);
export const customerResponseSchema = createApiResponseSchema(customerSchema);

// -----------------------------------------------------------------------------
// Type exports
// -----------------------------------------------------------------------------

export type AccountResponse = z.infer<typeof accountResponseSchema>;
export type ApiTokenResponse = z.infer<typeof apiTokenResponseSchema>;
export type CheckAuthResponse = z.infer<typeof checkAuthResponseSchema>;
export type CustomerResponse = z.infer<typeof customerResponseSchema>;
