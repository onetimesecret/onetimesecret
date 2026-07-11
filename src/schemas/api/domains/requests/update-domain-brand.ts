// src/schemas/api/domains/requests/update-domain-brand.ts
//
// Request schema for DomainsAPI::Logic::Domains::UpdateDomainBrand
// PUT /:extid/brand
//
// Transport wrapper: Ruby handler reads params['brand'], so the
// request body nests brand settings under a `brand` key.
//
// Targets the canonical contract (NOT the v2 wire shape) so the request
// TYPE admits the #3646 extended tokens — secondary_color, background_color,
// text_color, heading_font, full-range border_radius. The v2 shape declares
// none of them, so a v2-based type silently rejected extended-field updates at
// compile time (domainsStore.updateDomainBrand consumes this type). This schema
// is never `.parse()`d in the save path (brandStore/domainsStore PUT native v3
// records and parse the *response*), so retargeting is a compile-time type fix
// with no runtime transform change. `.partial()` is redundant on the already
// -partial canonical but kept explicit: every field is optional for PATCH.
import { brandSettingsCanonical } from '@/schemas/contracts';
import { z } from 'zod';

export const updateDomainBrandRequestSchema = z.object({
  brand: brandSettingsCanonical.partial(),
});

export type UpdateDomainBrandRequest = z.infer<typeof updateDomainBrandRequestSchema>;
