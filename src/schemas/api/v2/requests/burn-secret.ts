// src/schemas/api/v2/requests/burn-secret.ts
//
// Request schema for V2::Logic::Secrets::BurnSecret
// POST /receipt/:identifier/burn
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// Identifier is in path param, not body.

import { z } from 'zod';

export const burnSecretRequestSchema = z.object({
  /** Set to "true" to confirm burn */
  continue: z.string().optional(),
});

export type BurnSecretRequest = z.infer<typeof burnSecretRequestSchema>;
