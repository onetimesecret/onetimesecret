// src/schemas/contracts/config/section/features.ts

/**
 * Features Configuration Schema
 *
 * Maps to the `features:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and value constraints belong in `shapes/config/section/features.ts`.
 */

import { z } from 'zod';
import { nullableString } from '../shared/primitives';

/**
 * Incoming secrets recipient configuration
 */
const incomingRecipientSchema = z.tuple([z.string(), z.string().optional()]).nullable();

/**
 * Incoming secrets feature configuration
 */
const featuresIncomingSchema = z.object({
  enabled: z.boolean().optional(),
  memo_max_length: z.number().optional(),
  default_ttl: z.number().optional(),
  default_passphrase: z.string().nullable().optional(),
  recipients: z.array(incomingRecipientSchema).optional(),
});

/**
 * Region jurisdiction icon configuration
 */
const featuresRegionJurisdictionIconSchema = z.object({
  collection: z.string().optional(),
  name: z.string().optional(),
});

/**
 * Region jurisdiction configuration
 */
const featuresRegionJurisdictionSchema = z.object({
  identifier: z.string().optional(),
  display_name: z.string().optional(),
  domain: z.string().optional(),
  icon: featuresRegionJurisdictionIconSchema.optional(),
});

/**
 * Regions feature configuration
 *
 * `jurisdictions` is intentionally permissive: the shipped YAML uses
 * `<%= ENV['JURISDICTIONS'] || '' %>`, which evaluates to a string (CSV when
 * set, empty/nil when not). Ruby parses that into the array shape elsewhere.
 * Accepting array | string | null here lets `bin/ots config validate` pass
 * on the raw post-ERB YAML without weakening the validated array shape when
 * an operator does provide a structured list.
 */
const featuresRegionsSchema = z.object({
  enabled: z.boolean().optional(),
  current_jurisdiction: nullableString,
  jurisdictions: z
    .union([z.array(featuresRegionJurisdictionSchema), z.string(), z.null()])
    .optional(),
});

/**
 * Domains feature configuration
 *
 * Allowlisted subset of `features.domains` from
 * etc/defaults/config.defaults.yaml, serialized by
 * ConfigSerializer#transform_domains — any rename here must be applied on
 * the Ruby side as well. The `approximated` (proxy credentials) and `acme`
 * (internal listener) blocks are server-side only and must never appear in
 * a client-facing payload — do not re-add them here; per-domain DNS targets
 * come from the authenticated domains API.
 */
const featuresDomainsSchema = z.object({
  enabled: z.boolean().optional(),
  require_verified: z.boolean().optional(),
  default: nullableString,
  validation_strategy: z.enum(['passthrough', 'approximated', 'caddy_on_demand']).optional(),
});

/**
 * Complete features schema
 */
const featuresSchema = z.object({
  regions: featuresRegionsSchema.optional(),
  incoming: featuresIncomingSchema.optional(),
  domains: featuresDomainsSchema.optional(),
});

export { featuresSchema, featuresRegionsSchema, featuresIncomingSchema, featuresDomainsSchema };
