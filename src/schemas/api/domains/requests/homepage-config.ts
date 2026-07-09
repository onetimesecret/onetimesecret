// src/schemas/api/domains/requests/homepage-config.ts
//
// Request schemas for domain homepage configuration API endpoints.
//
// Endpoints:
// - GET /api/domains/:extid/homepage-config
// - PUT /api/domains/:extid/homepage-config
// - DELETE /api/domains/:extid/homepage-config
//
// Response schemas are in ../responses/homepage-config.ts

import { z } from 'zod';
import { homepageSecretsModeSchema } from '@/schemas/contracts/custom-domain/homepage-config';

// ---------------------------------------------------------------------------
// PUT /api/domains/:extid/homepage-config
// ---------------------------------------------------------------------------

/**
 * Request body for PUT of homepage configuration.
 *
 * Merge/PATCH-style semantics on the backend: an omitted field leaves the
 * stored value unchanged. `enabled` is the only field the workspace UI
 * always sends; `secrets_mode` is sent only when the operator changes which
 * experience the homepage presents ('create' | 'incoming'). Setting
 * 'incoming' is rejected server-side unless the domain's incoming config is
 * ready (enabled with at least one recipient) and the org is entitled.
 */
export const putHomepageConfigRequestSchema = z.object({
  enabled: z.boolean(),
  secrets_mode: homepageSecretsModeSchema.optional(),
});

export type PutHomepageConfigRequest = z.infer<typeof putHomepageConfigRequestSchema>;
