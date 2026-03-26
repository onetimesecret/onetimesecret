// src/schemas/api/domains/requests/update-domain-brand.ts
//
// Request schema for DomainsAPI::Logic::Domains::UpdateDomainBrand
// PUT /:extid/brand
//
// Transport wrapper: Ruby handler reads params['brand'], so the
// request body nests brand settings under a `brand` key.

import { brandSettingschema } from '@/schemas/shapes/v2/custom-domain/brand';
import { z } from 'zod';

export const updateDomainBrandRequestSchema = z.object({
  brand: brandSettingschema.partial(),
});

export type UpdateDomainBrandRequest = z.infer<typeof updateDomainBrandRequestSchema>;
