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
 * Admin homepage-config record: the stored config plus the server-computed
 * `effective_enabled`, which is the `enabled` the bootstrap would give the
 * CALLER: the stored flag after the serializer's downgrade rule (an
 * incoming-mode homepage whose incoming config is unavailable fails closed
 * to the trust card), narrowed by the network rules (`allowed_cidrs` /
 * `denied_cidrs`) judged against the caller's own request. The frontend
 * mirrors this into bootstrapStore instead of re-deriving readiness from
 * possibly-stale client state. Other visitors can get a different answer.
 */
export const homepageConfigAdminRecordSchema = homepageConfigCanonical.extend({
  effective_enabled: z.boolean().optional(),
});

export type HomepageConfigAdminRecord = z.infer<typeof homepageConfigAdminRecordSchema>;

/**
 * Response schema for GET and PUT /api/domains/:extid/homepage-config
 *
 * Returns `{ user_id, record }` where record matches the homepage config shape.
 * Record is nullable for GET when no config exists yet.
 */
export const homepageConfigResponseSchema = z.object({
  user_id: z.string(),
  record: homepageConfigAdminRecordSchema.nullable(),
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
