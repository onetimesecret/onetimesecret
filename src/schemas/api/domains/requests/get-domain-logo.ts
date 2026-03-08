// src/schemas/api/domains/requests/get-domain-logo.ts
//
// Request schema for DomainsAPI::Logic::Domains::GetDomainLogo
// GET /:extid/logo
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — extid in path. Returns image.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const getDomainLogoRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::GetDomainLogo raise_concerns / process
});

export type GetDomainLogoRequest = z.infer<typeof getDomainLogoRequestSchema>;
