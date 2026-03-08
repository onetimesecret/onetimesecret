// src/schemas/api/colonel/requests/get-user-details.ts
//
// Request schema for ColonelAPI::Logic::Colonel::GetUserDetails
// GET /users/:user_id
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — user_id in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: user_id
export const getUserDetailsRequestSchema = z.object({
  // TODO: fill in from ColonelAPI::Logic::Colonel::GetUserDetails raise_concerns / process
});

export type GetUserDetailsRequest = z.infer<typeof getUserDetailsRequestSchema>;
