// src/schemas/api/domains/requests/add-domain.ts
//
// Request schema for DomainsAPI::Logic::Domains::AddDomain
// POST /add
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const addDomainRequestSchema = z.object({
  /** Domain name to add (validated with PublicSuffix) */
  domain: z.string(),
  /** Organization ID to associate domain with */
  org_id: z.string().optional(),
});

export type AddDomainRequest = z.infer<typeof addDomainRequestSchema>;
