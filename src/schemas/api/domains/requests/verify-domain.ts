// src/schemas/api/domains/requests/verify-domain.ts
//
// Request schema for DomainsAPI::Logic::Domains::VerifyDomain
// POST /:extid/verify
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// POST — extid in path. Triggers DNS verification.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const verifyDomainRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::VerifyDomain raise_concerns / process
});

export type VerifyDomainRequest = z.infer<typeof verifyDomainRequestSchema>;
