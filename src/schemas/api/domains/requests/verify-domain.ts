// src/schemas/api/domains/requests/verify-domain.ts
//
// Request schema for DomainsAPI::Logic::Domains::VerifyDomain
// POST /:extid/verify
//
//
// POST — extid in path. Triggers DNS verification.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: extid
export const verifyDomainRequestSchema = z.object({
  // TODO: fill in from DomainsAPI::Logic::Domains::VerifyDomain raise_concerns / process
});

export type VerifyDomainRequest = z.infer<typeof verifyDomainRequestSchema>;
