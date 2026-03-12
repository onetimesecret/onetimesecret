// src/schemas/api/domains/requests/get-domain-logo.ts
//
// Request schema for DomainsAPI::Logic::Domains::GetDomainLogo
// GET /:extid/logo
//
//
// GET — extid in path. Returns image.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const getDomainLogoRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::GetDomainLogo raise_concerns / process
});

export type GetDomainLogoRequest = z.infer<typeof getDomainLogoRequestSchema>;
