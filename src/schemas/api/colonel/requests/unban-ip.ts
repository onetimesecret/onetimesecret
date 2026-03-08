// src/schemas/api/colonel/requests/unban-ip.ts
//
// Request schema for ColonelAPI::Logic::Colonel::UnbanIP
// DELETE /banned-ips/:ip
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// DELETE — IP in path param.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: ip
export const unbanIPRequestSchema = z.object({
  // TODO: fill in from ColonelAPI::Logic::Colonel::UnbanIP raise_concerns / process
});

export type UnbanIPRequest = z.infer<typeof unbanIPRequestSchema>;
