// src/schemas/models/domain/index.ts
export * from './brand';
export * from './vhost';

// src/schemas/models/domain.ts
import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

import { brandSettingschema } from './brand';
import { vhostSchema } from './vhost';

// Domain strategy constants and type
export const DomainStrategyValues = {
  CANONICAL: 'canonical',
  SUBDOMAIN: 'subdomain',
  CUSTOM: 'custom',
  INVALID: 'invalid',
} as const;

export type DomainStrategy = (typeof DomainStrategyValues)[keyof typeof DomainStrategyValues];

/**
 * Input schema for custom domain from API
 * - Handles string -> boolean coercion from Ruby/Redis
 * - Validates domain parts
 * - Handles nested objects (vhost, brand)
 */
export const customDomainSchema = createModelSchema({
  // Core identifiers
  domainid: z.string(),
  custid: z.string(),

  // Domain parts
  display_domain: z.string(),
  base_domain: z.string(),
  subdomain: z.string(),
  trd: z.string(),
  tld: z.string(),
  sld: z.string(),
  _original_value: z.string(),

  // Boolean fields that come as strings from API
  is_apex: transforms.fromString.boolean,
  verified: transforms.fromString.boolean,

  // Validation fields
  txt_validation_host: z.string(),
  txt_validation_value: z.string(),

  // Optional nested objects that can be:
  // 1. undefined
  // 2. A valid object matching their respective schemas
  // 3. An object with any properties (which will be stripped at root level)
  //
  // We use .passthrough() here to allow unknown properties in nested objects,
  // letting them bubble up to the root level where they'll be stripped via
  // customDomainSchema's .strip()
  //
  // This approach:
  // - Prevents validation errors from unexpected API fields
  // - Centralizes stripping behavior at the root level
  // - Makes debugging easier by allowing field inspection before stripping
  // - Added `.passthrough()` to allow unknown properties during validation
  // - Added `.strip()` to remove unknown properties after validation
  vhost: transforms.fromObject.nested(vhostSchema.passthrough().strip()).nullable(),
  brand: transforms.fromObject.nested(brandSettingschema.passthrough().strip()).nullable(),
  // The .strip() modifier removes all unknown properties throughout the entire
  // object hierarchy after validation. This ensures our domain objects maintain
  // a consistent shape regardless of API response variations.
}).strip();

/**
 * Input schema for domain cluster from API
 * Used for managing domain routing/infrastructure. Always null
 * when DOMAINS_ENABLED is false.
 */
const customDomainClusterSchema = z
  .object({
    type: z.string().nullable().optional(),
    cluster_ip: z.string().nullable().optional(),
    cluster_name: z.string().nullable().optional(),
    cluster_host: z.string().nullable().optional(),
    vhost_target: z.string().nullable().optional(),
  })
  .strip()
  .optional()
  .nullable();

export const customDomainDetailsSchema = z.object({
  cluster: customDomainClusterSchema,
});

export type CustomDomainCluster = z.infer<typeof customDomainClusterSchema>;

// Export types
export type CustomDomain = z.infer<typeof customDomainSchema>;
export type CustomDomainDetails = z.infer<typeof customDomainDetailsSchema>;
