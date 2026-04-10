// src/schemas/api/domains/responses/homepage-config.ts
//
// Response schemas for domain homepage configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:extid/homepage-config
// - PUT /api/domains/:extid/homepage-config
// - DELETE /api/domains/:extid/homepage-config

import { z } from 'zod';
import { homepageConfigCanonical } from '@/schemas/contracts/custom-domain';

// ---------------------------------------------------------------------------
// Envelope-wrapped response schemas
// ---------------------------------------------------------------------------

/**
 * Response schema for GET and PUT /api/domains/:extid/homepage-config
 *
 * Returns `{ user_id, record }` where record matches the homepage config shape.
 * Record is nullable for GET when no config exists yet.
 */
export const homepageConfigResponseSchema = z.object({
  user_id: z.string(),
  record: homepageConfigCanonical.nullable(),
});

export type HomepageConfigResponse = z.infer<typeof homepageConfigResponseSchema>;

/**
 * Response schema for DELETE /api/domains/:extid/homepage-config
 */
export const deleteHomepageConfigResponseSchema = z.object({
  user_id: z.string(),
  deleted: z.literal(true),
  domain_id: z.string(),
});

export type DeleteHomepageConfigResponse = z.infer<typeof deleteHomepageConfigResponseSchema>;
