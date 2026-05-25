// src/schemas/shapes/domains/signup-config.ts
//
// CustomDomain::SignupConfig shapes with runtime transforms.
// Derives from contracts, adding timestamp transforms and null normalization.
//
// Architecture: contract → shape → API

import {
  customDomainSignupConfigCanonical,
  signupValidationStrategySchema,
} from '@/schemas/contracts/custom-domain/signup-config';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// Re-export contracts for type access
export * from '@/schemas/contracts/custom-domain/signup-config';

// ─────────────────────────────────────────────────────────────────────────────
// Timestamp transforms
// ─────────────────────────────────────────────────────────────────────────────

const timestampOverrides = {
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
};

// ─────────────────────────────────────────────────────────────────────────────
// CustomDomain::SignupConfig schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * CustomDomain::SignupConfig schema with transforms.
 *
 * Derives from customDomainSignupConfigCanonical contract, applies:
 * - Timestamps: number (Unix epoch seconds) → Date
 * - Array normalization: null → empty array (allowed_signup_domains)
 */
export const customDomainSignupConfigSchema = customDomainSignupConfigCanonical.extend({
  ...timestampOverrides,

  // Array normalization: null → empty array
  allowed_signup_domains: z.array(z.string()).nullish().transform((v) => v ?? []),
});

export type CustomDomainSignupConfig = z.infer<typeof customDomainSignupConfigSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Summary schema (for list views)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * CustomDomain::SignupConfig summary schema for list views.
 */
export const customDomainSignupConfigSummarySchema = z.object({
  domain_id: z.string(),
  validation_strategy: signupValidationStrategySchema,
  enabled: z.boolean(),
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
});

export type CustomDomainSignupConfigSummary = z.infer<typeof customDomainSignupConfigSummarySchema>;
