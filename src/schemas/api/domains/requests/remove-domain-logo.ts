// src/schemas/api/domains/requests/remove-domain-logo.ts
//
// Request schema for DomainsAPI::Logic::Domains::RemoveDomainLogo
// DELETE /:extid/logo
//
//
// DELETE — extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const removeDomainLogoRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::RemoveDomainLogo raise_concerns / process
});

export type RemoveDomainLogoRequest = z.infer<typeof removeDomainLogoRequestSchema>;
