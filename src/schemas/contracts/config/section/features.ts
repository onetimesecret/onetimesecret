// src/schemas/contracts/config/section/features.ts

/**
 * Features Configuration Schema
 *
 * Maps to the `features:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and value constraints belong in shapes — not here.
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
 * Domain proxy configuration (for approximated strategy)
 */
const featuresDomainsProxySchema = z.object({
  api_key: nullableString,
  proxy_ip: nullableString,
  proxy_host: nullableString,
  proxy_name: nullableString,
  vhost_target: nullableString,
});

/**
 * ACME endpoint configuration (for caddy_on_demand strategy)
 *
 * `port` accepts string or number: the shipped YAML uses
 * `<%= ENV['ACME_PORT'] || '12020' %>`, which renders to the bareword
 * `12020`, and YAML auto-coerces that to an integer at parse time.
 * Both representations are semantically the same TCP port.
 */
const featuresDomainsAcmeSchema = z.object({
  enabled: z.boolean().optional(),
  listen_address: z.string().optional(),
  port: z.union([z.string(), z.number()]).optional(),
});

/**
 * Domains feature configuration
 *
 * Field names mirror `features.domains` in etc/defaults/config.defaults.yaml.
 * The bootstrap payload is the raw Ruby hash (see ConfigSerializer), so any
 * rename here must be applied on the Ruby side as well.
 */
const featuresDomainsSchema = z.object({
  enabled: z.boolean().optional(),
  require_verified: z.boolean().optional(),
  default: nullableString,
  validation_strategy: z.enum(['passthrough', 'approximated', 'caddy_on_demand']).optional(),
  approximated: featuresDomainsProxySchema.optional(),
  acme: featuresDomainsAcmeSchema.optional(),
});

/**
 * Complete features schema
 */
const featuresSchema = z.object({
  regions: featuresRegionsSchema.optional(),
  incoming: featuresIncomingSchema.optional(),
  domains: featuresDomainsSchema.optional(),
});

export {
  featuresSchema,
  featuresRegionsSchema,
  featuresIncomingSchema,
  featuresDomainsSchema,
  featuresDomainsProxySchema,
  featuresDomainsAcmeSchema,
};
