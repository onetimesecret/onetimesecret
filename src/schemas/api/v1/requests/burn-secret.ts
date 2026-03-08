// src/schemas/api/v1/requests/burn-secret.ts
//
// Request schema for V1::Controllers::Index#burn_secret
// POST /receipt/:key/burn
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const burnSecretRequestSchema = z.object({
  /** Set to "true" to confirm burn */
  continue: z.string().optional(),
});

export type BurnSecretRequest = z.infer<typeof burnSecretRequestSchema>;
