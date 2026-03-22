// src/schemas/api/v3/responses/account.ts
//
// V3 API response schemas for account and customer endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiResponseSchema } from '@/schemas/api/base';
import { customerRecord } from '@/schemas/shapes/v3/customer';
import { z } from 'zod';

// Re-export customerRecord for consumers that import from responses
export { customerRecord };

// ─────────────────────────────────────────────────────────────────────────────
// Account-specific composite records (not standalone entities)
// ─────────────────────────────────────────────────────────────────────────────

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
