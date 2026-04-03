// src/schemas/api/domains/responses/incoming-config.ts
//
// Response schemas for domain incoming configuration API endpoints.
//
// Endpoints:
// - GET /api/v2/domains/:domain_id/incoming
// - PUT /api/v2/domains/:domain_id/incoming
// - PATCH /api/v2/domains/:domain_id/incoming

import { z } from 'zod';
import { createApiResponseSchema } from '@/schemas/api/base';
import { customDomainIncomingConfigSchema } from '@/schemas/shapes/domains/incoming-config';

// ---------------------------------------------------------------------------
// Response-specific details schema
// ---------------------------------------------------------------------------

/**
 * Incoming config response details schema.
 *
 * Optional metadata that may accompany incoming config responses.
 */
export const incomingConfigDetailsSchema = z.object({
  /** Whether the current user can manage this incoming config. */
  can_manage: z.boolean().optional(),
  /** Whether incoming secrets feature is available for this domain. */
  feature_available: z.boolean().optional(),
});

export type IncomingConfigDetails = z.infer<typeof incomingConfigDetailsSchema>;

// ---------------------------------------------------------------------------
// Envelope-wrapped response schemas
// ---------------------------------------------------------------------------

/**
 * Response schema for GET /api/v2/domains/:domain_id/incoming
 *
 * Returns the full incoming config for a domain.
 */
export const getDomainIncomingConfigResponseSchema = createApiResponseSchema(
  customDomainIncomingConfigSchema,
  incomingConfigDetailsSchema
);

export type GetDomainIncomingConfigResponse = z.infer<typeof getDomainIncomingConfigResponseSchema>;

/**
 * Response schema for PUT /api/v2/domains/:domain_id/incoming
 *
 * Returns the replaced incoming config.
 */
export const putDomainIncomingConfigResponseSchema = createApiResponseSchema(
  customDomainIncomingConfigSchema,
  incomingConfigDetailsSchema
);

export type PutDomainIncomingConfigResponse = z.infer<typeof putDomainIncomingConfigResponseSchema>;

/**
 * Response schema for PATCH /api/v2/domains/:domain_id/incoming
 *
 * Returns the updated incoming config.
 */
export const patchDomainIncomingConfigResponseSchema = createApiResponseSchema(
  customDomainIncomingConfigSchema,
  incomingConfigDetailsSchema
);

export type PatchDomainIncomingConfigResponse = z.infer<typeof patchDomainIncomingConfigResponseSchema>;
