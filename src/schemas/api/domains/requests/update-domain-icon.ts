// src/schemas/api/domains/requests/update-domain-icon.ts
//
// Request schema for DomainsAPI::Logic::Domains::UpdateDomainIcon
// POST /:extid/icon
//
//
// POST — multipart file upload. Extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const updateDomainIconRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::UpdateDomainIcon raise_concerns / process
});

export type UpdateDomainIconRequest = z.infer<typeof updateDomainIconRequestSchema>;
