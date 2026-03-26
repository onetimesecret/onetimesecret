// src/tests/schemas/shapes/fixtures/customer.fixtures.ts
//
// Customer test fixtures using factory pattern.
// All timestamps use round seconds to survive epoch conversion.
//
// Note: Customer uses withFeatureFlags() which adds dynamic feature_flags field.
// The V2 schema transforms string-encoded booleans/numbers from Redis.

import type { CustomerCanonical } from '@/schemas/contracts';
import {
  toV2WireCustomer,
  toV3WireCustomer,
  type V2WireCustomer,
  type V3WireCustomer,
} from '../helpers/serializers';

// Re-export CustomerCanonical for backward compatibility with existing imports
export type { CustomerCanonical } from '@/schemas/contracts';

// -----------------------------------------------------------------------------
// Constants for round-second timestamps
// -----------------------------------------------------------------------------

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

/** One day earlier */
const ONE_DAY_EARLIER = new Date('2024-01-14T10:00:00.000Z');

/** One hour ago */
const ONE_HOUR_AGO = new Date('2024-01-15T09:00:00.000Z');

// -----------------------------------------------------------------------------
// Canonical Factories
// -----------------------------------------------------------------------------

/**
 * Creates a canonical customer with sensible defaults.
 * All timestamps are round seconds for epoch conversion safety.
 */
export function createCanonicalCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return {
    // Base model fields
    created: BASE_TIMESTAMP,
    updated: BASE_TIMESTAMP,

    // Core fields
    objid: 'c4st0m3r12ab',
    extid: 'ext_c4st0m3r12ab',
    role: 'customer',
    email: 'user@example.com',

    // Boolean fields
    verified: true,
    active: true,
    contributor: false,

    // Counter fields
    secrets_created: 5,
    secrets_burned: 1,
    secrets_shared: 3,
    emails_sent: 10,

    // Date fields
    last_login: ONE_HOUR_AGO,

    // Optional fields
    locale: 'en',

    // Notification preferences
    notify_on_reveal: true,

    // Feature flags
    feature_flags: {},

    ...overrides,
  };
}

// -----------------------------------------------------------------------------
// Role-Specific Factories
// -----------------------------------------------------------------------------

/**
 * Creates a "colonel" role customer (admin).
 */
export function createColonelCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    objid: 'c0l0n3l123ab',
    extid: 'ext_c0l0n3l123ab',
    role: 'colonel',
    email: 'admin@example.com',
    verified: true,
    active: true,
    feature_flags: {
      admin_panel: true,
      bulk_operations: true,
    },
    ...overrides,
  });
}

/**
 * Creates a "recipient" role customer (anonymous secret receiver).
 */
export function createRecipientCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    objid: 'r3c1p13nt12ab',
    extid: 'ext_r3c1p13nt12ab',
    role: 'recipient',
    email: 'recipient@example.com',
    verified: false,
    active: true,
    secrets_created: 0,
    secrets_burned: 0,
    secrets_shared: 0,
    emails_sent: 0,
    last_login: null,
    locale: null,
    notify_on_reveal: false,
    feature_flags: {},
    ...overrides,
  });
}

/**
 * Creates a "user_deleted_self" role customer (soft-deleted).
 */
export function createDeletedCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    objid: 'd3l3t3d123ab',
    extid: 'ext_d3l3t3d123ab',
    role: 'user_deleted_self',
    email: 'deleted@example.com',
    verified: false,
    active: false,
    last_login: ONE_DAY_EARLIER,
    feature_flags: {},
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Edge Case Factories
// -----------------------------------------------------------------------------

/**
 * Creates a customer with null last_login (never logged in).
 */
export function createNeverLoggedInCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    last_login: null,
    secrets_created: 0,
    secrets_burned: 0,
    secrets_shared: 0,
    emails_sent: 0,
    ...overrides,
  });
}

/**
 * Creates a customer with feature flags enabled.
 */
export function createFeatureFlaggedCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    feature_flags: {
      beta_features: true,
      dark_mode: true,
      api_v3: false,
    },
    ...overrides,
  });
}

/**
 * Creates a contributor customer.
 */
export function createContributorCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    contributor: true,
    feature_flags: {
      contributor_badge: true,
    },
    ...overrides,
  });
}

/**
 * Creates a customer with null locale.
 */
export function createNoLocaleCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    locale: null,
    ...overrides,
  });
}

/**
 * Creates a customer with high activity counters.
 */
export function createHighActivityCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    secrets_created: 1000,
    secrets_burned: 50,
    secrets_shared: 800,
    emails_sent: 500,
    ...overrides,
  });
}

/**
 * Creates an unverified customer.
 */
export function createUnverifiedCustomer(
  overrides?: Partial<CustomerCanonical>
): CustomerCanonical {
  return createCanonicalCustomer({
    verified: false,
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Wire Format Factories (use serializers)
// -----------------------------------------------------------------------------

/**
 * Creates V2 wire format from canonical.
 */
export function createV2WireCustomer(
  canonical?: CustomerCanonical
): V2WireCustomer {
  return toV2WireCustomer(canonical ?? createCanonicalCustomer());
}

/**
 * Creates V3 wire format from canonical.
 */
export function createV3WireCustomer(
  canonical?: CustomerCanonical
): V3WireCustomer {
  return toV3WireCustomer(canonical ?? createCanonicalCustomer());
}

// -----------------------------------------------------------------------------
// Comparison Functions
// -----------------------------------------------------------------------------

/**
 * Compares two canonical customers for equality.
 * Handles Date comparison by converting to timestamps.
 */
export function compareCanonicalCustomer(
  a: CustomerCanonical,
  b: CustomerCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  // String/primitive fields
  const primitiveFields = [
    'objid',
    'extid',
    'role',
    'email',
    'verified',
    'active',
    'secrets_created',
    'secrets_burned',
    'secrets_shared',
    'emails_sent',
    'locale',
    'notify_on_reveal',
  ] as const;

  for (const field of primitiveFields) {
    if (a[field] !== b[field]) {
      differences.push(
        `${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`
      );
    }
  }

  // Optional contributor field
  if (a.contributor !== b.contributor) {
    differences.push(
      `contributor: ${JSON.stringify(a.contributor)} !== ${JSON.stringify(b.contributor)}`
    );
  }

  // Date fields (compare as timestamps)
  const dateFields = ['created', 'updated', 'last_login'] as const;

  for (const field of dateFields) {
    const aVal = a[field];
    const bVal = b[field];
    const aTime = aVal instanceof Date ? aVal.getTime() : aVal;
    const bTime = bVal instanceof Date ? bVal.getTime() : bVal;
    if (aTime !== bTime) {
      differences.push(`${field}: ${aTime} !== ${bTime}`);
    }
  }

  // Feature flags (compare as JSON)
  if (JSON.stringify(a.feature_flags) !== JSON.stringify(b.feature_flags)) {
    differences.push(
      `feature_flags: ${JSON.stringify(a.feature_flags)} !== ${JSON.stringify(b.feature_flags)}`
    );
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}
