// src/schemas/api/v3/responses/domains.ts
//
// V3 JSON wire-format schemas for custom domain, jurisdiction, brand,
// and image endpoints.
// Timestamps use transforms.fromNumber.toDate so that .parse() returns
// Date objects for the frontend while io:"input" still documents them
// as numbers in OpenAPI.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas
// ─────────────────────────────────────────────────────────────────────────────

const fontFamilyValues = ['sans', 'serif', 'mono'] as const;
const cornerStyleValues = ['rounded', 'pill', 'square'] as const;

/** Brand settings nested inside a custom domain. */
const brandSettingsRecord = z
  .object({
    primary_color: z.string().default('#dc4a22'),
    colour: z.string().optional(),
    instructions_pre_reveal: z.string().nullish(),
    instructions_reveal: z.string().nullish(),
    instructions_post_reveal: z.string().nullish(),
    description: z.string().optional(),
    button_text_light: z.boolean().default(false),
    allow_public_homepage: z.boolean().default(false),
    allow_public_api: z.boolean().default(false),
    font_family: z.enum(fontFamilyValues).default('sans'),
    corner_style: z.enum(cornerStyleValues).default('rounded'),
    locale: z.string().default('en'),
    default_ttl: z.number().nullish(),
    passphrase_required: z.boolean().default(false),
    notify_enabled: z.boolean().default(false),
  })
  .partial();

/** Vhost (virtual host) details from domain provider.
 *  Timestamps use fromString.date/dateNullable (parseDateValue) instead
 *  of fromNumber transforms because vhost data comes verbatim from an
 *  external provider (Approximated) whose API returns string timestamps,
 *  not the numeric epochs that OTS's own V3 serialization produces.
 */
const vhostRecord = z
  .object({
    target_address: z.string().optional(),
    target_ports: z.string().optional(),
    target_cname: z.string().optional(),
    apx_hit: z.boolean().optional(),
    has_ssl: z.boolean().optional(),
    is_resolving: z.boolean().optional(),
    status_message: z.string().optional(),
    created_at: transforms.fromString.date.optional(),
    last_monitored_unix: transforms.fromString.date.optional(),
    ssl_active_from: transforms.fromString.dateNullable,
    ssl_active_until: transforms.fromString.dateNullable,
  })
  .partial();

/** Image properties record. */
const imagePropsRecord = z
  .object({
    encoded: z.string().optional(),
    content_type: z.string().optional(),
    filename: z.string().optional(),
    bytes: z.number().optional(),
    width: z.number().optional(),
    height: z.number().optional(),
    ratio: z.number().optional(),
  })
  .partial();

/** Custom domain record. */
const customDomainRecord = z.object({
  identifier: z.string(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  domainid: z.string(),
  extid: z.string(),
  custid: z.string().nullable(),
  display_domain: z.string(),
  base_domain: z.string(),
  subdomain: z.string().nullable(),
  trd: z.string().nullable(),
  tld: z.string(),
  sld: z.string(),
  is_apex: z.boolean(),
  verified: z.boolean(),
  txt_validation_host: z.string(),
  txt_validation_value: z.string(),
  vhost: vhostRecord.nullable(),
  brand: brandSettingsRecord.nullable(),
});

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

/** Jurisdiction record. */
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
