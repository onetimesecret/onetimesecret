// src/schemas/api/v3/responses/account.ts
//
// V3 JSON wire-format schemas for account and customer endpoints.
// Timestamps use transforms.fromNumber.toDate so that .parse() returns
// Date objects for the frontend while io:"input" still documents them
// as numbers in OpenAPI.

import { createApiResponseSchema } from '@/schemas/api/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas
// ─────────────────────────────────────────────────────────────────────────────

const customerRoles = ['customer', 'colonel', 'recipient', 'user_deleted_self'] as const;

/** Customer record as it appears in JSON responses. */
export const customerRecord = z.object({
  identifier: z.string(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  objid: z.string(),
  extid: z.string(),
  role: z.enum(customerRoles),
  email: z.string(),
  verified: z.boolean(),
  active: z.boolean(),
  contributor: z.boolean().optional(),
  secrets_created: z.coerce.number().default(0),
  secrets_burned: z.coerce.number().default(0),
  secrets_shared: z.coerce.number().default(0),
  emails_sent: z.coerce.number().default(0),
  last_login: transforms.fromNumber.toDateNullable,
  locale: z.string().nullable(),
  notify_on_reveal: z.boolean().default(false),
  feature_flags: z.record(z.string(), z.boolean()).default({}),
});

/** Account record (V2 AccountOwnInfo shape). */
const accountRecord = z.object({
  cust: customerRecord,
  apitoken: z.string().nullable(),
  stripe_customer: z.any().optional(),
  stripe_subscriptions: z.any().optional(),
});

/** API token record. */
const apiTokenRecord = z.object({
  apitoken: z.string(),
});

/** Details for checkAuth / customer responses. */
const checkAuthDetails = z.object({
  authenticated: z.boolean(),
  authorized: z.boolean(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const accountResponseSchema = createApiResponseSchema(accountRecord);
export const apiTokenResponseSchema = createApiResponseSchema(apiTokenRecord);
export const checkAuthResponseSchema = createApiResponseSchema(customerRecord, checkAuthDetails);
export const customerResponseSchema = createApiResponseSchema(customerRecord, checkAuthDetails);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type AccountResponse = z.infer<typeof accountResponseSchema>;
export type ApiTokenResponse = z.infer<typeof apiTokenResponseSchema>;
export type CheckAuthResponse = z.infer<typeof checkAuthResponseSchema>;
export type CustomerResponse = z.infer<typeof customerResponseSchema>;
