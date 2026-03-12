// src/schemas/api/domains/requests/remove-domain.ts
//
// Request schema for DomainsAPI::Logic::Domains::RemoveDomain
// POST /:extid/remove
//
//
// POST — extid in path. No body params.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const removeDomainRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::RemoveDomain raise_concerns / process
});

export type RemoveDomainRequest = z.infer<typeof removeDomainRequestSchema>;
