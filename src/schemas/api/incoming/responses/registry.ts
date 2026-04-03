// src/schemas/api/incoming/responses/registry.ts
//
// Response schema registry for the Incoming API.
// Separated from index.ts barrel for OpenAPI generator imports.

import { incomingConfigResponseSchema } from './config';
import { incomingSecretResponseSchema } from './incoming-secret';
import { validateRecipientResponseSchema } from './validate-recipient';

/**
 * Keyed lookup of Incoming API response schemas.
 * Used by the OpenAPI generator for runtime Zod parsing.
 */
export const responseSchemas = {
  // Config
  getConfig: incomingConfigResponseSchema,

  // Secrets
  createIncomingSecret: incomingSecretResponseSchema,

  // Validation
  validateRecipient: validateRecipientResponseSchema,
} as const;
