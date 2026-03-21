// src/schemas/api/v3/responses/domains.ts
//
// V3 API response schemas for custom domain, jurisdiction, brand,
// and image endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  brandSettingsRecord,
  customDomainRecord,
  imagePropsRecord,
} from '@/schemas/shapes/v3/custom-domain';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Response-specific details schemas (not standalone entities)
// ─────────────────────────────────────────────────────────────────────────────

/** Custom domain details (proxy/cluster info). */
const customDomainDetails = z.object({
  cluster: z
    .object({
      type: z.string().nullable().optional(),
      proxy_ip: z.string().nullable().optional(),
      proxy_name: z.string().nullable().optional(),
      proxy_host: z.string().nullable().optional(),
      vhost_target: z.string().nullable().optional(),
      validation_strategy: z.string().nullable().optional(),
    })
    .optional()
    .nullable(),
  domain_context: z.string().optional().nullable(),
});

/** Jurisdiction record (config-derived). */
const jurisdictionRecord = z.object({
  identifier: z.string(),
  display_name: z.string(),
  domain: z.string(),
  icon: z.object({
    collection: z.string(),
    name: z.string(),
  }),
  enabled: z.boolean().default(true),
});

/** Jurisdiction detail flags. */
const jurisdictionDetails = z.object({
  is_default: z.boolean(),
  is_current: z.boolean(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const brandSettingsResponseSchema = createApiResponseSchema(brandSettingsRecord);
export const customDomainResponseSchema = createApiResponseSchema(customDomainRecord, customDomainDetails);
export const customDomainListResponseSchema = createApiListResponseSchema(customDomainRecord, customDomainDetails);
export const imagePropsResponseSchema = createApiResponseSchema(imagePropsRecord);
export const jurisdictionResponseSchema = createApiResponseSchema(jurisdictionRecord, jurisdictionDetails);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type BrandSettingsResponse = z.infer<typeof brandSettingsResponseSchema>;
export type CustomDomainResponse = z.infer<typeof customDomainResponseSchema>;
export type CustomDomainListResponse = z.infer<typeof customDomainListResponseSchema>;
export type ImagePropsResponse = z.infer<typeof imagePropsResponseSchema>;
export type JurisdictionResponse = z.infer<typeof jurisdictionResponseSchema>;
