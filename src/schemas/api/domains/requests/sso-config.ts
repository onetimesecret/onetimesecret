// src/schemas/api/domains/requests/sso-config.ts
//
// Request schemas for domain SSO configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/sso
// - PUT /api/domains/:domain_extid/sso (full replacement)
// - PATCH /api/domains/:domain_extid/sso (partial update)
// - DELETE /api/domains/:domain_extid/sso
// - POST /api/domains/:domain_extid/sso/test
//
// Response schemas are in ../responses/sso-config.ts

import { z } from 'zod';
import {
  patchSsoConfigPayloadSchema,
  putSsoConfigPayloadStrictSchema,
} from '@/schemas/shapes/sso-config';

// Re-export response schemas
export {
  getSsoConfigResponseSchema,
  putSsoConfigResponseSchema,
  patchSsoConfigResponseSchema,
  deleteSsoConfigResponseSchema,
  ssoConfigDetailsSchema,
  type GetSsoConfigResponse,
  type PutSsoConfigResponse,
  type PatchSsoConfigResponse,
  type DeleteSsoConfigResponse,
  type SsoConfigDetails,
} from '../responses/sso-config';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/domains/:domain_extid/sso
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request parameters for getting SSO configuration.
 *
 * Path params: domain_extid (domain external ID)
 */
export const getSsoConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type GetSsoConfigRequest = z.infer<typeof getSsoConfigRequestSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/domains/:domain_extid/sso (full replacement)
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

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/domains/:domain_extid/sso (partial update)
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

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/domains/:domain_extid/sso
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request parameters for deleting SSO configuration.
 *
 * Path params: domain_extid (domain external ID)
 */
export const deleteSsoConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type DeleteSsoConfigRequest = z.infer<typeof deleteSsoConfigRequestSchema>;
