// src/schemas/api/domains/responses/email-config.ts
//
// Response schemas for domain email configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:domain_extid/email-config
// - PUT /api/domains/:domain_extid/email-config
// - PATCH /api/domains/:domain_extid/email-config
// - DELETE /api/domains/:domain_extid/email-config
// - POST /api/domains/:domain_extid/email-config/validate

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import { customDomainEmailConfigSchema } from '@/schemas/shapes/domains/email-config';

// ---------------------------------------------------------------------------
// Response-specific details schema
// ---------------------------------------------------------------------------

/**
 * Email config response details schema.
 *
 * Optional metadata that may accompany email config responses.
 */
export const emailConfigDetailsSchema = z.object({
  /** Whether the current user can manage this email config. */
  can_manage: z.boolean().optional(),
  /** Whether the email config has been validated. */
  is_validated: z.boolean().optional(),
  /** Number of DNS records still pending verification. */
  pending_dns_count: z.number().optional(),
});

export type EmailConfigDetails = z.infer<typeof emailConfigDetailsSchema>;

// ---------------------------------------------------------------------------
// Envelope-wrapped response schemas
// ---------------------------------------------------------------------------

/**
 * Response schema for GET /api/domains/:domain_extid/email-config
 *
 * Returns the full email config with provider details.
 */
export const getEmailConfigResponseSchema = createApiResponseSchema(
  customDomainEmailConfigSchema,
  emailConfigDetailsSchema
);

export type GetEmailConfigResponse = z.infer<typeof getEmailConfigResponseSchema>;

/**
 * Response schema for PUT /api/domains/:domain_extid/email-config
 *
 * Returns the replaced email config.
 */
export const putEmailConfigResponseSchema = createApiResponseSchema(
  customDomainEmailConfigSchema,
  emailConfigDetailsSchema
);

export type PutEmailConfigResponse = z.infer<typeof putEmailConfigResponseSchema>;

/**
 * Response schema for PATCH /api/domains/:domain_extid/email-config
 *
 * Returns the updated email config.
 */
export const patchEmailConfigResponseSchema = createApiResponseSchema(
  customDomainEmailConfigSchema,
  emailConfigDetailsSchema
);

export type PatchEmailConfigResponse = z.infer<typeof patchEmailConfigResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:domain_extid/email-config
 *
 * Returns a success confirmation with optional details.
 */
export const deleteEmailConfigResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteEmailConfigResponse = z.infer<typeof deleteEmailConfigResponseSchema>;

// ---------------------------------------------------------------------------
// Validate response schema
// ---------------------------------------------------------------------------

/**
 * Response schema for POST /api/domains/:domain_extid/email-config/validate
 *
 * Returns validation results including DNS record status updates.
 */
export const validateEmailConfigResponseSchema = createApiResponseSchema(
  customDomainEmailConfigSchema,
  emailConfigDetailsSchema.extend({
    /** Human-readable validation result message. */
    validation_message: z.string().optional(),
  })
);

export type ValidateEmailConfigResponse = z.infer<typeof validateEmailConfigResponseSchema>;
