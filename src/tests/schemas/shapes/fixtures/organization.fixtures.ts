// src/tests/schemas/shapes/fixtures/organization.fixtures.ts
//
// Organization test fixtures using factory pattern.
// All timestamps use round seconds to survive epoch conversion.

import type { OrganizationCanonical } from '@/schemas/contracts';
import {
  toV2WireOrganization,
  toV3WireOrganization,
  type V2WireOrganization,
  type V3WireOrganization,
} from '../helpers/serializers';

// Re-export OrganizationCanonical for backward compatibility with existing imports
export type { OrganizationCanonical } from '@/schemas/contracts';

// -----------------------------------------------------------------------------
// Constants for round-second timestamps
// -----------------------------------------------------------------------------

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

/** One day earlier */
const ONE_DAY_EARLIER = new Date('2024-01-14T10:00:00.000Z');

// -----------------------------------------------------------------------------
// Canonical Factories
// -----------------------------------------------------------------------------

/**
 * Creates a canonical organization with sensible defaults.
 * All timestamps are round seconds for epoch conversion safety.
 */
export function createCanonicalOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return {
    // Identity fields - use realistic identifier formats
    identifier: 'org12ab34cd',
    objid: 'org12ab34cd',
    extid: 'on12ab34cd',

    // Core fields
    display_name: 'Acme Corp',
    description: 'A test organization for development',
    owner_id: 'cust12ab34cd',
    contact_email: 'billing@acme.example.com',

    // Status flags
    is_default: false,

    // Plan and billing
    planid: 'free',

    // Timestamps
    created: BASE_TIMESTAMP,
    updated: BASE_TIMESTAMP,

    ...overrides,
  };
}

// -----------------------------------------------------------------------------
// Variant Factories
// -----------------------------------------------------------------------------

/**
 * Creates a default organization (auto-created workspace).
 * Default orgs cannot be deleted and have is_default=true.
 */
export function createDefaultOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    identifier: 'org_default12',
    objid: 'org_default12',
    extid: 'on_default12',
    display_name: 'Personal Workspace',
    description: null,
    is_default: true,
    planid: 'free',
    ...overrides,
  });
}

/**
 * Creates a paid organization with pro plan.
 */
export function createPaidOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    identifier: 'org_paid12ab',
    objid: 'org_paid12ab',
    extid: 'on_paid12ab',
    display_name: 'Enterprise Solutions',
    description: 'Premium organization with paid features',
    planid: 'pro',
    contact_email: 'enterprise@example.com',
    ...overrides,
  });
}

/**
 * Creates an organization with minimal fields (nulls where allowed).
 */
export function createMinimalOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    identifier: 'org_min12345',
    objid: 'org_min12345',
    extid: 'on_min12345',
    display_name: 'Minimal Org',
    description: null,
    contact_email: null,
    is_default: false,
    planid: 'free',
    ...overrides,
  });
}

/**
 * Creates an organization with long display name and description.
 */
export function createVerboseOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    identifier: 'org_verbose12',
    objid: 'org_verbose12',
    extid: 'on_verbose12',
    display_name: 'Very Long Organization Name That Tests Display Limits',
    description:
      'This is a very long description that tests the limits of the description field. ' +
      'It contains multiple sentences and should be properly handled by all serializers. ' +
      'Organizations may have detailed descriptions explaining their purpose.',
    contact_email: 'verbose.organization.contact@example.com',
    ...overrides,
  });
}

/**
 * Creates an older organization (created one day earlier).
 */
export function createOldOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    identifier: 'org_old123ab',
    objid: 'org_old123ab',
    extid: 'on_old123ab',
    display_name: 'Legacy Organization',
    created: ONE_DAY_EARLIER,
    updated: BASE_TIMESTAMP,
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Wire Format Factories (use serializers)
// -----------------------------------------------------------------------------

/**
 * Creates V2 wire format from canonical.
 */
export function createV2WireOrganization(
  canonical?: OrganizationCanonical
): V2WireOrganization {
  return toV2WireOrganization(canonical ?? createCanonicalOrganization());
}

/**
 * Creates V3 wire format from canonical.
 */
export function createV3WireOrganization(
  canonical?: OrganizationCanonical
): V3WireOrganization {
  return toV3WireOrganization(canonical ?? createCanonicalOrganization());
}

// -----------------------------------------------------------------------------
// Comparison Functions
// -----------------------------------------------------------------------------

/**
 * Compares two canonical organizations for equality.
 * Handles Date comparison by converting to timestamps.
 */
export function compareCanonicalOrganization(
  a: OrganizationCanonical,
  b: OrganizationCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  // String/primitive fields
  const primitiveFields = [
    'identifier',
    'objid',
    'extid',
    'display_name',
    'description',
    'owner_id',
    'contact_email',
    'is_default',
    'planid',
  ] as const;

  for (const field of primitiveFields) {
    if (a[field] !== b[field]) {
      differences.push(
        `${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`
      );
    }
  }

  // Date fields (compare as timestamps)
  const dateFields = ['created', 'updated'] as const;

  for (const field of dateFields) {
    const aVal = a[field];
    const bVal = b[field];
    const aTime = aVal instanceof Date ? aVal.getTime() : aVal;
    const bTime = bVal instanceof Date ? bVal.getTime() : bVal;
    if (aTime !== bTime) {
      differences.push(`${field}: ${aTime} !== ${bTime}`);
    }
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}
