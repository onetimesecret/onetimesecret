import { createApiResponseSchema } from '@/schemas/api';
import { customerSchema } from '@/schemas/models/customer/index';
import { transforms } from '@/utils/transforms';
import type Stripe from 'stripe';
import { z } from 'zod';

/**
 * Account schema with Stripe integration
 */
export const accountSchema = z.object({
  cust: customerSchema,
  apitoken: z.string().optional(),
  stripe_customer: z.custom<Stripe.Customer>(),
  stripe_subscriptions: z.array(z.custom<Stripe.Subscription>()),
});

export type Account = z.infer<typeof accountSchema>;

// Response schema
export const accountResponseSchema = createApiResponseSchema(accountSchema, z.object({}));
export type AccountResponse = z.infer<typeof accountResponseSchema>;

/**
 * Schema for CheckAuthData
 * Extends Customer with an optional last_login as number
 */
export const checkAuthDataSchema = customerSchema.extend({
  last_login: transforms.fromString.number.optional(),
});

export type CheckAuthData = z.infer<typeof checkAuthDataSchema>;

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

// API response types
export const apiTokenResponseSchema = createApiResponseSchema(apiTokenSchema, z.object({}));
export type ApiTokenResponse = z.infer<typeof apiTokenResponseSchema>;
