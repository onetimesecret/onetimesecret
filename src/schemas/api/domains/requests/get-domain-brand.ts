// src/schemas/api/domains/requests/get-domain-brand.ts
//
// Request schema for DomainsAPI::Logic::Domains::GetDomainBrand
// GET /:extid/brand
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — extid in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const getDomainBrandRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::GetDomainBrand raise_concerns / process
});

export type GetDomainBrandRequest = z.infer<typeof getDomainBrandRequestSchema>;
