// src/tests/schemas/shapes/fixtures/custom-domain.fixtures.ts
//
// Custom domain test fixtures using factory pattern.
// All timestamps use round seconds to survive epoch conversion.
//
// CustomDomain is Tier 3 (most complex) due to:
// - Domain parsing fields (tld, sld, trd, subdomain)
// - DNS validation (txt_validation_host, txt_validation_value)
// - Nested objects (brand, vhost)
// - Verification status (verified, resolving)

import {
  toV2WireCustomDomain,
  toV3WireCustomDomain,
  type V2WireCustomDomain,
  type V3WireCustomDomain,
} from '../helpers/serializers';

// -----------------------------------------------------------------------------
// Canonical Type (post-transform representation)
// -----------------------------------------------------------------------------

/**
 * Canonical representation of a CustomDomain after parsing.
 * All timestamps are Date objects, booleans are native.
 */
export interface CustomDomainCanonical {
  // Identity fields
  identifier: string;
  domainid: string;
  extid: string;

  // Ownership
  custid: string | null;

  // Domain structure (from PublicSuffix parsing)
  display_domain: string;
  base_domain: string;
  subdomain: string | null;
  trd: string | null; // Transit routing domain (subdomain part)
  tld: string; // Top level domain (e.g., "com", "co.uk")
  sld: string; // Second level domain (e.g., "example")

  // Domain type
  is_apex: boolean;

  // Verification status
  verified: boolean;

  // DNS validation
  txt_validation_host: string;
  txt_validation_value: string;

  // Nested objects
  vhost: VHostCanonical | null;
  brand: BrandSettingsCanonical | null;

  // Timestamps
  created: Date;
  updated: Date;
}

/**
 * Canonical representation of VHost (domain monitoring data).
 */
export interface VHostCanonical {
  target_address?: string;
  target_ports?: string;
  target_cname?: string;
  apx_hit?: boolean;
  has_ssl?: boolean;
  is_resolving?: boolean;
  status_message?: string;
  created_at?: Date;
  last_monitored_unix?: Date;
  ssl_active_from?: Date | null;
  ssl_active_until?: Date | null;
}

/**
 * Canonical representation of BrandSettings.
 */
export interface BrandSettingsCanonical {
  primary_color?: string;
  colour?: string;
  instructions_pre_reveal?: string | null;
  instructions_reveal?: string | null;
  instructions_post_reveal?: string | null;
  description?: string;
  button_text_light?: boolean;
  allow_public_homepage?: boolean;
  allow_public_api?: boolean;
  font_family?: 'sans' | 'serif' | 'mono';
  corner_style?: 'rounded' | 'pill' | 'square';
  locale?: string;
  default_ttl?: number | null;
  passphrase_required?: boolean;
  notify_enabled?: boolean;
}

// -----------------------------------------------------------------------------
// Constants for round-second timestamps
// -----------------------------------------------------------------------------

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

/** One day earlier */
const ONE_DAY_EARLIER = new Date('2024-01-14T10:00:00.000Z');

/** SSL validity period */
const SSL_ACTIVE_FROM = new Date('2024-01-01T00:00:00.000Z');
const SSL_ACTIVE_UNTIL = new Date('2025-01-01T00:00:00.000Z');

// -----------------------------------------------------------------------------
// Default nested objects
// -----------------------------------------------------------------------------

/**
 * Creates default VHost settings.
 */
export function createCanonicalVHost(
  overrides?: Partial<VHostCanonical>
): VHostCanonical {
  return {
    target_address: '192.0.2.1',
    target_ports: '443',
    apx_hit: true,
    has_ssl: true,
    is_resolving: true,
    status_message: 'Active',
    created_at: ONE_DAY_EARLIER,
    last_monitored_unix: BASE_TIMESTAMP,
    ssl_active_from: SSL_ACTIVE_FROM,
    ssl_active_until: SSL_ACTIVE_UNTIL,
    ...overrides,
  };
}

/**
 * Creates default BrandSettings.
 */
export function createCanonicalBrandSettings(
  overrides?: Partial<BrandSettingsCanonical>
): BrandSettingsCanonical {
  return {
    primary_color: '#dc4a22',
    button_text_light: false,
    allow_public_homepage: false,
    allow_public_api: false,
    font_family: 'sans',
    corner_style: 'rounded',
    locale: 'en',
    passphrase_required: false,
    notify_enabled: false,
    ...overrides,
  };
}

// -----------------------------------------------------------------------------
// Canonical Factories
// -----------------------------------------------------------------------------

/**
 * Creates a canonical custom domain with sensible defaults.
 * Represents a verified apex domain (example.com).
 */
export function createCanonicalCustomDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return {
    // Identity fields - use realistic identifier formats
    identifier: 'cd12ab34cd56',
    domainid: 'cd12ab34cd56',
    extid: 'cd12ab34cd56',

    // Ownership
    custid: 'cust12ab34cd',

    // Domain structure (apex domain)
    display_domain: 'secrets.example.com',
    base_domain: 'example.com',
    subdomain: 'secrets.example.com',
    trd: 'secrets',
    tld: 'com',
    sld: 'example',

    // Domain type
    is_apex: false,

    // Verification status
    verified: true,

    // DNS validation
    txt_validation_host: '_onetime-challenge.secrets.example.com',
    txt_validation_value: 'ots-verify-abc123def456',

    // Nested objects
    vhost: createCanonicalVHost(),
    brand: createCanonicalBrandSettings(),

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
 * Creates a verified domain (DNS validation complete).
 */
export function createVerifiedDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_verified12',
    domainid: 'cd_verified12',
    extid: 'cd_verified12',
    verified: true,
    vhost: createCanonicalVHost({
      is_resolving: true,
      has_ssl: true,
    }),
    ...overrides,
  });
}

/**
 * Creates a pending domain (awaiting DNS validation).
 */
export function createPendingDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_pending123',
    domainid: 'cd_pending123',
    extid: 'cd_pending123',
    verified: false,
    vhost: null, // No vhost until verified
    brand: null, // No brand settings until verified
    ...overrides,
  });
}

/**
 * Creates a subdomain domain (e.g., secrets.example.com).
 */
export function createSubdomainDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_subdomain1',
    domainid: 'cd_subdomain1',
    extid: 'cd_subdomain1',
    display_domain: 'secrets.example.com',
    base_domain: 'example.com',
    subdomain: 'secrets.example.com',
    trd: 'secrets',
    tld: 'com',
    sld: 'example',
    is_apex: false,
    txt_validation_host: '_onetime-challenge.secrets.example.com',
    ...overrides,
  });
}

/**
 * Creates an apex domain (e.g., example.com).
 */
export function createApexDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_apex12345',
    domainid: 'cd_apex12345',
    extid: 'cd_apex12345',
    display_domain: 'example.com',
    base_domain: 'example.com',
    subdomain: null,
    trd: null,
    tld: 'com',
    sld: 'example',
    is_apex: true,
    txt_validation_host: '_onetime-challenge.example.com',
    ...overrides,
  });
}

/**
 * Creates a domain with custom brand settings.
 */
export function createBrandedDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_branded12',
    domainid: 'cd_branded12',
    extid: 'cd_branded12',
    brand: createCanonicalBrandSettings({
      primary_color: '#336699',
      button_text_light: true,
      allow_public_homepage: true,
      font_family: 'serif',
      corner_style: 'pill',
      instructions_pre_reveal: 'Please enter the passphrase to reveal your secret.',
      locale: 'de',
    }),
    ...overrides,
  });
}

/**
 * Creates a domain with complex TLD (e.g., .co.uk).
 */
export function createComplexTldDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_couk12345',
    domainid: 'cd_couk12345',
    extid: 'cd_couk12345',
    display_domain: 'secrets.example.co.uk',
    base_domain: 'example.co.uk',
    subdomain: 'secrets.example.co.uk',
    trd: 'secrets',
    tld: 'co.uk',
    sld: 'example',
    is_apex: false,
    txt_validation_host: '_onetime-challenge.secrets.example.co.uk',
    ...overrides,
  });
}

/**
 * Creates a minimal domain (null nested objects).
 */
export function createMinimalDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_minimal12',
    domainid: 'cd_minimal12',
    extid: 'cd_minimal12',
    custid: null,
    subdomain: null,
    trd: null,
    vhost: null,
    brand: null,
    ...overrides,
  });
}

/**
 * Creates an older domain (different created/updated times).
 */
export function createOldDomain(
  overrides?: Partial<CustomDomainCanonical>
): CustomDomainCanonical {
  return createCanonicalCustomDomain({
    identifier: 'cd_old1234ab',
    domainid: 'cd_old1234ab',
    extid: 'cd_old1234ab',
    display_domain: 'legacy.example.com',
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
export function createV2WireCustomDomain(
  canonical?: CustomDomainCanonical
): V2WireCustomDomain {
  return toV2WireCustomDomain(canonical ?? createCanonicalCustomDomain());
}

/**
 * Creates V3 wire format from canonical.
 */
export function createV3WireCustomDomain(
  canonical?: CustomDomainCanonical
): V3WireCustomDomain {
  return toV3WireCustomDomain(canonical ?? createCanonicalCustomDomain());
}

// -----------------------------------------------------------------------------
// Comparison Functions
// -----------------------------------------------------------------------------

/**
 * Compares two canonical custom domains for equality.
 * Handles Date comparison by converting to timestamps.
 * Handles nested object comparison.
 */
export function compareCanonicalCustomDomain(
  a: CustomDomainCanonical,
  b: CustomDomainCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  // String/primitive fields
  const primitiveFields = [
    'identifier',
    'domainid',
    'extid',
    'custid',
    'display_domain',
    'base_domain',
    'subdomain',
    'trd',
    'tld',
    'sld',
    'is_apex',
    'verified',
    'txt_validation_host',
    'txt_validation_value',
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

  // Nested objects - simplified comparison
  if ((a.vhost === null) !== (b.vhost === null)) {
    differences.push(`vhost: ${a.vhost === null ? 'null' : 'object'} !== ${b.vhost === null ? 'null' : 'object'}`);
  }

  if ((a.brand === null) !== (b.brand === null)) {
    differences.push(`brand: ${a.brand === null ? 'null' : 'object'} !== ${b.brand === null ? 'null' : 'object'}`);
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}
