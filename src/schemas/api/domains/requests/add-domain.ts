// src/schemas/api/domains/requests/add-domain.ts
//
// Request schema for DomainsAPI::Logic::Domains::AddDomain
// POST /add
//
// Stricter validation from production usage (DomainForm.vue):
// - min 3 chars, alphanumeric with hyphens/dots/underscores

import { z } from 'zod';

export const addDomainRequestSchema = z.object({
  /** Domain name to add (validated with PublicSuffix) */
  domain: z
    .string()
    .min(3)
    .regex(/^[a-zA-Z0-9][a-zA-Z0-9-_.]+[a-zA-Z0-9]$/),
  /** Organization ID to associate domain with */
  org_id: z.string().optional(),
});

export type AddDomainRequest = z.infer<typeof addDomainRequestSchema>;
