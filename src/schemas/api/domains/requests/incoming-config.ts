// src/schemas/api/domains/requests/incoming-config.ts
//
// Request schemas for domain incoming configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:extid/incoming-config
// - PUT /api/domains/:extid/incoming-config
// - DELETE /api/domains/:extid/incoming-config
//
// Response schemas are in ../responses/incoming-config.ts

import { z } from 'zod';
import {
  patchIncomingConfigPayloadSchema,
  putIncomingConfigPayloadSchema,
} from '@/schemas/shapes/domains/incoming-config';

// Re-export response schemas for convenience
export {
  getDomainIncomingConfigResponseSchema,
  putDomainIncomingConfigResponseSchema,
  patchDomainIncomingConfigResponseSchema,
  incomingConfigDetailsSchema,
  type GetDomainIncomingConfigResponse,
  type PutDomainIncomingConfigResponse,
  type PatchDomainIncomingConfigResponse,
  type IncomingConfigDetails,
} from '../responses/incoming-config';

// ---------------------------------------------------------------------------
// GET /api/domains/:extid/incoming-config
// ---------------------------------------------------------------------------

/**
 * Request parameters for getting incoming configuration.
 *
 * Path params: domain_id (domain external ID)
 */
export const getDomainIncomingConfigRequestSchema = z.object({
  // Path parameters (typically handled by router, included for completeness)
});

export type GetDomainIncomingConfigRequest = z.infer<typeof getDomainIncomingConfigRequestSchema>;

// ---------------------------------------------------------------------------
// PUT /api/domains/:extid/incoming-config
// ---------------------------------------------------------------------------

/**
 * Request body for PUT (full replacement) of incoming configuration.
 *
 * PUT semantics: the request body IS the new state.
 * - Required fields: enabled
 *
 * Note: Recipients are managed via separate add/remove endpoints.
 */
export const putDomainIncomingConfigRequestSchema = putIncomingConfigPayloadSchema;

export type PutDomainIncomingConfigRequest = z.infer<typeof putDomainIncomingConfigRequestSchema>;

// ---------------------------------------------------------------------------
// PATCH /api/domains/:extid/incoming-config (partial update - future)
// ---------------------------------------------------------------------------

/**
 * Request body for PATCH (partial update) of incoming configuration.
 *
 * PATCH semantics: only provided fields are updated.
 * - All fields are optional (true partial update)
 * - Omitted fields preserve existing values
 *
 * Fields:
 * - enabled: optional boolean
 */
export const patchDomainIncomingConfigRequestSchema = patchIncomingConfigPayloadSchema;

export type PatchDomainIncomingConfigRequest = z.infer<typeof patchDomainIncomingConfigRequestSchema>;
