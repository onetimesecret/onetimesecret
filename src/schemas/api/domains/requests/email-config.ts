// src/schemas/api/domains/requests/email-config.ts
//
// Request schemas for domain email configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/email-config
// - PUT /api/domains/:domain_extid/email-config (full replacement)
// - PATCH /api/domains/:domain_extid/email-config (partial update)
// - DELETE /api/domains/:domain_extid/email-config
// - POST /api/domains/:domain_extid/email-config/validate
//
// Response schemas are in ../responses/email-config.ts

import { z } from 'zod';
import {
  patchEmailConfigPayloadSchema,
  putEmailConfigPayloadStrictSchema,
} from '@/schemas/shapes/domains/email-config';

// Re-export response schemas
export {
  getEmailConfigResponseSchema,
  putEmailConfigResponseSchema,
  patchEmailConfigResponseSchema,
  deleteEmailConfigResponseSchema,
  validateEmailConfigResponseSchema,
  emailConfigDetailsSchema,
  type GetEmailConfigResponse,
  type PutEmailConfigResponse,
  type PatchEmailConfigResponse,
  type DeleteEmailConfigResponse,
  type ValidateEmailConfigResponse,
  type EmailConfigDetails,
} from '../responses/email-config';

// ---------------------------------------------------------------------------
// GET /api/domains/:domain_extid/email-config
// ---------------------------------------------------------------------------

/**
 * Request parameters for getting email configuration.
 *
 * Path params: domain_extid (domain external ID)
 */
export const getEmailConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type GetEmailConfigRequest = z.infer<typeof getEmailConfigRequestSchema>;

// ---------------------------------------------------------------------------
// PUT /api/domains/:domain_extid/email-config (full replacement)
// ---------------------------------------------------------------------------

/**
 * Request body for PUT (full replacement) of email configuration.
 *
 * PUT semantics: the request body IS the new state.
 * - Required fields: provider, from_address, from_name
 * - Optional fields: reply_to
 * - Provider-specific validation:
 *   - 'inherit' does not require from_address/from_name
 *
 * Uses strict validation for provider-specific requirements.
 */
export const putEmailConfigRequestSchema = putEmailConfigPayloadStrictSchema;

export type PutEmailConfigRequest = z.infer<typeof putEmailConfigRequestSchema>;

// ---------------------------------------------------------------------------
// PATCH /api/domains/:domain_extid/email-config (partial update)
// ---------------------------------------------------------------------------

/**
 * Request body for PATCH (partial update) of email configuration.
 *
 * PATCH semantics: only provided fields are updated.
 * - All fields are optional (true partial update)
 * - Omitted fields preserve existing values
 *
 * Fields:
 * - provider: optional enum ('ses' | 'sendgrid' | 'lettermint' | 'inherit')
 * - from_address: optional string (valid email)
 * - from_name: optional string
 * - reply_to: optional string (valid email or empty string)
 */
export const patchEmailConfigRequestSchema = patchEmailConfigPayloadSchema;

export type PatchEmailConfigRequest = z.infer<typeof patchEmailConfigRequestSchema>;

// ---------------------------------------------------------------------------
// DELETE /api/domains/:domain_extid/email-config
// ---------------------------------------------------------------------------

/**
 * Request parameters for deleting email configuration.
 *
 * Path params: domain_extid (domain external ID)
 */
export const deleteEmailConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type DeleteEmailConfigRequest = z.infer<typeof deleteEmailConfigRequestSchema>;

// ---------------------------------------------------------------------------
// POST /api/domains/:domain_extid/email-config/validate
// ---------------------------------------------------------------------------

/**
 * Request parameters for validating email configuration.
 *
 * Path params: domain_extid (domain external ID)
 * No request body - validates the current stored configuration.
 */
export const validateEmailConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type ValidateEmailConfigRequest = z.infer<typeof validateEmailConfigRequestSchema>;
