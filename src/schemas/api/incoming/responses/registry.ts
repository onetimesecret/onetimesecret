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
 *
 * Keys must match the Ruby SCHEMAS constant declarations in
 * apps/api/incoming/logic/*.rb for the schema scanner to validate correctly.
 */
export const responseSchemas = {
  // Config - Ruby: SCHEMAS = { response: 'incomingConfig' }
  incomingConfig: incomingConfigResponseSchema,

  // Secrets - Ruby: SCHEMAS = { response: 'incomingSecret' }
  incomingSecret: incomingSecretResponseSchema,

  // Validation - Ruby: SCHEMAS = { response: 'validateRecipient' }
  validateRecipient: validateRecipientResponseSchema,
} as const;
