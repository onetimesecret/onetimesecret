// src/schemas/api/organizations/requests/sso-config.ts
//
// Request/response schemas for SSO configuration API endpoints.
//
// Endpoints:
// - GET /api/organizations/:org_extid/sso
// - PUT /api/organizations/:org_extid/sso (full replacement)
// - PATCH /api/organizations/:org_extid/sso (partial update)
// - DELETE /api/organizations/:org_extid/sso

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import {
  orgSsoConfigSchema,
  createOrUpdateSsoConfigPayloadSchema,
  createOrUpdateSsoConfigPayloadStrictSchema,
  patchSsoConfigPayloadSchema,
  putSsoConfigPayloadStrictSchema,
} from '@/schemas/shapes/organizations/org-sso-config';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/organizations/:org_extid/sso
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
// PUT /api/organizations/:org_extid/sso (full replacement)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request body for PUT (full replacement) of SSO configuration.
 *
 * PUT semantics: the request body IS the new state.
 * - Required fields: provider_type, client_id, client_secret, display_name
 * - Optional fields: tenant_id, issuer, allowed_domains, enabled
 * - Provider-specific validation:
 *   - entra_id requires tenant_id
 *   - oidc requires issuer (valid URL)
 *
 * Uses strict validation for provider-specific requirements.
 */
export const putSsoConfigRequestSchema = putSsoConfigPayloadStrictSchema;

export type PutSsoConfigRequest = z.infer<typeof putSsoConfigRequestSchema>;

/**
 * Response schema for PUT SSO configuration.
 *
 * Returns the replaced SSO config with masked credentials.
 */
export const putSsoConfigResponseSchema = createApiResponseSchema(orgSsoConfigSchema);

export type PutSsoConfigResponse = z.infer<typeof putSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/organizations/:org_extid/sso (partial update)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request body for PATCH (partial update) of SSO configuration.
 *
 * PATCH semantics: only provided fields are updated.
 * - All fields are optional (true partial update)
 * - Omitted fields preserve existing values
 * - client_secret is optional (preserves existing if omitted)
 *
 * Fields:
 * - provider_type: optional enum ('oidc' | 'entra_id' | 'google' | 'github')
 * - client_id: optional string
 * - client_secret: optional string
 * - display_name: optional string
 * - tenant_id: optional string (for Entra ID)
 * - issuer: optional string URL (for OIDC)
 * - allowed_domains: optional array of strings
 * - enabled: optional boolean
 */
export const patchSsoConfigRequestSchema = patchSsoConfigPayloadSchema;

export type PatchSsoConfigRequest = z.infer<typeof patchSsoConfigRequestSchema>;

/**
 * Response schema for PATCH SSO configuration.
 *
 * Returns the updated SSO config with masked credentials.
 */
export const patchSsoConfigResponseSchema = createApiResponseSchema(orgSsoConfigSchema);

export type PatchSsoConfigResponse = z.infer<typeof patchSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Legacy aliases (deprecated, use verb-specific schemas)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @deprecated Use putSsoConfigRequestSchema or patchSsoConfigRequestSchema
 */
export const createOrUpdateSsoConfigRequestSchema = createOrUpdateSsoConfigPayloadSchema;

export type CreateOrUpdateSsoConfigRequest = z.infer<typeof createOrUpdateSsoConfigRequestSchema>;

/**
 * @deprecated Use putSsoConfigRequestSchema
 */
export const createOrUpdateSsoConfigRequestStrictSchema = createOrUpdateSsoConfigPayloadStrictSchema;

export type CreateOrUpdateSsoConfigRequestStrict = z.infer<typeof createOrUpdateSsoConfigRequestStrictSchema>;

/**
 * @deprecated Use putSsoConfigResponseSchema or patchSsoConfigResponseSchema
 */
export const createOrUpdateSsoConfigResponseSchema = createApiResponseSchema(orgSsoConfigSchema);

export type CreateOrUpdateSsoConfigResponse = z.infer<typeof createOrUpdateSsoConfigResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/organizations/:org_extid/sso
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
