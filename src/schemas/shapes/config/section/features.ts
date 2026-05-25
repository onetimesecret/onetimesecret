// src/schemas/shapes/config/section/features.ts

/**
 * Features Configuration Shape
 *
 * Adds runtime defaults and value constraints on top of the type-only
 * features contract — incoming-secret memo/TTL bounds, region defaults,
 * domain validation defaults, and ACME listener defaults.
 *
 * @see src/schemas/contracts/config/section/features.ts
 */

import { z } from 'zod';
import { nullableString } from '@/schemas/contracts/config/shared/primitives';

export {
  featuresSchema,
  featuresRegionsSchema,
  featuresIncomingSchema,
  featuresDomainsSchema,
  featuresDomainsProxySchema,
  featuresDomainsAcmeSchema,
} from '@/schemas/contracts/config/section/features';

const incomingRecipientShape = z.tuple([z.string(), z.string().optional()]).nullable();

const featuresIncomingShape = z.object({
  enabled: z.boolean().default(false),
  memo_max_length: z.number().int().positive().default(50),
  default_ttl: z.number().int().positive().default(604800),
  default_passphrase: z.string().nullable().optional(),
  recipients: z.array(incomingRecipientShape).optional(),
});

const featuresRegionJurisdictionIconShape = z.object({
  collection: z.string().optional(),
  name: z.string().optional(),
});

const featuresRegionJurisdictionShape = z.object({
  identifier: z.string().optional(),
  display_name: z.string().optional(),
  domain: z.string().optional(),
  icon: featuresRegionJurisdictionIconShape.optional(),
});

/**
 * Regions feature shape.
 *
 * `jurisdictions` stays permissive: the shipped YAML uses
 * `<%= ENV['JURISDICTIONS'] || '' %>`, which evaluates to a CSV string when
 * set and empty when not. Ruby parses that into the array shape elsewhere.
 */
const featuresRegionsShape = z.object({
  enabled: z.boolean().default(false),
  current_jurisdiction: nullableString,
  jurisdictions: z
    .union([z.array(featuresRegionJurisdictionShape), z.string(), z.null()])
    .optional(),
});

const featuresDomainsProxyShape = z.object({
  api_key: nullableString,
  proxy_ip: nullableString,
  proxy_host: nullableString,
  proxy_name: nullableString,
  vhost_target: nullableString,
});

/**
 * ACME endpoint shape.
 *
 * `port` accepts string or number: the shipped YAML uses
 * `<%= ENV['ACME_PORT'] || '12020' %>`, which renders to the bareword `12020`
 * and YAML auto-coerces to an integer at parse time. Both representations
 * are semantically the same TCP port.
 */
const featuresDomainsAcmeShape = z.object({
  enabled: z.boolean().default(false),
  listen_address: z.string().default('127.0.0.1'),
  port: z.union([z.string(), z.number()]).default('12020'),
});

const featuresDomainsShape = z.object({
  enabled: z.boolean().default(false),
  require_verified: z.boolean().default(false),
  default: nullableString,
  validation_strategy: z
    .enum(['passthrough', 'approximated', 'caddy_on_demand'])
    .default('passthrough'),
  approximated: featuresDomainsProxyShape.optional(),
  acme: featuresDomainsAcmeShape.optional(),
});

const featuresShape = z.object({
  regions: featuresRegionsShape.optional(),
  incoming: featuresIncomingShape.optional(),
  domains: featuresDomainsShape.optional(),
});

export {
  featuresShape,
  featuresRegionsShape,
  featuresIncomingShape,
  featuresDomainsShape,
  featuresDomainsProxyShape,
  featuresDomainsAcmeShape,
};
