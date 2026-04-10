// src/schemas/contracts/custom-domain/index.ts
//
// Custom domain contracts barrel file.
//
// Re-exports brand config, homepage config, api config, and domain-level schemas.
// Consumers import from '@/schemas/contracts/custom-domain' as before.
//
// Architecture: contract -> shape -> API

import { z } from 'zod';
import { customDomainEmailConfigCanonical } from '../email-config';

// Re-export sub-contracts
export {
  brandSettingsCanonical,
  fontFamilyValues,
  cornerStyleValues,
  imagePropsCanonical,
} from './brand-config';
export type {
  BrandSettingsCanonical,
  FontFamily,
  CornerStyle,
  ImagePropsCanonical,
} from './brand-config';

export { homepageConfigCanonical } from './homepage-config';
export type { HomepageConfigCanonical } from './homepage-config';

export { apiConfigCanonical } from './api-config';
export type { ApiConfigCanonical } from './api-config';

// Import for use in customDomainCanonical
import { brandSettingsCanonical } from './brand-config';
import { homepageConfigCanonical } from './homepage-config';
import { apiConfigCanonical } from './api-config';

// ─────────────────────────────────────────────────────────────────────────────
// Domain status enum
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Custom domain status values.
 *
 * @category Contracts
 */
export const domainStatusValues = ['pending', 'active', 'error', 'suspended'] as const;

export type DomainStatus = (typeof domainStatusValues)[number];

/**
 * Domain status enum object for runtime status checks.
 *
 * @category Contracts
 */
export const DomainStatus = {
  PENDING: 'pending',
  ACTIVE: 'active',
  ERROR: 'error',
  SUSPENDED: 'suspended',
} as const;

/**
 * Zod schema for validating domain status values.
 *
 * @category Contracts
 */
export const domainStatusSchema = z.enum(domainStatusValues);

// ─────────────────────────────────────────────────────────────────────────────
// VHost canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical vhost (virtual host) contract.
 *
 * VHost contains DNS and SSL monitoring data from the domain proxy service.
 * Documents the information sent back by Approximated.
 *
 * @category Contracts
 */
export const vhostCanonical = z
  .object({
    /** Proxy service ID. */
    id: z.number().optional(),

    /** Current vhost status. */
    status: z.string().optional(),

    /** Incoming address for the domain. */
    incoming_address: z.string().optional(),

    /** Target backend address. */
    target_address: z.string().optional(),

    /** Target ports configuration. */
    target_ports: z.string().optional(),

    /** Whether the domain is being served by the proxy. */
    apx_hit: z.boolean().optional(),

    /** Whether SSL is active. */
    has_ssl: z.boolean().optional(),

    /** Whether DNS is resolving correctly. */
    is_resolving: z.boolean().optional(),

    /** Vhost creation timestamp. */
    created_at: z.date().optional(),

    /** Last monitoring check timestamp. */
    last_monitored_unix: z.date().optional(),

    /** SSL certificate start date. Optional - external API may omit. */
    ssl_active_from: z.date().nullish(),

    /** SSL certificate expiration date. Optional - external API may omit. */
    ssl_active_until: z.date().nullish(),

    /** Where DNS currently points. */
    dns_pointed_at: z.string().optional(),

    /** Keep-host header setting. */
    keep_host: z.string().nullable(),

    /** Human-readable last monitored time. */
    last_monitored_humanized: z.string().optional(),

    /** Status message from proxy service. */
    status_message: z.string().optional(),

    /** User-facing status message. */
    user_message: z.string().optional(),
  })
  .partial();

// ─────────────────────────────────────────────────────────────────────────────
// Custom domain canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical custom domain record contract.
 *
 * Defines field names and output types (post-parse).
 * No transforms - those are version-specific in shapes.
 *
 * @category Contracts
 * @see {@link "shapes/v2/custom-domain"} - V2 wire format
 * @see {@link "shapes/v3/custom-domain"} - V3 wire format
 */
export const customDomainCanonical = z.object({
  // ─────────────────────────────────────────────────────────────────────────
  // Identity fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Domain ID (internal UUID, primary key). Alias for objid. */
  domainid: z.string(),

  /** External ID (user-facing, format: cd%<id>s). */
  extid: z.string(),

  // ─────────────────────────────────────────────────────────────────────────
  // Ownership
  // ─────────────────────────────────────────────────────────────────────────

  /** Organization objid that owns this domain. */
  org_id: z.string().optional(),

  /** Customer ID (legacy, now equals objid). */
  custid: z.string().nullable(),

  // ─────────────────────────────────────────────────────────────────────────
  // Domain structure (parsed from display_domain via PublicSuffix)
  // ─────────────────────────────────────────────────────────────────────────

  /** Full domain as displayed (e.g., secrets.example.com). */
  display_domain: z.string(),

  /** Base domain without subdomain (e.g., example.com). */
  base_domain: z.string(),

  /** Full subdomain if present (e.g., secrets.example.com). */
  subdomain: z.string().nullable(),

  /** Transit routing domain / subdomain prefix (e.g., secrets). */
  trd: z.string().nullable(),

  /** Top level domain (e.g., com). */
  tld: z.string(),

  /** Second level domain (e.g., example). */
  sld: z.string(),

  /** Whether this is an apex/root domain (no subdomain). */
  is_apex: z.boolean(),

  // ─────────────────────────────────────────────────────────────────────────
  // DNS validation
  // ─────────────────────────────────────────────────────────────────────────

  /** TXT record hostname for domain verification. */
  txt_validation_host: z.string(),

  /** Expected TXT record value for verification. */
  txt_validation_value: z.string(),

  // ─────────────────────────────────────────────────────────────────────────
  // Status fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Domain status (pending, active, error, suspended). */
  status: z.string().optional(),

  /** Whether DNS TXT record is verified. */
  verified: z.boolean(),

  /** Whether DNS A/CNAME record is resolving correctly. */
  resolving: z.boolean().optional(),

  // ─────────────────────────────────────────────────────────────────────────
  // Nested objects
  // ─────────────────────────────────────────────────────────────────────────

  /** Virtual host monitoring data from proxy service. */
  vhost: vhostCanonical.nullable(),

  /** Brand appearance settings. */
  brand: brandSettingsCanonical.nullable(),

  // ─────────────────────────────────────────────────────────────────────────
  // SSO status (computed from CustomDomain::SsoConfig lookup)
  // ─────────────────────────────────────────────────────────────────────────

  /** Whether SSO configuration exists for this domain. */
  sso_configured: z.boolean().optional(),

  /** Whether SSO is enabled (config exists AND enabled flag is true). */
  sso_enabled: z.boolean().optional(),

  // ─────────────────────────────────────────────────────────────────────────
  // Email config status (computed from CustomDomain::MailerConfig lookup)
  // ─────────────────────────────────────────────────────────────────────────

  /** Email configuration for this domain, if any. Null when unconfigured. */
  email_config: customDomainEmailConfigCanonical.nullable().optional(),

  // ─────────────────────────────────────────────────────────────────────────
  // Homepage config (computed from CustomDomain::HomepageConfig lookup)
  // ─────────────────────────────────────────────────────────────────────────

  /** Homepage secrets configuration for this domain, if any. Null when unconfigured. */
  homepage_config: homepageConfigCanonical.nullable().optional(),

  // ─────────────────────────────────────────────────────────────────────────
  // API config (computed from CustomDomain::ApiConfig lookup)
  // ─────────────────────────────────────────────────────────────────────────

  /** API access configuration for this domain, if any. Null when unconfigured. */
  api_config: apiConfigCanonical.nullable().optional(),

  // ─────────────────────────────────────────────────────────────────────────
  // Timestamps
  // ─────────────────────────────────────────────────────────────────────────

  /** Domain creation timestamp. */
  created: z.date(),

  /** Last update timestamp. */
  updated: z.date(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for vhost record. */
export type VHostCanonical = z.infer<typeof vhostCanonical>;

/** TypeScript type for custom domain record. */
export type CustomDomainCanonical = z.infer<typeof customDomainCanonical>;
