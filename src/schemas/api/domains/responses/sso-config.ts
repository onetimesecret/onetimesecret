// src/schemas/api/domains/responses/sso-config.ts
//
// Response schemas for domain SSO configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/sso
// - PUT /api/domains/:domain_extid/sso
// - PATCH /api/domains/:domain_extid/sso
// - DELETE /api/domains/:domain_extid/sso

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import { domainSsoConfigSchema } from '@/schemas/shapes/sso-config';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * SSO config response details schema.
 *
 * Optional metadata that may accompany SSO config responses.
 */
export const ssoConfigDetailsSchema = z.object({
  /** Whether the current user can manage this SSO config. */
  can_manage: z.boolean().optional(),
  /** Whether the SSO config has been tested/validated. */
  is_validated: z.boolean().optional(),
  /** Last successful SSO authentication timestamp. */
  last_auth_at: z.number().nullable().optional(),
});

export type SsoConfigDetails = z.infer<typeof ssoConfigDetailsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Response schema for GET /api/domains/:domain_extid/sso
 *
 * Returns the full SSO config with masked credentials.
 */
export const getSsoConfigResponseSchema = createApiResponseSchema(
  domainSsoConfigSchema,
  ssoConfigDetailsSchema
);

export type GetSsoConfigResponse = z.infer<typeof getSsoConfigResponseSchema>;

/**
 * Response schema for PUT /api/domains/:domain_extid/sso
 *
 * Returns the replaced SSO config with masked credentials.
 */
export const putSsoConfigResponseSchema = createApiResponseSchema(
  domainSsoConfigSchema,
  ssoConfigDetailsSchema
);

export type PutSsoConfigResponse = z.infer<typeof putSsoConfigResponseSchema>;

/**
 * Response schema for PATCH /api/domains/:domain_extid/sso
 *
 * Returns the updated SSO config with masked credentials.
 */
export const patchSsoConfigResponseSchema = createApiResponseSchema(
  domainSsoConfigSchema,
  ssoConfigDetailsSchema
);

export type PatchSsoConfigResponse = z.infer<typeof patchSsoConfigResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:domain_extid/sso
 *
 * Returns a success confirmation with optional details.
 */
export const deleteSsoConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteSsoConfigResponse = z.infer<typeof deleteSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Legacy aliases (deprecated)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @deprecated Use putSsoConfigResponseSchema or patchSsoConfigResponseSchema
 */
export const createOrUpdateSsoConfigResponseSchema = putSsoConfigResponseSchema;

export type CreateOrUpdateSsoConfigResponse = z.infer<typeof createOrUpdateSsoConfigResponseSchema>;
