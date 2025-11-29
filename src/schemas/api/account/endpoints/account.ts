// src/schemas/api/account/endpoints/account.ts

import { customerSchema } from '@/schemas/models/customer';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Account schema with Stripe integration
 */
export const accountSchema = z.object({
  cust: customerSchema,
  apitoken: z.string().nullable(),
});

export type Account = z.infer<typeof accountSchema>;

/**
 * Schema for CheckAuthDetails
 */
export const checkAuthDetailsSchema = z.object({
  authenticated: z.boolean(),
});

export type CheckAuthDetails = z.infer<typeof checkAuthDetailsSchema>;

/**
 * API token schema
 *
 * API Token response has only two fields - apitoken and
 * active (and not the full record created/updated/identifier).
 */
export const apiTokenSchema = z.object({
  apitoken: z.string(),
  active: transforms.fromString.boolean,
});

export type ApiToken = z.infer<typeof apiTokenSchema>;
