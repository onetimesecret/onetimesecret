// src/schemas/api/organizations/requests/sso-config.ts
//
// Request/response schemas for SSO configuration API endpoints.
//
// Endpoints:
// - GET /api/organizations/:org_extid/sso-config
// - PUT /api/organizations/:org_extid/sso-config
// - DELETE /api/organizations/:org_extid/sso-config

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import {
  orgSsoConfigSchema,
  createOrUpdateSsoConfigPayloadSchema,
  createOrUpdateSsoConfigPayloadStrictSchema,
} from '@/schemas/shapes/organizations/org-sso-config';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/organizations/:org_extid/sso-config
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request parameters for getting SSO configuration.
 *
 * Path params: org_extid (organization external ID)
 */
export const getSsoConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type GetSsoConfigRequest = z.infer<typeof getSsoConfigRequestSchema>;

/**
 * Response schema for getting SSO configuration.
 *
 * Returns the full SSO config with masked credentials.
 */
export const getSsoConfigResponseSchema = createApiResponseSchema(orgSsoConfigSchema);

export type GetSsoConfigResponse = z.infer<typeof getSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/organizations/:org_extid/sso-config
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request body for creating or updating SSO configuration.
 *
 * Uses the base payload schema for form binding.
 * For strict validation (provider-specific requirements), use
 * createOrUpdateSsoConfigRequestStrictSchema.
 */
export const createOrUpdateSsoConfigRequestSchema = createOrUpdateSsoConfigPayloadSchema;

export type CreateOrUpdateSsoConfigRequest = z.infer<typeof createOrUpdateSsoConfigRequestSchema>;

/**
 * Request body with strict provider-specific validation.
 *
 * Enforces:
 * - tenant_id required for entra_id provider
 * - issuer required for oidc provider
 */
export const createOrUpdateSsoConfigRequestStrictSchema = createOrUpdateSsoConfigPayloadStrictSchema;

export type CreateOrUpdateSsoConfigRequestStrict = z.infer<typeof createOrUpdateSsoConfigRequestStrictSchema>;

/**
 * Response schema for creating/updating SSO configuration.
 *
 * Returns the updated SSO config with masked credentials.
 */
export const createOrUpdateSsoConfigResponseSchema = createApiResponseSchema(orgSsoConfigSchema);

export type CreateOrUpdateSsoConfigResponse = z.infer<typeof createOrUpdateSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/organizations/:org_extid/sso-config
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request parameters for deleting SSO configuration.
 *
 * Path params: org_extid (organization external ID)
 */
export const deleteSsoConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type DeleteSsoConfigRequest = z.infer<typeof deleteSsoConfigRequestSchema>;

/**
 * Response schema for deleting SSO configuration.
 *
 * Returns a success confirmation with optional details.
 */
export const deleteSsoConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteSsoConfigResponse = z.infer<typeof deleteSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Details schema for responses
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
