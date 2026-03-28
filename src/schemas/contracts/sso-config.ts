// src/schemas/contracts/sso-config.ts
//
// DomainSsoConfig contracts defining field names and wire format types.
// Shapes transform these to runtime types (e.g., timestamps -> Date).
//
// Architecture: contract -> shape -> API

/**
 * Per-Domain SSO Configuration contracts.
 *
 * Stores SSO/OIDC credentials for custom domains that manage their own
 * identity provider connections. This enables multi-tenant SSO where each
 * domain can configure their own Entra ID, Google Workspace, or
 * generic OIDC provider.
 *
 * Design Decisions:
 *
 * 1. One-to-One with Domain: Each custom domain has at most one SSO
 *    config. The domain_id field is the identifier.
 *
 * 2. Masked Credentials: client_secret is never exposed in API responses.
 *    Instead, client_secret_masked provides a hint (e.g., "••••1234").
 *
 * 3. Provider Types: Supports 'oidc' (generic), 'entra_id', 'google', and
 *    'github'. Each has slightly different options (e.g., Entra requires
 *    tenant_id, OIDC requires issuer for discovery).
 *
 * 4. Domain Allowlist: The allowed_domains list restricts which email
 *    domains can authenticate via this SSO config. Empty list means no
 *    restriction (any domain allowed).
 *
 * @module contracts/sso-config
 * @category Contracts
 * @see {@link "shapes/sso-config"} - Shapes with transforms
 */

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Provider type schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Supported SSO provider types.
 *
 * Maps to OmniAuth strategies:
 * - oidc: omniauth-openid-connect (generic OIDC with discovery)
 * - entra_id: omniauth-entra-id (Microsoft Entra ID / Azure AD)
 * - google: omniauth-google-oauth2 (Google Workspace)
 * - github: omniauth-github (GitHub OAuth)
 *
 * @category Contracts
 */
export const ssoProviderTypeSchema = z.enum(['oidc', 'entra_id', 'google', 'github']);

export type SsoProviderType = z.infer<typeof ssoProviderTypeSchema>;

/**
 * Provider metadata for UI behavior.
 *
 * Mirrors PROVIDER_METADATA in lib/onetime/models/domain_sso_config.rb.
 * Used by forms to determine when domain filter field should be shown/required.
 */
export const SSO_PROVIDER_METADATA: Record<SsoProviderType, {
  requiresDomainFilter: boolean;
  idpControlsAccess: boolean;
  description: string;
}> = {
  oidc: {
    requiresDomainFilter: false,
    idpControlsAccess: true,
    description: 'Generic OIDC provider with user assignment',
  },
  entra_id: {
    requiresDomainFilter: false,
    idpControlsAccess: true,
    description: 'Microsoft Entra ID controls access via app assignment',
  },
  google: {
    requiresDomainFilter: false,
    idpControlsAccess: true,
    description: 'Google Workspace controls access via app assignment',
  },
  github: {
    requiresDomainFilter: true,
    idpControlsAccess: false,
    description: 'GitHub OAuth allows any user — domain filter recommended',
  },
} as const;

// ─────────────────────────────────────────────────────────────────────────────
// Canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical DomainSsoConfig contract schema.
 *
 * Defines field names matching the Ruby DomainSsoConfig model and wire format.
 * Shapes transform timestamps (number -> Date) for runtime use.
 *
 * Note: client_id and client_secret are encrypted at rest in the backend.
 * API responses use client_secret_masked to indicate presence without exposing
 * the actual secret.
 *
 * @see lib/onetime/models/domain_sso_config.rb - Backend model
 * @category Contracts
 */
export const domainSsoConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.identifier). */
  domain_id: z.string(),

  /** SSO provider type (oidc, entra_id, google, github). */
  provider_type: ssoProviderTypeSchema,

  /** Whether SSO is enabled for this organization. */
  enabled: z.boolean(),

  /** Human-readable name for UI display (e.g., "Acme Corp SSO"). */
  display_name: z.string(),

  /** OAuth client ID (encrypted at rest). */
  client_id: z.string(),

  /**
   * Masked client secret for display (e.g., "••••1234").
   * Never contains the actual secret value.
   */
  client_secret_masked: z.string(),

  /**
   * Azure AD tenant ID.
   *
   * Provider-specific field requirements:
   *
   *   | provider_type | tenant_id | issuer   |
   *   |---------------|-----------|----------|
   *   | entra_id      | required  | -        |
   *   | oidc          | -         | required |
   *   | google        | -         | -        |
   *   | github        | -         | -        |
   *
   * Google and GitHub use well-known OAuth endpoints, so neither
   * tenant_id nor issuer is needed. Universal fields (client_id,
   * display_name) are always required regardless of provider.
   */
  tenant_id: z.string().nullable(),

  /**
   * OIDC issuer URL for discovery endpoint.
   *
   * Required only for 'oidc' provider type. See tenant_id docs above
   * for full provider-specific field requirements matrix.
   */
  issuer: z.string().nullable(),

  /**
   * Email domain allowlist.
   * Users must have email addresses in one of these domains to authenticate.
   * Empty array means no domain restriction.
   */
  allowed_domains: z.array(z.string()),

  /**
   * Whether app-side domain filtering is recommended for this provider.
   * True for providers without IdP-side user assignment (e.g., GitHub).
   * Read-only, computed from provider_type.
   */
  requires_domain_filter: z.boolean(),

  /**
   * Whether the IdP controls access via user/app assignment.
   * When true, app-side domain filtering is typically redundant.
   * Read-only, computed from provider_type.
   */
  idp_controls_access: z.boolean(),

  /** Configuration creation timestamp (Unix epoch seconds). */
  created_at: z.number(),

  /** Last update timestamp (Unix epoch seconds). */
  updated_at: z.number(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for DomainSsoConfig wire format. */
export type DomainSsoConfigCanonical = z.infer<typeof domainSsoConfigCanonical>;

// ─────────────────────────────────────────────────────────────────────────────
// Deprecated aliases (backward compatibility)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @deprecated Use domainSsoConfigCanonical. SSO config moved from per-org to per-domain.
 */
export const orgSsoConfigCanonical = domainSsoConfigCanonical;

/**
 * @deprecated Use DomainSsoConfigCanonical. SSO config moved from per-org to per-domain.
 */
export type OrgSsoConfigCanonical = DomainSsoConfigCanonical;

// ─────────────────────────────────────────────────────────────────────────────
// Request payload schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Create or update SSO configuration request payload schema.
 *
 * Used for PUT /api/domains/:domain_extid/sso
 *
 * Fields:
 * - provider_type: Required, one of the supported providers
 * - display_name: Required, human-readable name
 * - client_id: Required, OAuth client ID
 * - client_secret: Required for create, optional for update (omit to keep existing)
 * - tenant_id: Required for entra_id provider
 * - issuer: Required for oidc provider
 * - allowed_domains: Optional domain allowlist
 * - enabled: Optional, defaults to false
 *
 * @category Contracts
 */
export const createOrUpdateSsoConfigPayloadSchema = z.object({
  /** SSO provider type (oidc, entra_id, google, github). */
  provider_type: ssoProviderTypeSchema,

  /** Human-readable name for UI display. */
  display_name: z.string().min(1, 'Display name is required').max(100, 'Display name is too long'),

  /** OAuth client ID. */
  client_id: z.string().min(1, 'Client ID is required'),

  /**
   * OAuth client secret.
   * Required for create, optional for update (omit to keep existing secret).
   */
  client_secret: z.string().optional(),

  /**
   * Azure AD tenant ID.
   *
   * Conditionally required based on provider_type:
   *   - entra_id: REQUIRED (identifies Azure AD tenant)
   *   - oidc:     not used (uses issuer instead)
   *   - google:   not used (well-known endpoints)
   *   - github:   not used (well-known endpoints)
   *
   * Typed as optional because it's only required for entra_id.
   * Strict schemas enforce this via superRefine validation.
   */
  tenant_id: z.string().optional(),

  /**
   * OIDC issuer URL for auto-discovery.
   *
   * Conditionally required based on provider_type:
   *   - oidc:     REQUIRED (e.g., https://login.example.com)
   *   - entra_id: not used (uses tenant_id instead)
   *   - google:   not used (well-known endpoints)
   *   - github:   not used (well-known endpoints)
   *
   * Typed as optional because it's only required for oidc.
   * Strict schemas enforce this via superRefine validation.
   */
  issuer: z.string().url('Issuer must be a valid URL').optional(),

  /** Email domain allowlist. Empty array means no restriction. */
  allowed_domains: z.array(z.string()).optional(),

  /** Whether SSO is enabled. Defaults to false. */
  enabled: z.boolean().optional(),
});

export type CreateOrUpdateSsoConfigPayload = z.infer<typeof createOrUpdateSsoConfigPayloadSchema>;

/**
 * Validation refinement for provider-specific requirements.
 *
 * - Entra ID requires tenant_id
 * - OIDC requires issuer
 *
 * Use this schema when strict validation is needed.
 */
export const createOrUpdateSsoConfigPayloadStrictSchema = createOrUpdateSsoConfigPayloadSchema.superRefine(
  (data, ctx) => {
    if (data.provider_type === 'entra_id' && !data.tenant_id) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'tenant_id is required for Entra ID provider',
        path: ['tenant_id'],
      });
    }

    if (data.provider_type === 'oidc' && !data.issuer) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'issuer is required for OIDC provider',
        path: ['issuer'],
      });
    }
  }
);

export type CreateOrUpdateSsoConfigPayloadStrict = z.infer<typeof createOrUpdateSsoConfigPayloadStrictSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PATCH payload schema (partial update - all fields optional)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * PATCH SSO configuration request payload schema.
 *
 * All fields are optional for partial update semantics.
 * Only provided fields are updated; omitted fields preserve existing values.
 *
 * @category Contracts
 */
export const patchSsoConfigPayloadSchema = z.object({
  /** SSO provider type (oidc, entra_id, google, github). */
  provider_type: ssoProviderTypeSchema.optional(),

  /** Human-readable name for UI display. */
  display_name: z.string().min(1, 'Display name is required').max(100, 'Display name is too long').optional(),

  /** OAuth client ID. */
  client_id: z.string().min(1, 'Client ID is required').optional(),

  /**
   * OAuth client secret.
   * Optional for update - omit to preserve existing secret.
   */
  client_secret: z.string().optional(),

  /** Azure AD tenant ID (required for entra_id only). See createOrUpdateSsoConfigPayloadSchema. */
  tenant_id: z.string().optional(),

  /** OIDC issuer URL (required for oidc only). See createOrUpdateSsoConfigPayloadSchema. */
  issuer: z.string().url('Issuer must be a valid URL').optional(),

  /** Email domain allowlist. Empty array means no restriction. */
  allowed_domains: z.array(z.string()).optional(),

  /** Whether SSO is enabled. */
  enabled: z.boolean().optional(),
});

export type PatchSsoConfigPayload = z.infer<typeof patchSsoConfigPayloadSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT payload schema (full replacement - required fields enforced)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * PUT SSO configuration request payload schema.
 *
 * Full replacement semantics - client_secret is always required.
 * The request body IS the new state.
 *
 * @category Contracts
 */
export const putSsoConfigPayloadSchema = z.object({
  /** SSO provider type (oidc, entra_id, google, github). */
  provider_type: ssoProviderTypeSchema,

  /** Human-readable name for UI display. */
  display_name: z.string().min(1, 'Display name is required').max(100, 'Display name is too long'),

  /** OAuth client ID. */
  client_id: z.string().min(1, 'Client ID is required'),

  /** OAuth client secret. Required for PUT (full replacement). */
  client_secret: z.string().min(1, 'Client secret is required'),

  /** Azure AD tenant ID (required for entra_id only). See createOrUpdateSsoConfigPayloadSchema. */
  tenant_id: z.string().optional(),

  /** OIDC issuer URL (required for oidc only). See createOrUpdateSsoConfigPayloadSchema. */
  issuer: z.string().url('Issuer must be a valid URL').optional(),

  /** Email domain allowlist. Empty array means no restriction. */
  allowed_domains: z.array(z.string()).optional(),

  /** Whether SSO is enabled. Defaults to false. */
  enabled: z.boolean().optional(),
});

/**
 * PUT SSO config payload with provider-specific validation.
 *
 * - Entra ID requires tenant_id
 * - OIDC requires issuer
 */
export const putSsoConfigPayloadStrictSchema = putSsoConfigPayloadSchema.superRefine(
  (data, ctx) => {
    if (data.provider_type === 'entra_id' && !data.tenant_id) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'tenant_id is required for Entra ID provider',
        path: ['tenant_id'],
      });
    }

    if (data.provider_type === 'oidc' && !data.issuer) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'issuer is required for OIDC provider',
        path: ['issuer'],
      });
    }
  }
);

export type PutSsoConfigPayload = z.infer<typeof putSsoConfigPayloadSchema>;
export type PutSsoConfigPayloadStrict = z.infer<typeof putSsoConfigPayloadStrictSchema>;
