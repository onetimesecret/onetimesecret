// src/schemas/api/v2/responses/account.ts
//
// Response schemas for account-related endpoints.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  accountSchema,
  apiTokenSchema,
  checkAuthDetailsSchema,
} from '@/schemas/api/account/endpoints/account';
import { customerSchema } from '@/schemas/models';
import { z } from 'zod';

export const accountResponseSchema = createApiResponseSchema(accountSchema);
export const apiTokenResponseSchema = createApiResponseSchema(apiTokenSchema);
export const checkAuthResponseSchema = createApiResponseSchema(customerSchema, checkAuthDetailsSchema);
export const customerResponseSchema = createApiResponseSchema(customerSchema, checkAuthDetailsSchema);

export type AccountResponse = z.infer<typeof accountResponseSchema>;
export type ApiTokenResponse = z.infer<typeof apiTokenResponseSchema>;
export type CheckAuthResponse = z.infer<typeof checkAuthResponseSchema>;
export type CustomerResponse = z.infer<typeof customerResponseSchema>;
