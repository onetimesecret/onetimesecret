// src/schemas/api/domains/responses/domains.ts
//
// Response schemas for custom domain, jurisdiction, brand, and image endpoints.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import { customDomainCanonical } from '@/schemas/contracts';
import {
  jurisdictionDetailsSchema,
  jurisdictionSchema,
} from '@/schemas/shapes/v2';
import { brandSettingschema, imagePropsSchema } from '@/schemas/shapes/v2/custom-domain/brand';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schemas (not standalone entities)
// ─────────────────────────────────────────────────────────────────────────────

/** Custom domain details (proxy/cluster info). */
export const customDomainDetailsSchema = z.object({
  cluster: z
    .object({
      type: z.string().nullable().optional(),
      proxy_ip: z.string().nullable().optional(),
      proxy_name: z.string().nullable().optional(),
      proxy_host: z.string().nullable().optional(),
      vhost_target: z.string().nullable().optional(),
      validation_strategy: z.string().nullable().optional(),
    })
    .strip()
    .optional()
    .nullable(),
  domain_context: z.string().optional().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

// v2-lane brand response. Wraps the v2 wire shape (`brandSettingschema`):
// string-encoded booleans, and — by design — WITHOUT the #3646 extended tokens
// (secondary_color, background_color, text_color, heading_font, border_radius).
// A v2 client parsing them would need string-boolean coercion that the native
// v3 canonical shape does not provide, so DO NOT retarget this to v3/canonical.
// The extended tokens ride the v3 lane: `@/schemas/api/v3/responses/domains.ts`
// wraps the canonical `brandSettingsSchema`, and that is what the Pinia stores
// (brandStore, domainsStore) actually parse via `@/schemas/api/v3/responses`.
export const brandSettingsResponseSchema = createApiResponseSchema(brandSettingschema);
export const customDomainResponseSchema = createApiResponseSchema(
  customDomainCanonical,
  customDomainDetailsSchema
);
export const customDomainListResponseSchema = createApiListResponseSchema(
  customDomainCanonical,
  customDomainDetailsSchema
);
export const imagePropsResponseSchema = createApiResponseSchema(imagePropsSchema);
export const jurisdictionResponseSchema = createApiResponseSchema(
  jurisdictionSchema,
  jurisdictionDetailsSchema
);

export type BrandSettingsResponse = z.infer<typeof brandSettingsResponseSchema>;
export type CustomDomainDetails = z.infer<typeof customDomainDetailsSchema>;
export type CustomDomainProxy = CustomDomainDetails['cluster'];
export type CustomDomainResponse = z.infer<typeof customDomainResponseSchema>;
export type CustomDomainListResponse = z.infer<typeof customDomainListResponseSchema>;
export type ImagePropsResponse = z.infer<typeof imagePropsResponseSchema>;
export type JurisdictionResponse = z.infer<typeof jurisdictionResponseSchema>;
