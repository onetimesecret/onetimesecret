// src/schemas/contracts/custom-domain.ts
// @see src/tests/composables/useDomainsManager.spec.ts - Test fixtures for domain schema
//
// Canonical custom domain record schema - field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

/**
 * Custom domain record contracts defining field names and output types.
 *
 * Custom domains allow organizations to serve secrets from their own domains
 * (e.g., secrets.example.com). These canonical schemas define the "what"
 * (field names and final types) without the "how" (wire-format transforms).
 *
 * Domain terminology (from PublicSuffix parsing):
 * - tld: Top level domain (e.g., .org in mozilla.org)
 * - sld: Second level domain (e.g., mozilla in mozilla.org)
 * - trd: Transit routing domain/subdomain (e.g., www in www.mozilla.org)
 * - base_domain: sld + tld (e.g., mozilla.org)
 * - subdomain: Full subdomain including trd (e.g., www.mozilla.org)
 *
 * Version-specific shapes in `shapes/v2/custom-domain/` and `shapes/v3/custom-domain.ts`
 * extend these with appropriate transforms for each API version.
 *
 * @module contracts/custom-domain
 * @category Contracts
 * @see {@link "shapes/v2/custom-domain"} - V2 wire format with string transforms
 * @see {@link "shapes/v3/custom-domain"} - V3 wire format with native types
 */

import { z } from 'zod';
import { customDomainEmailConfigCanonical } from './email-config';

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
// Brand settings canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Font family values for brand settings.
 *
 * @category Contracts
 */
export const fontFamilyValues = ['sans', 'serif', 'mono'] as const;
export type FontFamily = (typeof fontFamilyValues)[number];

/**
 * Corner style values for brand settings.
 *
 * @category Contracts
 */
export const cornerStyleValues = ['rounded', 'pill', 'square'] as const;
export type CornerStyle = (typeof cornerStyleValues)[number];

/**
 * Canonical brand settings contract.
 *
 * Brand settings control the visual appearance and behavior of the
 * custom domain's secret sharing interface.
 *
 * @category Contracts
 */
export const brandSettingsCanonical = z
  .object({
    /** Primary brand color (hex format, e.g., #dc4a22). */
    primary_color: z
      .string()
      .regex(/^#[0-9A-Fa-f]{6}$/i)
      .default('#dc4a22'),

    /** Legacy color field (deprecated). */
    colour: z.string().optional(),

    /** Instructions shown before secret reveal. */
    instructions_pre_reveal: z.string().nullish(),

    /** Instructions shown during secret reveal. */
    instructions_reveal: z.string().nullish(),

    /** Instructions shown after secret reveal. */
    instructions_post_reveal: z.string().nullish(),

    /** Brand description. */
    description: z.string().optional(),

    /** Whether button text should be light colored. */
    button_text_light: z.boolean().default(false),

    /** Whether public homepage is allowed. */
    allow_public_homepage: z.boolean().default(false),

    /** Whether public API access is allowed. */
    allow_public_api: z.boolean().default(false),

    /** Font family for the interface. */
    font_family: z.enum(fontFamilyValues).default('sans'),

    /** Corner style for UI elements. */
    corner_style: z.enum(cornerStyleValues).default('rounded'),

    /** Locale/language code. */
    locale: z.string().default('en'),

    /** Default TTL for secrets (seconds). */
    default_ttl: z.number().nullish(),

    /** Whether passphrase is required by default. */
    passphrase_required: z.boolean().default(false),

    /** Whether email notifications are enabled by default. */
    notify_enabled: z.boolean().default(false),
  })
  .partial();

/**
 * Canonical image properties contract.
 *
 * Used for logo and icon image metadata.
 *
 * @category Contracts
 */
export const imagePropsCanonical = z
  .object({
    /** Base64 encoded image data. */
    encoded: z.string().optional(),

    /** MIME content type (e.g., image/png). */
    content_type: z.string().optional(),

    /** Original filename. */
    filename: z.string().optional(),

    /** File size in bytes. */
    bytes: z.number().optional(),

    /** Image width in pixels. */
    width: z.number().optional(),

    /** Image height in pixels. */
    height: z.number().optional(),

    /** Width/height aspect ratio. */
    ratio: z.number().optional(),
  })
  .partial();

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
 * Custom domain records track:
 * - Identity: identifier, domainid (UUID), extid (user-facing ID)
 * - Domain structure: display_domain, base_domain, subdomain, tld, sld, trd
 * - Ownership: org_id (Organization objid), custid (legacy)
 * - DNS validation: txt_validation_host, txt_validation_value
 * - Status: status, verified, resolving
 * - Nested objects: vhost (monitoring), brand (appearance)
 * - Timestamps: created, updated
 *
 * Note: The is_apex field indicates whether this is an apex/root domain
 * (no subdomain) vs a subdomain configuration.
 *
 * @category Contracts
 * @see {@link "shapes/v2/custom-domain".customDomainSchema} - V2 wire format
 * @see {@link "shapes/v3/custom-domain".customDomainSchema} - V3 wire format
 *
 * @example
 * ```typescript
 * // Extend in version-specific shapes
 * const customDomainV3 = customDomainCanonical.extend({
 *   created: transforms.fromNumber.toDate,
 *   updated: transforms.fromNumber.toDate,
 * });
 *
 * // Derive TypeScript type
 * type CustomDomain = z.infer<typeof customDomainCanonical>;
 * ```
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

/** TypeScript type for brand settings. */
export type BrandSettingsCanonical = z.infer<typeof brandSettingsCanonical>;

/** TypeScript type for image properties. */
export type ImagePropsCanonical = z.infer<typeof imagePropsCanonical>;

/** TypeScript type for vhost record. */
export type VHostCanonical = z.infer<typeof vhostCanonical>;

/** TypeScript type for custom domain record. */
export type CustomDomainCanonical = z.infer<typeof customDomainCanonical>;
