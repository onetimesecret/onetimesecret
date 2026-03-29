// src/tests/schemas/shapes/fixtures/organization.fixtures.ts
//
// Organization test fixtures using factory pattern.
// All timestamps use round seconds to survive epoch conversion.

import type { OrganizationCanonical } from '@/schemas/contracts/organization';

// Re-export type for convenience
export type { OrganizationCanonical } from '@/schemas/contracts/organization';

// -----------------------------------------------------------------------------
// Constants for round-second timestamps
// -----------------------------------------------------------------------------

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

/** Base epoch seconds */
const BASE_EPOCH = Math.floor(BASE_TIMESTAMP.getTime() / 1000);

/** One day earlier */
const ONE_DAY_EARLIER_EPOCH = Math.floor(new Date('2024-01-14T10:00:00.000Z').getTime() / 1000);

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
    objid: 'org123abc456',
    extid: 'on%org123abc456',
    display_name: 'Acme Corporation',
    description: 'A test organization for unit tests',
    owner_id: 'cust789xyz',
    contact_email: 'admin@acme.example.com',
    is_default: false,
    planid: 'free',
    created: BASE_EPOCH,
    updated: BASE_EPOCH,
    ...overrides,
  };
}

// -----------------------------------------------------------------------------
// State-Specific Factories
// -----------------------------------------------------------------------------

/**
 * Creates a default organization (auto-created personal workspace).
 * Default orgs cannot be deleted by the user.
 */
export function createDefaultOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    objid: 'org_default_123',
    extid: 'on%org_default_123',
    display_name: 'Personal Workspace',
    description: null,
    is_default: true,
    ...overrides,
  });
}

/**
 * Creates an organization with a paid plan.
 */
export function createPaidOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    objid: 'org_enterprise_456',
    extid: 'on%org_enterprise_456',
    display_name: 'Enterprise Organization',
    description: 'Organization with paid plan',
    planid: 'identity',
    ...overrides,
  });
}

/**
 * Creates an organization with null optional fields.
 */
export function createMinimalOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    objid: 'org_minimal_789',
    extid: 'on%org_minimal_789',
    display_name: 'Minimal Org',
    description: null,
    contact_email: null,
    ...overrides,
  });
}

/**
 * Creates an organization created earlier (for testing timestamps).
 */
export function createOlderOrganization(
  overrides?: Partial<OrganizationCanonical>
): OrganizationCanonical {
  return createCanonicalOrganization({
    objid: 'org_older_abc',
    extid: 'on%org_older_abc',
    display_name: 'Older Organization',
    created: ONE_DAY_EARLIER_EPOCH,
    updated: BASE_EPOCH,
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Wire Format Factories
// -----------------------------------------------------------------------------

/**
 * Wire format type for organization API responses.
 * Matches what organizationSchema expects as input.
 */
export type OrganizationWire = OrganizationCanonical & {
  billing_email?: string | null;
  member_count?: number | null;
  current_user_role?: 'owner' | 'admin' | 'member' | null;
  entitlements?: string[] | null;
  limits?: { teams?: number; members_per_team?: number; custom_domains?: number } | null;
  domain_count?: number | null;
};

/**
 * Creates wire format from canonical, adding API-response fields.
 *
 * @param canonicalOrOverrides - Either a full OrganizationCanonical object,
 *   or partial overrides to apply to the default canonical organization.
 */
export function createWireOrganization(
  canonicalOrOverrides?: OrganizationCanonical | Partial<OrganizationWire>
): OrganizationWire {
  // If overrides have wire-only fields, use as overrides; otherwise treat as canonical
  const hasWireFields = canonicalOrOverrides && (
    'billing_email' in canonicalOrOverrides ||
    'member_count' in canonicalOrOverrides ||
    'current_user_role' in canonicalOrOverrides ||
    'entitlements' in canonicalOrOverrides ||
    'limits' in canonicalOrOverrides ||
    'domain_count' in canonicalOrOverrides
  );

  if (hasWireFields) {
    // Overrides mode: merge with defaults
    const overrides = canonicalOrOverrides as Partial<OrganizationWire>;
    const canonical = createCanonicalOrganization(overrides);
    return {
      ...canonical,
      billing_email: null,
      member_count: 1,
      current_user_role: 'owner',
      entitlements: ['create_secrets', 'view_receipt'],
      limits: {
        teams: 1,
        members_per_team: 5,
        custom_domains: 0,
      },
      domain_count: 0,
      ...overrides,
    };
  }

  // Canonical mode: use as-is or default
  const org = canonicalOrOverrides
    ? createCanonicalOrganization(canonicalOrOverrides as Partial<OrganizationCanonical>)
    : createCanonicalOrganization();

  return {
    ...org,
    billing_email: null,
    member_count: 1,
    current_user_role: 'owner',
    entitlements: ['create_secrets', 'view_receipt'],
    limits: {
      teams: 1,
      members_per_team: 5,
      custom_domains: 0,
    },
    domain_count: 0,
  };
}

/**
 * Creates wire format for a paid organization with entitlements.
 */
export function createWirePaidOrganization(
  canonical?: OrganizationCanonical
): OrganizationWire {
  const org = canonical ?? createPaidOrganization();
  return {
    ...org,
    billing_email: 'billing@enterprise.example.com',
    member_count: 10,
    current_user_role: 'owner',
    entitlements: [
      'create_secrets',
      'view_receipt',
      'api_access',
      'custom_domains',
      'custom_branding',
      'manage_orgs',
      'manage_teams',
      'manage_members',
    ],
    limits: {
      teams: 10,
      members_per_team: 50,
      custom_domains: 5,
    },
    domain_count: 2,
  };
}

// -----------------------------------------------------------------------------
// Billing-Specific Wire Format Factories
// -----------------------------------------------------------------------------

/**
 * Creates wire format for free tier organization (no subscription).
 */
export function createWireFreeOrganization(
  overrides?: Partial<OrganizationWire>
): OrganizationWire {
  return {
    ...createWireOrganization(createCanonicalOrganization({
      objid: 'org_free_123',
      extid: 'on%org_free_123',
      planid: 'free_v1',
    })),
    entitlements: [],
    limits: { teams: 0, members_per_team: 0, custom_domains: 0 },
    ...overrides,
  };
}

/**
 * Creates wire format for single team tier (Identity Plus).
 */
export function createWireSingleTeamOrganization(
  overrides?: Partial<OrganizationWire>
): OrganizationWire {
  return {
    ...createWireOrganization(createCanonicalOrganization({
      objid: 'org_single_123',
      extid: 'on%org_single_123',
      planid: 'identity_plus_v1_monthly',
    })),
    billing_email: 'billing@example.com',
    member_count: 5,
    current_user_role: 'owner',
    entitlements: ['api_access', 'custom_domains', 'custom_branding'],
    limits: { teams: 1, members_per_team: 10, custom_domains: 3 },
    ...overrides,
  };
}

/**
 * Creates wire format for multi team tier (Team Plus).
 */
export function createWireMultiTeamOrganization(
  overrides?: Partial<OrganizationWire>
): OrganizationWire {
  return {
    ...createWireOrganization(createCanonicalOrganization({
      objid: 'org_multi_123',
      extid: 'on%org_multi_123',
      planid: 'team_plus_v1_monthly',
    })),
    billing_email: 'billing@enterprise.example.com',
    member_count: 15,
    current_user_role: 'owner',
    entitlements: [
      'api_access',
      'custom_domains',
      'custom_branding',
      'manage_teams',
      'manage_members',
      'audit_logs',
    ],
    limits: { teams: 5, members_per_team: 25, custom_domains: 10 },
    ...overrides,
  };
}

/**
 * Creates wire format for legacy identity plan (Early Supporter).
 * These customers have single_team tier features but planid is 'identity'.
 */
export function createWireLegacyIdentityOrganization(
  overrides?: Partial<OrganizationWire>
): OrganizationWire {
  return {
    ...createWireOrganization(createCanonicalOrganization({
      objid: 'org_legacy_123',
      extid: 'on%org_legacy_123',
      display_name: 'Early Supporter Org',
      planid: 'identity',
    })),
    billing_email: 'billing@legacy.example.com',
    member_count: 3,
    current_user_role: 'owner',
    entitlements: ['api_access', 'custom_domains', 'custom_branding'],
    limits: { teams: 1, members_per_team: 10, custom_domains: 3 },
    ...overrides,
  };
}

/**
 * Pre-configured wire organization variants for billing tests.
 */
export const wireOrganizations = {
  free: createWireFreeOrganization(),
  singleTeam: createWireSingleTeamOrganization(),
  multiTeam: createWireMultiTeamOrganization(),
  legacyIdentity: createWireLegacyIdentityOrganization(),
};

// -----------------------------------------------------------------------------
// Comparison Functions
// -----------------------------------------------------------------------------

/**
 * Compares two canonical organizations for equality.
 * Handles timestamp comparison as numbers.
 */
export function compareCanonicalOrganization(
  a: OrganizationCanonical,
  b: OrganizationCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  // String fields
  const stringFields = [
    'objid',
    'extid',
    'display_name',
    'owner_id',
    'planid',
  ] as const;

  for (const field of stringFields) {
    if (a[field] !== b[field]) {
      differences.push(
        `${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`
      );
    }
  }

  // Nullable string fields
  const nullableStringFields = ['description', 'contact_email'] as const;

  for (const field of nullableStringFields) {
    if (a[field] !== b[field]) {
      differences.push(
        `${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`
      );
    }
  }

  // Boolean fields
  if (a.is_default !== b.is_default) {
    differences.push(`is_default: ${a.is_default} !== ${b.is_default}`);
  }

  // Number fields (timestamps)
  const numberFields = ['created', 'updated'] as const;

  for (const field of numberFields) {
    if (a[field] !== b[field]) {
      differences.push(`${field}: ${a[field]} !== ${b[field]}`);
    }
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}
