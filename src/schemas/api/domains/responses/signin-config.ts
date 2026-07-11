// src/schemas/api/domains/responses/signin-config.ts
//
// Response schemas for domain signin configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/signin-config
// - PUT /api/domains/:domain_extid/signin-config
// - DELETE /api/domains/:domain_extid/signin-config

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import { authOverrideDetailsSchema } from '@/schemas/api/domains/responses/auth-override';
import {
  customDomainSigninConfigSchema,
  signinRestrictToSchema,
} from '@/schemas/shapes/domains/signin-config';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Signin config response details schema (ADR-024).
 *
 * Shared auth-override resolution details plus the install-level method
 * restriction, so the settings UI can render the inherited mode while the
 * domain is unconfigured.
 */
export const signinConfigDetailsSchema = authOverrideDetailsSchema.extend({
  /**
   * Install-level restrict_to. Resilient parse: an unrecognized value
   * degrades to null (show all methods) instead of failing the response.
   */
  global_restrict_to: signinRestrictToSchema.nullable().catch(null).optional(),
});

export type SigninConfigDetails = z.infer<typeof signinConfigDetailsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Response schema for GET /api/domains/:domain_extid/signin-config
 *
 * `record` is null when the domain has no signin config — unconfigured is a
 * first-class state (200, not 404) so `details` can carry the inherited
 * global state (ADR-024).
 */
export const getSigninConfigResponseSchema = createApiResponseSchema(
  customDomainSigninConfigSchema.nullable(),
  signinConfigDetailsSchema
);

export type GetSigninConfigResponse = z.infer<typeof getSigninConfigResponseSchema>;

/**
 * Response schema for PUT /api/domains/:domain_extid/signin-config
 */
export const putSigninConfigResponseSchema = createApiResponseSchema(
  customDomainSigninConfigSchema,
  signinConfigDetailsSchema
);

export type PutSigninConfigResponse = z.infer<typeof putSigninConfigResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:domain_extid/signin-config
 *
 * Carries post-delete resolution details (effective == global) so the
 * settings UI can re-render without a refetch.
 */
export const deleteSigninConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
  details: signinConfigDetailsSchema.optional(),
});

export type DeleteSigninConfigResponse = z.infer<typeof deleteSigninConfigResponseSchema>;
