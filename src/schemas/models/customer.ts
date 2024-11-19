// src/schemas/models/customer.ts
import { baseApiRecordSchema } from '@/schemas/base';
import type { } from '@/types/api/responses';
import { booleanFromString, numberFromString } from '@/utils/transforms';
import { z } from 'zod';

/**
 * @fileoverview Customer schema for API transformation boundaries
 *
 * Key Design Decisions:
 * 1. Input schemas handle API -> App transformation
 * 2. App uses single shared type between stores/components
 * 3. No explicit output schemas - serialize when needed
 *
 * Type Flow:
 * API Response (strings) -> InputSchema -> Store/Components -> API Request
 *                          ^                                ^
 *                          |                                |
 *                       transform                       serialize
 *
 * Validation Rules:
 * - Boolean fields come as strings from Ruby/Redis ('true'/'false')
 * - Numeric counters come as strings from API
 * - Dates come as UTC seconds strings
 * - Role is validated against enum
 * - Optional fields explicitly marked
 */


// Role enum matching Ruby model
export const CustomerRole = {
  CUSTOMER: 'customer',
  COLONEL: 'colonel',
  RECIPIENT: 'recipient',
  USER_DELETED_SELF: 'user_deleted_self'
} as const

/**
 * Plan options schema matching Ruby model
 */
export const planOptionsSchema = z.object({
  ttl: z.number(),
  size: z.number(),
  api: z.boolean(),
  name: z.string(),
  email: z.boolean().optional(),
  custom_domains: z.boolean().optional(),
  dark_mode: z.boolean().optional(),
  cname: z.boolean().optional(),
  private: z.boolean().optional()
})

export type PlanOptions = z.infer<typeof planOptionsSchema>

/**
 * Plan schema for customer plans
 */
export const planSchema = baseApiRecordSchema.extend({
  planid: z.string(),
  price: z.number(),
  discount: z.number(),
  options: planOptionsSchema
})

export type Plan = z.infer<typeof planSchema>

/**
 * Input schema for customer from API
 * - Handles string -> boolean/number/date coercion from Ruby/Redis
 * - Validates role against enum
 * - Allows extra fields from API (passthrough)
 */
export const customerInputSchema = baseApiRecordSchema.extend({
  // Core fields
  custid: z.string(),
  role: z.enum([
    CustomerRole.CUSTOMER,
    CustomerRole.COLONEL,
    CustomerRole.RECIPIENT,
    CustomerRole.USER_DELETED_SELF
  ]),

  // Boolean fields that come as strings from API
  verified: booleanFromString,
  active: booleanFromString,
  contributor: booleanFromString.optional(),

  // Counter fields that come as strings from API
  secrets_created: numberFromString.default(0),
  secrets_burned: numberFromString.default(0),
  secrets_shared: numberFromString.default(0),
  emails_sent: numberFromString.default(0),

  // Date fields (UTC seconds from API)
  last_login: z.string().transform(val => new Date(Number(val) * 1000)),

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
  feature_flags: z.record(z.union([
    z.boolean(),
    z.number(),
    z.string()
  ])).optional()
}).passthrough()

// Update the type to explicitly use Date for timestamps
export type Customer = Omit<z.infer<typeof customerInputSchema>, 'created' | 'updated'> & {
  created: Date;
  updated: Date;
}

/**
 * Schema for CheckAuthData
 * Extends Customer with an optional last_login as number
 */
export const checkAuthDataSchema = customerInputSchema.extend({
  last_login: z.number().optional()
})

export type CheckAuthData = z.infer<typeof checkAuthDataSchema>

/**
 * Schema for CheckAuthDetails
 */
export const checkAuthDetailsSchema = z.object({
  authenticated: z.boolean()
})

export type CheckAuthDetails = z.infer<typeof checkAuthDetailsSchema>

// ApiToken schema using baseApiRecordSchema
export const apiTokenSchema = baseApiRecordSchema.extend({
  apitoken: z.string(),
  active: booleanFromString
});

export type ApiToken = z.infer<typeof apiTokenSchema>;

// Account schema
export const accountSchema = baseApiRecordSchema.extend({
  cust: customerInputSchema,
  apitoken: z.string().optional(),
  stripe_customer: z.object({
    // Define Stripe.Customer schema fields
    // You'll want to replace this with actual Stripe customer schema
    id: z.string(),
    email: z.string().optional()
  }),
  stripe_subscriptions: z.array(z.object({
    // Define Stripe.Subscription schema fields
    // Replace with actual Stripe subscription schema details
    id: z.string(),
    status: z.string()
  }))
});

export type Account = z.infer<typeof accountSchema>;
