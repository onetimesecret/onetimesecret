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
import { putIncomingConfigPayloadSchema } from '@/schemas/shapes/domains/incoming-config';

// Re-export response schemas for convenience
export {
  getDomainIncomingConfigResponseSchema,
  putDomainIncomingConfigResponseSchema,
  incomingConfigDetailsSchema,
  type GetDomainIncomingConfigResponse,
  type PutDomainIncomingConfigResponse,
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
 * Request body for PUT of incoming configuration.
 *
 * Carries the full intended state — enabled flag + the complete
 * recipients list (plaintext, admin view). PUT semantics: the body
 * IS the new state.
 */
export const putDomainIncomingConfigRequestSchema = putIncomingConfigPayloadSchema;

export type PutDomainIncomingConfigRequest = z.infer<typeof putDomainIncomingConfigRequestSchema>;
