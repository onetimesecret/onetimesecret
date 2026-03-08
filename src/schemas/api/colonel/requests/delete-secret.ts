// src/schemas/api/colonel/requests/delete-secret.ts
//
// Request schema for ColonelAPI::Logic::Colonel::DeleteSecret
// DELETE /secrets/:secret_id
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// DELETE — secret_id in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: secret_id
export const deleteSecretRequestSchema = z.object({
  // TODO: fill in from ColonelAPI::Logic::Colonel::DeleteSecret raise_concerns / process
});

export type DeleteSecretRequest = z.infer<typeof deleteSecretRequestSchema>;
