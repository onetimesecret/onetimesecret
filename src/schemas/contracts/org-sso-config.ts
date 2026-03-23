// src/schemas/contracts/org-sso-config.ts
//
// OrgSsoConfig contracts defining field names and wire format types.
// Shapes transform these to runtime types (e.g., timestamps -> Date).
//
// Architecture: contract -> shape -> API

/**
 * Per-Organization SSO Configuration contracts.
 *
 * Stores SSO/OIDC credentials for organizations that manage their own
 * identity provider connections. This enables multi-tenant SSO where each
 * organization can configure their own Entra ID, Google Workspace, or
 * generic OIDC provider.
 *
 * Design Decisions:
 *
 * 1. One-to-One with Organization: Each organization has at most one SSO
 *    config. The org_id field is the identifier.
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
 * @module contracts/org-sso-config
 * @category Contracts
 * @see {@link "shapes/organizations/org-sso-config"} - Shapes with transforms
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

// ─────────────────────────────────────────────────────────────────────────────
// Canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical OrgSsoConfig contract schema.
 *
 * Defines field names matching the Ruby OrgSsoConfig model and wire format.
 * Shapes transform timestamps (number -> Date) for runtime use.
 *
 * Note: client_id and client_secret are encrypted at rest in the backend.
 * API responses use client_secret_masked to indicate presence without exposing
 * the actual secret.
 *
 * @see lib/onetime/models/org_sso_config.rb - Backend model
 * @category Contracts
 */
export const orgSsoConfigCanonical = z.object({
  /** Organization ID (references Organization.objid). */
  org_id: z.string(),

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

  /** Azure AD tenant ID (required for Entra ID provider). */
  tenant_id: z.string().nullable(),

  /** OIDC issuer URL for discovery endpoint (required for OIDC provider). */
  issuer: z.string().nullable(),

  /**
   * Email domain allowlist.
   * Users must have email addresses in one of these domains to authenticate.
   * Empty array means no domain restriction.
   */
  allowed_domains: z.array(z.string()),

  /** Configuration creation timestamp (Unix epoch seconds). */
  created_at: z.number(),

  /** Last update timestamp (Unix epoch seconds). */
  updated_at: z.number(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for OrgSsoConfig wire format. */
export type OrgSsoConfigCanonical = z.infer<typeof orgSsoConfigCanonical>;

// ─────────────────────────────────────────────────────────────────────────────
// Request payload schemas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Create or update SSO configuration request payload schema.
 *
 * Used for PUT /api/organizations/:org_id/sso-config
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

  /** Azure AD tenant ID (required for Entra ID provider). */
  tenant_id: z.string().optional(),

  /** OIDC issuer URL (required for OIDC provider). */
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

  /** Azure AD tenant ID (required for Entra ID provider). */
  tenant_id: z.string().optional(),

  /** OIDC issuer URL (required for OIDC provider). */
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

  /** Azure AD tenant ID (required for Entra ID provider). */
  tenant_id: z.string().optional(),

  /** OIDC issuer URL (required for OIDC provider). */
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
