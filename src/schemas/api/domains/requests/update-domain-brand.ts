// src/schemas/api/domains/requests/update-domain-brand.ts
//
// Request schema for DomainsAPI::Logic::Domains::UpdateDomainBrand
// PUT /:extid/brand
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// Existing Zod schema in v3/requests.ts (updateDomainBrandRequestSchema).

import { z } from 'zod';

export const updateDomainBrandRequestSchema = z.object({
  /** Hex color for brand */
  primary_color: z.string().optional(),
  /** Font family enum */
  font_family: z.string().optional(),
  /** Corner style enum */
  corner_style: z.string().optional(),
  /** Default TTL in seconds (entitlement-gated) */
  default_ttl: z.number().int().optional(),
  /** Allow public homepage (entitlement-gated) */
  allow_public_homepage: z.boolean().optional(),
});

export type UpdateDomainBrandRequest = z.infer<typeof updateDomainBrandRequestSchema>;
