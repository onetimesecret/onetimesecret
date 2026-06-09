// src/schemas/api/domains/requests/signin-config.ts
//
// Request schemas for domain signin configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/signin-config
// - PUT /api/domains/:domain_extid/signin-config (full replacement)
// - DELETE /api/domains/:domain_extid/signin-config
//
// Response schemas are in ../responses/signin-config.ts

import { z } from 'zod';
import { putSigninConfigPayloadSchema } from '@/schemas/contracts/custom-domain/signin-config';

// Re-export response schemas
export {
  getSigninConfigResponseSchema,
  putSigninConfigResponseSchema,
  deleteSigninConfigResponseSchema,
  signinConfigDetailsSchema,
  type GetSigninConfigResponse,
  type PutSigninConfigResponse,
  type DeleteSigninConfigResponse,
  type SigninConfigDetails,
} from '../responses/signin-config';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/domains/:domain_extid/signin-config
// ─────────────────────────────────────────────────────────────────────────────

export const getSigninConfigRequestSchema = z.object({});

export type GetSigninConfigRequest = z.infer<typeof getSigninConfigRequestSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/domains/:domain_extid/signin-config (full replacement)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request body for PUT (full replacement) of signin configuration.
 *
 * PUT semantics: the request body IS the new state.
 * - Optional: enabled (defaults to false)
 * - Optional: signin_enabled, restrict_to, email_auth_enabled, sso_enabled
 *   (null = inherit global default)
 */
export const putSigninConfigRequestSchema = putSigninConfigPayloadSchema;

export type PutSigninConfigRequest = z.infer<typeof putSigninConfigRequestSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/domains/:domain_extid/signin-config
// ─────────────────────────────────────────────────────────────────────────────

export const deleteSigninConfigRequestSchema = z.object({});

export type DeleteSigninConfigRequest = z.infer<typeof deleteSigninConfigRequestSchema>;
