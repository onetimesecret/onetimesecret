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

import {
  featuresSchema,
  featuresRegionsSchema,
  featuresIncomingSchema,
  featuresDomainsSchema,
  featuresDomainsProxySchema,
  featuresDomainsAcmeSchema,
} from '@/schemas/contracts/config/section/features';
import { augment } from '@/schemas/utils/augment';

export {
  featuresSchema,
  featuresRegionsSchema,
  featuresIncomingSchema,
  featuresDomainsSchema,
  featuresDomainsProxySchema,
  featuresDomainsAcmeSchema,
};

const featuresIncomingShape = augment(featuresIncomingSchema, {
  enabled: (b) => b.default(false),
  memo_max_length: (n) => n.int().positive().default(50),
  default_ttl: (n) => n.int().positive().default(604800),
});

const featuresRegionsShape = augment(featuresRegionsSchema, {
  enabled: (b) => b.default(false),
});

const featuresDomainsProxyShape = featuresDomainsProxySchema;

/**
 * ACME endpoint shape.
 *
 * `port` stays a string|number union — the shipped YAML uses
 * `<%= ENV['ACME_PORT'] || '12020' %>`, which renders to the bareword
 * `12020` that YAML auto-coerces to an integer. Both representations are
 * the same TCP port. The default keeps the string form to match the
 * env-unset path.
 */
const featuresDomainsAcmeShape = augment(featuresDomainsAcmeSchema, {
  enabled: (b) => b.default(false),
  listen_address: (s) => s.default('127.0.0.1'),
  port: (u) => u.default('12020'),
});

const featuresDomainsShape = augment(featuresDomainsSchema, {
  enabled: (b) => b.default(false),
  require_verified: (b) => b.default(false),
  validation_strategy: (e) => e.default('passthrough'),
  acme: {
    enabled: (b) => b.default(false),
    listen_address: (s) => s.default('127.0.0.1'),
    port: (u) => u.default('12020'),
  },
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
    acme: {
      enabled: (b) => b.default(false),
      listen_address: (s) => s.default('127.0.0.1'),
      port: (u) => u.default('12020'),
    },
  },
});

export {
  featuresShape,
  featuresRegionsShape,
  featuresIncomingShape,
  featuresDomainsShape,
  featuresDomainsProxyShape,
  featuresDomainsAcmeShape,
};
