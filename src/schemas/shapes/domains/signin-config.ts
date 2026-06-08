// src/schemas/shapes/domains/signin-config.ts
//
// CustomDomain::SigninConfig shapes with runtime transforms.
// Derives from contracts, adding timestamp transforms.
//
// Architecture: contract -> shape -> API

import {
  customDomainSigninConfigCanonical,
  signinRestrictToSchema,
} from '@/schemas/contracts/custom-domain/signin-config';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export contracts for type access
export * from '@/schemas/contracts/custom-domain/signin-config';

// ─────────────────────────────────────────────────────────────────────────────
// Timestamp transforms
// ─────────────────────────────────────────────────────────────────────────────

const timestampOverrides = {
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
};

// ─────────────────────────────────────────────────────────────────────────────
// CustomDomain::SigninConfig schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * CustomDomain::SigninConfig schema with transforms.
 *
 * Derives from customDomainSigninConfigCanonical contract, applies:
 * - Timestamps: number (Unix epoch seconds) -> Date
 */
export const customDomainSigninConfigSchema = customDomainSigninConfigCanonical.extend({
  ...timestampOverrides,
});

export type CustomDomainSigninConfig = z.infer<typeof customDomainSigninConfigSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Summary schema (for list views)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * CustomDomain::SigninConfig summary schema for list views.
 */
export const customDomainSigninConfigSummarySchema = z.object({
  domain_id: z.string(),
  enabled: z.boolean(),
  signin_enabled: z.boolean(),
  restrict_to: signinRestrictToSchema.nullable(),
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
});

export type CustomDomainSigninConfigSummary = z.infer<typeof customDomainSigninConfigSummarySchema>;
