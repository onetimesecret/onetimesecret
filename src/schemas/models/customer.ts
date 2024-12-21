import { createRecordResponseSchema } from '@/schemas/api/base';
import { baseModelSchema, optional } from '@/schemas/models/base';
import { transforms } from '@/utils/transforms';
import { z } from 'zod';

import { FeatureFlags } from './customer/feature_flags';

/**
 * @fileoverview Customer schema with simplified type boundaries
 *
 * Key improvements:
 * 1. Unified transformation layer using base transforms
 * 2. Clearer type flow from API to frontend
 * 3. Simplified schema structure
 */

// Role enum matching Ruby model
export const CustomerRole = {
  CUSTOMER: 'customer',
  COLONEL: 'colonel',
  RECIPIENT: 'recipient',
  USER_DELETED_SELF: 'user_deleted_self',
} as const;

/**
 * Plan options schema matching Ruby model
 */
export const planOptionsSchema = z.object({
  ttl: transforms.fromString.number,
  size: transforms.fromString.number,
  api: transforms.fromString.boolean,
  name: z.string(),
  email: optional(transforms.fromString.boolean),
  custom_domains: optional(transforms.fromString.boolean),
  dark_mode: optional(transforms.fromString.boolean),
  cname: optional(transforms.fromString.boolean),
  private: optional(transforms.fromString.boolean),
});

export type PlanOptions = z.infer<typeof planOptionsSchema>;

/**
 * Plan schema for customer plans
 */
export const planSchema = baseModelSchema.extend({
  planid: z.string(),
  price: transforms.fromString.number,
  discount: transforms.fromString.number,
  options: planOptionsSchema,
});

export type Plan = z.infer<typeof planSchema>;

/**
 * Customer schema with unified transformations
 */
export const customerSchema = baseModelSchema.extend({
    // Core fields
    custid: z.string(),
    role: z.enum([
      CustomerRole.CUSTOMER,
      CustomerRole.COLONEL,
      CustomerRole.RECIPIENT,
      CustomerRole.USER_DELETED_SELF,
    ]),

    // Boolean fields from API
    verified: transforms.fromString.boolean,
    active: transforms.fromString.boolean,
    contributor: optional(transforms.fromString.boolean),

    // Counter fields from API with default values
    secrets_created: z.preprocess(
      (val) => Number(val) || 0,
      z.number()
    ),
    secrets_burned: z.preprocess(
      (val) => Number(val) || 0,
      z.number()
    ),
    secrets_shared: z.preprocess(
      (val) => Number(val) || 0,
      z.number()
    ),
    emails_sent: z.preprocess(
      (val) => Number(val) || 0,
      z.number()
    ),

    // Date fields
    last_login: transforms.fromString.date,

    // Optional fields
    locale: z.string().optional(),
    planid: z.string().optional(),

    // Plan data
    plan: planSchema,

    // Stripe-related fields
    stripe_customer_id: z.string().optional(),
    stripe_subscription_id: z.string().optional(),
    stripe_checkout_email: z.string().optional(),

    // Feature flags can have mixed types
    feature_flags: z
      .record(z.union([z.boolean(), z.number(), z.string()]))
      .transform((val): FeatureFlags => val as FeatureFlags)
      .default({}),  // allows for customer objects that don't have the field yet
  })
  .passthrough();

// Update the type to explicitly use Date for timestamps
export type Customer = Omit<z.infer<typeof customerSchema>, 'created' | 'updated'> & {
  created: Date;
  updated: Date;
};

/**
 * Schema for CheckAuthData
 * Extends Customer with an optional last_login as number
 */
//export const checkAuthDataSchema = customerSchema.extend({
//  last_login: optional(transforms.fromString.number),
//});

export type CheckAuthData = z.infer<typeof checkAuthDataSchema>;

/**
 * Schema for CheckAuthDetails
 */
//export const checkAuthDetailsSchema = z.object({
//  authenticated: z.boolean(),
//});

export type CheckAuthDetails = z.infer<typeof checkAuthDetailsSchema>;

/**
 * API token schema
 *
 * API Token response has only two fields - apitoken and
 * active (and not the full record created/updated/identifier).
 *
 */
export const apiTokenSchema = z.object({
  apitoken: z.string(),
  active: transforms.fromString.boolean,
});

export type ApiToken = z.infer<typeof apiTokenSchema>;

// API response types
export const customerResponseSchema = createRecordResponseSchema(customerSchema);
export const apiTokenResponseSchema = createRecordResponseSchema(apiTokenSchema);
export type CustomerResponse = z.infer<typeof customerResponseSchema>;
export type ApiTokenResponse = z.infer<typeof apiTokenResponseSchema>;
