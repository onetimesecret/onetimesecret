// src/schemas/config/section/features.ts

import { z } from 'zod/v4';
import { nullableString } from '../shared/primitives';

const featuresIncomingSchema = z.object({
  enabled: z.boolean().optional(),
  email: z.email().optional(),
  passphrase: z.string().optional(),
  regex: z.string().optional(),
});

const featuresRegionJurisdictionIconSchema = z.object({
  collection: z.string().optional(),
  name: z.string().optional(),
});

const featuresRegionJurisdictionSchema = z.object({
  identifier: z.string().optional(),
  display_name: z.string().optional(),
  domain: z.string().optional(),
  icon: featuresRegionJurisdictionIconSchema.optional(),
});

const featuresRegionsSchema = z.object({
  // YAML: <%= ENV['REGIONS_ENABLED'] || true %>
  enabled: z.boolean().optional(),
  current_jurisdiction: nullableString,
  jurisdictions: z.array(featuresRegionJurisdictionSchema).optional(),
});

const featuresDomainsClusterSchema = z.object({
  type: nullableString,
  api_key: nullableString,
  cluster_ip: nullableString,
  cluster_host: nullableString,
  cluster_name: nullableString,
  vhost_target: nullableString,
});

const featuresDomainsSchema = z.object({
  // YAML: <%= ENV['DOMAINS_ENABLED'] || true %>
  enabled: z.boolean().optional(),
  default: nullableString,
  cluster: featuresDomainsClusterSchema.optional(),
});

const featuresSchema = z.object({
  incoming: featuresIncomingSchema.optional(),
  regions: featuresRegionsSchema.optional(),
  domains: featuresDomainsSchema.optional(),
});

export { featuresSchema };
