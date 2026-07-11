// src/schemas/api/domains/responses/signup-config.ts
//
// Response schemas for domain signup configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/signup-config
// - PUT /api/domains/:domain_extid/signup-config
// - DELETE /api/domains/:domain_extid/signup-config

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import { authOverrideDetailsSchema } from '@/schemas/api/domains/responses/auth-override';
import { customDomainSignupConfigSchema } from '@/schemas/shapes/domains/signup-config';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Signup config response details schema (ADR-024).
 *
 * The shared auth-override resolution details: global capability and the
 * resolver's effective output for this domain.
 */
export const signupConfigDetailsSchema = authOverrideDetailsSchema;

export type SignupConfigDetails = z.infer<typeof signupConfigDetailsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Response schema for GET /api/domains/:domain_extid/signup-config
 *
 * `record` is null when the domain has no signup config — unconfigured is a
 * first-class state (200, not 404) so `details` can carry the inherited
 * global state (ADR-024).
 */
export const getSignupConfigResponseSchema = createApiResponseSchema(
  customDomainSignupConfigSchema.nullable(),
  signupConfigDetailsSchema
);

export type GetSignupConfigResponse = z.infer<typeof getSignupConfigResponseSchema>;

/**
 * Response schema for PUT /api/domains/:domain_extid/signup-config
 */
export const putSignupConfigResponseSchema = createApiResponseSchema(
  customDomainSignupConfigSchema,
  signupConfigDetailsSchema
);

export type PutSignupConfigResponse = z.infer<typeof putSignupConfigResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:domain_extid/signup-config
 *
 * Carries post-delete resolution details (effective == global) so the
 * settings UI can re-render without a refetch.
 */
export const deleteSignupConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
  details: signupConfigDetailsSchema.optional(),
});

export type DeleteSignupConfigResponse = z.infer<typeof deleteSignupConfigResponseSchema>;
