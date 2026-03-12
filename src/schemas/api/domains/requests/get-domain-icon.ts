// src/schemas/api/domains/requests/get-domain-icon.ts
//
// Request schema for DomainsAPI::Logic::Domains::GetDomainIcon
// GET /:extid/icon
//
//
// GET — extid in path. Returns image.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const getDomainIconRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::GetDomainIcon raise_concerns / process
});

export type GetDomainIconRequest = z.infer<typeof getDomainIconRequestSchema>;
