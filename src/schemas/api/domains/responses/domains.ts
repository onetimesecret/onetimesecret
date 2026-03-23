// src/schemas/api/domains/responses/domains.ts
//
// Response schemas for custom domain, jurisdiction, brand, and image endpoints.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  customDomainSchema,
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

export const brandSettingsResponseSchema = createApiResponseSchema(brandSettingschema);
export const customDomainResponseSchema = createApiResponseSchema(customDomainSchema, customDomainDetailsSchema);
export const customDomainListResponseSchema = createApiListResponseSchema(customDomainSchema, customDomainDetailsSchema);
export const imagePropsResponseSchema = createApiResponseSchema(imagePropsSchema);
export const jurisdictionResponseSchema = createApiResponseSchema(jurisdictionSchema, jurisdictionDetailsSchema);

export type BrandSettingsResponse = z.infer<typeof brandSettingsResponseSchema>;
export type CustomDomainDetails = z.infer<typeof customDomainDetailsSchema>;
export type CustomDomainProxy = CustomDomainDetails['cluster'];
export type CustomDomainResponse = z.infer<typeof customDomainResponseSchema>;
export type CustomDomainListResponse = z.infer<typeof customDomainListResponseSchema>;
export type ImagePropsResponse = z.infer<typeof imagePropsResponseSchema>;
export type JurisdictionResponse = z.infer<typeof jurisdictionResponseSchema>;
