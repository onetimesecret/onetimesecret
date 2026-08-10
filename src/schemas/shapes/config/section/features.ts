// src/schemas/shapes/config/section/features.ts

/**
 * Features Configuration Shape
 *
 * Adds runtime defaults and value constraints on top of the type-only
 * features contract — incoming-secret memo/TTL bounds, region defaults,
 * and domain validation defaults.
 *
 * @see src/schemas/contracts/config/section/features.ts
 */

import {
  featuresSchema,
  featuresRegionsSchema,
  featuresIncomingSchema,
  featuresDomainsSchema,
} from '@/schemas/contracts/config/section/features';
import { augment } from '@/schemas/utils/augment';

export { featuresSchema, featuresRegionsSchema, featuresIncomingSchema, featuresDomainsSchema };

const featuresIncomingShape = augment(featuresIncomingSchema, {
  enabled: (b) => b.default(false),
  memo_max_length: (n) => n.int().positive().default(50),
  default_ttl: (n) => n.int().positive().default(604800),
});

const featuresRegionsShape = augment(featuresRegionsSchema, {
  enabled: (b) => b.default(false),
});

const featuresDomainsShape = augment(featuresDomainsSchema, {
  enabled: (b) => b.default(false),
  require_verified: (b) => b.default(false),
  validation_strategy: (e) => e.default('passthrough'),
});

const featuresShape = augment(featuresSchema, {
  regions: { enabled: (b) => b.default(false) },
  incoming: {
    enabled: (b) => b.default(false),
    memo_max_length: (n) => n.int().positive().default(50),
    default_ttl: (n) => n.int().positive().default(604800),
  },
  domains: {
    enabled: (b) => b.default(false),
    require_verified: (b) => b.default(false),
    validation_strategy: (e) => e.default('passthrough'),
  },
});

export { featuresShape, featuresRegionsShape, featuresIncomingShape, featuresDomainsShape };
