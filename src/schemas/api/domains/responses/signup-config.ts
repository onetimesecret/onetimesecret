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
import { customDomainSignupConfigSchema } from '@/schemas/shapes/domains/signup-config';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Signup config response details schema.
 *
 * Optional metadata that may accompany signup config responses.
 */
export const signupConfigDetailsSchema = z.object({
  /** Whether the current user can manage this signup config. */
  can_manage: z.boolean().optional(),
});

export type SignupConfigDetails = z.infer<typeof signupConfigDetailsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Response schema for GET /api/domains/:domain_extid/signup-config
 */
export const getSignupConfigResponseSchema = createApiResponseSchema(
  customDomainSignupConfigSchema,
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
 */
export const deleteSignupConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteSignupConfigResponse = z.infer<typeof deleteSignupConfigResponseSchema>;
