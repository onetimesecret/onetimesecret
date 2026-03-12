// src/schemas/api/domains/requests/remove-domain-icon.ts
//
// Request schema for DomainsAPI::Logic::Domains::RemoveDomainIcon
// DELETE /:extid/icon
//
//
// DELETE — extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const removeDomainIconRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::RemoveDomainIcon raise_concerns / process
});

export type RemoveDomainIconRequest = z.infer<typeof removeDomainIconRequestSchema>;
