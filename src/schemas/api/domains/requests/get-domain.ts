// src/schemas/api/domains/requests/get-domain.ts
//
// Request schema for DomainsAPI::Logic::Domains::GetDomain
// GET /:extid
//
//
// GET — extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const getDomainRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::GetDomain raise_concerns / process
});

export type GetDomainRequest = z.infer<typeof getDomainRequestSchema>;
