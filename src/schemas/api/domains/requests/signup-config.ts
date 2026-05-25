// src/schemas/api/domains/requests/signup-config.ts
//
// Request schemas for domain signup configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/signup-config
// - PUT /api/domains/:domain_extid/signup-config (full replacement)
// - DELETE /api/domains/:domain_extid/signup-config
//
// Response schemas are in ../responses/signup-config.ts

import { z } from 'zod';
import { putSignupConfigPayloadStrictSchema } from '@/schemas/shapes/domains/signup-config';

// Re-export response schemas
export {
  getSignupConfigResponseSchema,
  putSignupConfigResponseSchema,
  deleteSignupConfigResponseSchema,
  signupConfigDetailsSchema,
  type GetSignupConfigResponse,
  type PutSignupConfigResponse,
  type DeleteSignupConfigResponse,
  type SignupConfigDetails,
} from '../responses/signup-config';

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/domains/:domain_extid/signup-config
// ─────────────────────────────────────────────────────────────────────────────

export const getSignupConfigRequestSchema = z.object({});

export type GetSignupConfigRequest = z.infer<typeof getSignupConfigRequestSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT /api/domains/:domain_extid/signup-config (full replacement)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request body for PUT (full replacement) of signup configuration.
 *
 * PUT semantics: the request body IS the new state.
 * - Required: validation_strategy
 * - Conditionally required: allowed_signup_domains (when strategy is
 *   'domain_allowlist')
 * - Optional: enabled (defaults to false)
 */
export const putSignupConfigRequestSchema = putSignupConfigPayloadStrictSchema;

export type PutSignupConfigRequest = z.infer<typeof putSignupConfigRequestSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/domains/:domain_extid/signup-config
// ─────────────────────────────────────────────────────────────────────────────

export const deleteSignupConfigRequestSchema = z.object({});

export type DeleteSignupConfigRequest = z.infer<typeof deleteSignupConfigRequestSchema>;
