// src/schemas/shapes/v3/custom-domain/index.ts
//
// V3 wire-format shapes for custom domains.
// Derives from contracts, adding V3-specific transforms (number -> Date, native types).

import { customDomainCanonical } from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

import { brandSettingsSchema } from './brand';
import { vhostSchema } from './vhost';

export * from './brand';
export * from './vhost';

// ─────────────────────────────────────────────────────────────────────────────
// Domain strategy constants
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Domain strategy values for routing decisions.
 */
export const DomainStrategyValues = {
  CANONICAL: 'canonical',
  SUBDOMAIN: 'subdomain',
  CUSTOM: 'custom',
  INVALID: 'invalid',
} as const;

export type DomainStrategy = (typeof DomainStrategyValues)[keyof typeof DomainStrategyValues];

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
// V3 custom domain shape
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 custom domain schema.
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
 * const domain = customDomainSchema.parse({
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
export const customDomainSchema = customDomainCanonical.extend({
  // Wire-format overrides
  ...v3TimestampOverrides,

  // V3 sends native booleans
  is_apex: z.boolean().default(false),
  verified: z.boolean().default(false),
  resolving: z.boolean().optional().default(false),

  // Nested objects with V3 transforms
  vhost: transforms.fromObject.nested(vhostSchema.passthrough().strip()).nullable().default(null),
  brand: transforms.fromObject.nested(brandSettingsSchema.passthrough().strip()).nullable().default(null),

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

/** TypeScript type for V3 custom domain. */
export type CustomDomain = z.infer<typeof customDomainSchema>;
