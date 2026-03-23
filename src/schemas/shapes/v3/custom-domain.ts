// src/schemas/shapes/v3/custom-domain.ts
//
// V3 wire-format shapes for custom domains.
// Derives from contracts, adding V3-specific transforms (number -> Date, native types).

import {
  brandSettingsCanonical,
  customDomainCanonical,
  imagePropsCanonical,
  vhostCanonical,
} from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 wire-format overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Timestamp field overrides for V3 wire format.
 * V3 sends timestamps as Unix epoch numbers; these transform to Date objects.
 */
const v3TimestampOverrides = {
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
};

// ─────────────────────────────────────────────────────────────────────────────
// V3 brand settings shape
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 brand settings record.
 *
 * V3 sends native types - booleans are native, no string transforms needed.
 * Extends contract with defaults for optional fields.
 *
 * @example
 * ```typescript
 * const brand = brandSettingsRecord.parse({
 *   primary_color: '#dc4a22',
 *   font_family: 'sans',
 *   button_text_light: false,
 * });
 * ```
 */
export const brandSettingsRecord = brandSettingsCanonical.extend({
  // V3 sends native booleans, add defaults
  button_text_light: z.boolean().default(false),
  allow_public_homepage: z.boolean().default(false),
  allow_public_api: z.boolean().default(false),
  passphrase_required: z.boolean().default(false),
  notify_enabled: z.boolean().default(false),
});

/**
 * V3 image properties record.
 *
 * Image metadata for logo and icon fields.
 */
export const imagePropsRecord = imagePropsCanonical;

// ─────────────────────────────────────────────────────────────────────────────
// V3 vhost shape
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 vhost record.
 *
 * Extends contract with timestamp transforms for date fields.
 *
 * IMPORTANT: Vhost data comes verbatim from Approximated API, which returns
 * timestamps as strings (ISO 8601 or similar), NOT Unix epoch numbers.
 * Therefore we use fromString transforms here, not fromNumber.
 *
 * @example
 * ```typescript
 * const vhost = vhostRecord.parse({
 *   status: 'active',
 *   has_ssl: true,
 *   is_resolving: true,
 *   last_monitored_unix: '2021-01-01T00:00:00Z',
 * });
 *
 * console.log(vhost.last_monitored_unix instanceof Date); // true
 * ```
 */
export const vhostRecord = vhostCanonical.extend({
  // V3 sends booleans as native types
  apx_hit: z.boolean().optional(),
  has_ssl: z.boolean().optional(),
  is_resolving: z.boolean().optional(),

  // Approximated API sends timestamps as strings, not numbers
  // All timestamp fields are optional - external API may omit them,
  // and historical data may predate these fields.
  created_at: transforms.fromString.date.optional(),
  last_monitored_unix: transforms.fromString.date.optional(),
  ssl_active_from: transforms.fromString.dateNullable.optional(),
  ssl_active_until: transforms.fromString.dateNullable.optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// V3 custom domain shape
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 custom domain record.
 *
 * Derives from contract, adds V3 wire-format transforms:
 * - Timestamps: number (Unix epoch seconds) -> Date
 * - Boolean fields: native booleans (no string transform needed)
 * - Nested objects: vhost and brand with their own V3 transforms
 *
 * V3 is the clean API - native JSON types without string encoding.
 *
 * @example
 * ```typescript
 * const domain = customDomainRecord.parse({
 *   identifier: 'secrets.example.com',
 *   domainid: '01234567-89ab-cdef-0123-456789abcdef',
 *   extid: 'cd1a2b3c4d',
 *   display_domain: 'secrets.example.com',
 *   base_domain: 'example.com',
 *   subdomain: 'secrets.example.com',
 *   trd: 'secrets',
 *   tld: 'com',
 *   sld: 'example',
 *   is_apex: false,
 *   txt_validation_host: '_onetime-challenge.secrets.example.com',
 *   txt_validation_value: 'abc123...',
 *   verified: true,
 *   resolving: true,
 *   created: 1609372800,
 *   updated: 1609459200,
 *   vhost: { status: 'active', has_ssl: true },
 *   brand: { primary_color: '#dc4a22' },
 * });
 *
 * console.log(domain.created instanceof Date); // true
 * console.log(domain.verified); // true (native boolean)
 * ```
 */
export const customDomainRecord = customDomainCanonical.extend({
  // Wire-format overrides
  ...v3TimestampOverrides,

  // V3 sends native booleans
  is_apex: z.boolean().default(false),
  verified: z.boolean().default(false),
  resolving: z.boolean().optional().default(false),

  // Nested objects with V3 transforms
  vhost: transforms.fromObject.nested(vhostRecord.passthrough().strip()).nullable().default(null),
  brand: transforms.fromObject.nested(brandSettingsRecord.passthrough().strip()).nullable().default(null),

  // Optional fields with defaults
  org_id: z.string().optional(),
  custid: z.string().nullable().default(null),
  subdomain: z.string().nullable().default(null),
  trd: z.string().nullable().default(null),
  status: z.string().optional().default('pending'),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V3 brand settings record. */
export type BrandSettingsRecord = z.infer<typeof brandSettingsRecord>;

/** TypeScript type for V3 image properties record. */
export type ImagePropsRecord = z.infer<typeof imagePropsRecord>;

/** TypeScript type for V3 vhost record. */
export type VHostRecord = z.infer<typeof vhostRecord>;

/** TypeScript type for V3 custom domain record. */
export type CustomDomainRecord = z.infer<typeof customDomainRecord>;
