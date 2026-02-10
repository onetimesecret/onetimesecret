// src/schemas/config/section/features.ts

/**
 * Features Configuration Schema
 *
 * Maps to the `features:` section in config.defaults.yaml
 */

import { z } from 'zod/v4';
import { nullableString } from '../shared/primitives';

/**
 * Incoming secrets recipient configuration
 */
const incomingRecipientSchema = z.tuple([z.string(), z.string().optional()]).nullable();

/**
 * Incoming secrets feature configuration
 */
const featuresIncomingSchema = z.object({
  enabled: z.boolean().default(false),
  memo_max_length: z.number().int().positive().default(50),
  default_ttl: z.number().int().positive().default(604800),
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
 */
const featuresRegionsSchema = z.object({
  enabled: z.boolean().default(false),
  current_jurisdiction: nullableString,
  federation_hmac_secret: nullableString,
  jurisdictions: z.array(featuresRegionJurisdictionSchema).optional(),
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
 */
const featuresDomainsAcmeSchema = z.object({
  enabled: z.boolean().default(false),
  listen_address: z.string().default('127.0.0.1'),
  port: z.union([z.string(), z.number()]).default('12020'),
});

/**
 * Domains feature configuration
 */
const featuresDomainsSchema = z.object({
  enabled: z.boolean().default(false),
  default: nullableString,
  validation_strategy: z.enum(['passthrough', 'approximated', 'caddy_on_demand']).default('passthrough'),
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
