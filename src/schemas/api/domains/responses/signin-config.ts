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
import { customDomainSigninConfigSchema } from '@/schemas/shapes/domains/signin-config';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Signin config response details schema.
 *
 * Optional metadata that may accompany signin config responses.
 */
export const signinConfigDetailsSchema = z.object({
  /** Whether the current user can manage this signin config. */
  can_manage: z.boolean().optional(),
});

export type SigninConfigDetails = z.infer<typeof signinConfigDetailsSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Response schema for GET /api/domains/:domain_extid/signin-config
 */
export const getSigninConfigResponseSchema = createApiResponseSchema(
  customDomainSigninConfigSchema,
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
 */
export const deleteSigninConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteSigninConfigResponse = z.infer<typeof deleteSigninConfigResponseSchema>;
