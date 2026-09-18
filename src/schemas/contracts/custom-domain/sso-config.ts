// src/schemas/contracts/custom-domain/sso-config.ts
//
// CustomDomain::SsoConfig contracts defining field names and wire format types.
// Shapes transform these to runtime types (e.g., timestamps -> Date).
//
// Architecture: contract -> shape -> API

/**
 * Per-Domain SSO Configuration contracts.
 *
 * Stores SSO/OIDC credentials for custom domains that manage their own
 * identity provider connections. This enables multi-tenant SSO where each
 * domain can configure their own Entra ID or generic OIDC provider.
 *
 * Design Decisions:
 *
 * 1. One-to-One with Domain: Each custom domain has at most one SSO
 *    config. The domain_id field is the identifier.
 *
 * 2. Masked Credentials: client_secret is never exposed in API responses.
 *    Instead, client_secret_masked provides a hint (e.g., "••••1234").
 *
 * 3. Provider Types: Supports 'oidc' (generic), 'entra_id' and 'saml'.
 *    Every tenant provider must carry a tenant-distinguishing issuer:
 *    identity partitioning is keyed (provider, issuer, uid), so issuerless
 *    providers (GitHub is plain OAuth2; Google has one global issuer)
 *    cannot satisfy per-tenant isolation and are refused at the callback
 *    (#3902, PR #3900). SAML qualifies because its issuer is the tenant's
 *    own IdP EntityID (#4450). Each provider has different options (Entra
 *    requires tenant_id, OIDC requires issuer for discovery, SAML requires
 *    the IdP trio and has no client credential at all).
 *
 * 4. Domain Allowlist: The allowed_domains list restricts which email
 *    domains can authenticate via this SSO config. Empty list means no
 *    restriction (any domain allowed).
 *
 * 5. SAML trust anchor (#4450): idp_sso_service_url, idp_entity_id and
 *    idp_cert are returned in PLAINTEXT (none is a secret — an IdP publishes
 *    all three). They are encrypted at rest for INTEGRITY (AAD-bound to the
 *    domain), which is why `unreadable_fields` exists: a value that fails to
 *    decrypt is served as null AND named there, and the UI must render an
 *    error state demanding re-entry — never treat that null as "unset".
 *
 * @module contracts/custom-domain/sso-config
 * @category Contracts
 * @see {@link "shapes/domains/sso-config"} - Shapes with transforms
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
 * - saml: OmniAuth::Strategies::RequestBoundSAML (omniauth-saml subclass, #4450)
 *
 * Every tenant provider carries a tenant-distinguishing issuer: per-tenant
 * identity partitioning is keyed (provider, issuer, uid), and issuerless
 * providers (google, github) resolve to a shared issuer sentinel, so their
 * callbacks are refused on tenant surfaces (#3902, PR #3900).
 * Platform/install-level SSO is a separate surface and still supports
 * GitHub/Google.
 *
 * Mirrors PROVIDER_TYPES in lib/onetime/models/custom_domain/sso_config.rb
 * (pinned by src/tests/contracts/sso-config-metadata-contract.spec.ts).
 *
 * @category Contracts
 */
export const ssoProviderTypeSchema = z.enum(['oidc', 'entra_id', 'saml']);

export type SsoProviderType = z.infer<typeof ssoProviderTypeSchema>;

/**
 * Provider metadata for UI behavior.
 *
 * Mirrors PROVIDER_METADATA in lib/onetime/models/custom_domain/sso_config.rb.
 * Used by forms to determine when domain filter field should be shown/required.
 */
export const SSO_PROVIDER_METADATA: Record<SsoProviderType, {
  requiresDomainFilter: boolean;
  idpControlsAccess: boolean;
  description: string;
}> = {
  oidc: {
    requiresDomainFilter: true,
    idpControlsAccess: false,
    description: 'Generic OpenID Connect provider — domain filtering recommended',
  },
  entra_id: {
    requiresDomainFilter: false,
    idpControlsAccess: true,
    description: 'Microsoft Entra ID — access controlled via Azure app assignment',
  },
  // "SAML" names a protocol, not an IdP, so nothing here can promise the IdP
  // restricts who reaches this application. Same conservative posture as
  // generic OIDC.
  saml: {
    requiresDomainFilter: true,
    idpControlsAccess: false,
    description: 'Generic SAML 2.0 identity provider — domain filtering recommended',
  },
} as const;

/**
 * Provider types that authenticate to the IdP with an OAuth client
 * credential, i.e. the ones for which client_id is required (and
 * client_secret for entra_id). SAML has none — its trust anchor is the IdP
 * signing certificate — so the form hides and the payloads omit both.
 *
 * Mirrors CLIENT_CREDENTIAL_PROVIDER_TYPES in
 * lib/onetime/models/custom_domain/sso_config.rb (pinned by the contract
 * spec against the Ruby source).
 */
export const SSO_CLIENT_CREDENTIAL_PROVIDER_TYPES: readonly SsoProviderType[] = ['oidc', 'entra_id'];

export function ssoProviderUsesClientCredentials(providerType: SsoProviderType): boolean {
  return SSO_CLIENT_CREDENTIAL_PROVIDER_TYPES.includes(providerType);
}

/**
 * Default platform route name per provider type, i.e. the `<route>` in
 * `/auth/sso/<route>/callback`. Used to preview the callback / SP URLs before
 * a record exists (once saved, prefer the API's sp_entity_id / acs_url).
 *
 * Mirrors the `default:` values of PROVIDER_ROUTE_MAP in
 * lib/onetime/models/custom_domain/sso_config.rb (pinned by the contract
 * spec against the Ruby source). An operator can override the registered
 * route per provider via OIDC_ROUTE_NAME / ENTRA_ROUTE_NAME /
 * SAML_ROUTE_NAME; this static map cannot see that override, so the preview
 * drifts from the real path in a deployment that sets one. Not plumbed
 * through the API yet — tracked in #3932 (bootstrap-config carrier, since
 * the preview must work before any record exists).
 */
export const SSO_PROVIDER_ROUTE_NAMES: Record<SsoProviderType, string> = {
  oidc: 'oidc',
  entra_id: 'entra',
  saml: 'saml',
} as const;

/**
 * The SAML IdP trio (#4450). All three are required for provider_type
 * 'saml' and discarded for every other type. Mirrors SAML_FIELDS in
 * lib/onetime/models/custom_domain/sso_config.rb.
 */
export const SSO_SAML_FIELDS = ['idp_sso_service_url', 'idp_entity_id', 'idp_cert'] as const;

export type SsoSamlField = (typeof SSO_SAML_FIELDS)[number];

// ─────────────────────────────────────────────────────────────────────────────
// Canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical CustomDomain::SsoConfig contract schema.
 *
 * Defines field names matching the Ruby CustomDomain::SsoConfig model and wire format.
 * Shapes transform timestamps (number -> Date) for runtime use.
 *
 * Note: client_id and client_secret are encrypted at rest in the backend.
 * API responses use client_secret_masked to indicate presence without exposing
 * the actual secret.
 *
 * @see lib/onetime/models/custom_domain/sso_config.rb - Backend model
 * @category Contracts
 */
export const customDomainSsoConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.identifier). */
  domain_id: z.string(),

  /** SSO provider type (oidc, entra_id, saml). */
  provider_type: ssoProviderTypeSchema,

  /** Whether SSO is enabled for this organization. */
  enabled: z.boolean(),

  /** Human-readable name for UI display (e.g., "Acme Corp SSO"). */
  display_name: z.string(),

  /**
   * OAuth client ID (encrypted at rest). Null if not yet configured, and
   * always null for 'saml' (no client credential).
   */
  client_id: z.string().nullable(),

  /**
   * Masked client secret for display (e.g., "••••1234").
   * Never contains the actual secret value. Null if not yet configured,
   * and always null for 'saml'.
   */
  client_secret_masked: z.string().nullable(),

  /**
   * Azure AD tenant ID.
   *
   * Provider-specific field requirements:
   *
   *   | provider_type | client_id | client_secret | tenant_id | issuer   | SAML trio |
   *   |---------------|-----------|---------------|-----------|----------|-----------|
   *   | entra_id      | required  | required      | required  | -        | -         |
   *   | oidc          | required  | optional      | -         | required | -         |
   *   | saml          | -         | -             | -         | -        | required  |
   *
   * The SAML trio is idp_sso_service_url + idp_entity_id + idp_cert. The
   * side a provider type does not use is cleared by the API, never stored.
   * display_name is required by the form regardless of provider.
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
   * SAML IdP SSO service URL (https), where the browser is redirected with
   * the AuthnRequest. Plaintext; 'saml' only, null otherwise. A null that is
   * also named in `unreadable_fields` means UNREADABLE, not unset.
   */
  idp_sso_service_url: z.string().nullable(),

  /**
   * SAML IdP EntityID — the issuer every identity from this domain is keyed
   * on, compared byte-for-byte with the Issuer of each response. Plaintext;
   * 'saml' only, null otherwise. See `unreadable_fields`.
   */
  idp_entity_id: z.string().nullable(),

  /**
   * SAML IdP signing certificate, one PEM X.509 block. A public value,
   * returned in plaintext; 'saml' only, null otherwise. See
   * `unreadable_fields`.
   */
  idp_cert: z.string().nullable(),

  /**
   * Our SP EntityID for this domain, read-only, for the admin to register at
   * the IdP: `https://<domain>/auth/sso/<route>/metadata` (also the SP
   * metadata URL). Null for non-saml records or when the API could not
   * derive it — the form then previews it from the domain host.
   */
  sp_entity_id: z.string().nullable(),

  /**
   * Our Assertion Consumer Service URL for this domain, read-only:
   * `https://<domain>/auth/sso/<route>/callback`. Null for non-saml records
   * or when the API could not derive it.
   */
  acs_url: z.string().nullable(),

  /**
   * Names of encrypted fields whose reveal FAILED (any of client_id,
   * client_secret, idp_sso_service_url, idp_entity_id, idp_cert). Empty for
   * a healthy record. A listed field is served as null; the UI must render
   * an error state and demand re-entry, because a trust anchor that will not
   * decrypt is exactly what the domain-bound AAD exists to catch.
   */
  unreadable_fields: z.array(z.string()),

  /**
   * Email domain allowlist.
   * Users must have email addresses in one of these domains to authenticate.
   * Empty array means no domain restriction.
   */
  allowed_domains: z.array(z.string()),

  /**
   * Whether app-side domain filtering is recommended for this provider.
   * True for providers without IdP-side user assignment (e.g., generic OIDC).
   * Read-only, computed from provider_type.
   */
  requires_domain_filter: z.boolean(),

  /**
   * Whether the IdP controls access via user/app assignment.
   * When true, app-side domain filtering is typically redundant.
   * Read-only, computed from provider_type.
   */
  idp_controls_access: z.boolean(),

  /**
   * Whether to enforce SSO-only authentication for this domain.
   * When true, password-based authentication is disabled and users
   * must sign in via the configured SSO provider.
   */
  enforce_sso_only: z.boolean(),

  /**
   * Whether SSO users on this domain receive org-wide access.
   * When true, users who authenticate via this domain's SSO can access
   * all organization domains. When false (default), access is scoped
   * to this domain only.
   */
  grant_org_scope: z.boolean(),

  /** Configuration creation timestamp (Unix epoch seconds). */
  created_at: z.number(),

  /** Last update timestamp (Unix epoch seconds). */
  updated_at: z.number(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for CustomDomain::SsoConfig wire format. */
export type CustomDomainSsoConfigCanonical = z.infer<typeof customDomainSsoConfigCanonical>;

// ─────────────────────────────────────────────────────────────────────────────
// SAML request fields (shared by PATCH and PUT)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Request-side SAML trio (#4450). Every field is optional at the schema
 * level because the payload types are shared across providers; the strict
 * PUT schema requires all three for provider_type 'saml'.
 *
 * The SSO URL must be https: the API refuses anything else (and also
 * applies an SSRF host check the client cannot mirror). The certificate is
 * one PEM `-----BEGIN CERTIFICATE-----` block; the API normalizes CRLF and
 * literal "\n". Fingerprint parameters (idp_cert_fingerprint and its
 * ruby-saml siblings) are refused by the API for every provider type and
 * are deliberately absent here.
 */
const samlPayloadFields = {
  idp_sso_service_url: z
    .string()
    .url('IdP SSO service URL must be a valid URL')
    .startsWith('https://', 'IdP SSO service URL must be an https:// URL')
    .optional(),
  idp_entity_id: z.string().min(1, 'IdP EntityID is required').optional(),
  idp_cert: z
    .string()
    .includes('-----BEGIN CERTIFICATE-----', {
      message: 'IdP certificate must be a PEM X.509 certificate (-----BEGIN CERTIFICATE-----)',
    })
    .optional(),
};

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
  /** SSO provider type (oidc, entra_id, saml). */
  provider_type: ssoProviderTypeSchema.optional(),

  /** Human-readable name for UI display. */
  display_name: z.string().min(1, 'Display name is required').max(100, 'Display name is too long').optional(),

  /** OAuth client ID (oidc / entra_id; not used by saml). */
  client_id: z.string().min(1, 'Client ID is required').optional(),

  /**
   * OAuth client secret.
   * Optional for update - omit to preserve existing secret.
   */
  client_secret: z.string().optional(),

  /**
   * Azure AD tenant ID (required for entra_id only). See
   * customDomainSsoConfigCanonical for provider-specific requirements.
   */
  tenant_id: z.string().optional(),

  /**
   * OIDC issuer URL (required for oidc only). See
   * customDomainSsoConfigCanonical for provider-specific requirements.
   */
  issuer: z.string().url('Issuer must be a valid URL').optional(),

  /**
   * SAML trio (#4450). On an existing saml record each omitted/blank field
   * preserves the stored value; switching TO saml needs all three.
   */
  ...samlPayloadFields,

  /** Email domain allowlist. Empty array means no restriction. */
  allowed_domains: z.array(z.string()).optional(),

  /** Whether SSO is enabled. */
  enabled: z.boolean().optional(),

  /** Whether to enforce SSO-only authentication for this domain. */
  enforce_sso_only: z.boolean().optional(),

  /** Whether SSO users on this domain receive org-wide access. */
  grant_org_scope: z.boolean().optional(),
});

export type PatchSsoConfigPayload = z.infer<typeof patchSsoConfigPayloadSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// PUT payload schema (full replacement - required fields enforced)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * PUT SSO configuration request payload schema.
 *
 * Full replacement semantics - the request body IS the new state. A PUT
 * that omits client_secret clears any stored one (only valid for OIDC
 * public clients and SAML, which has none).
 *
 * @category Contracts
 */
export const putSsoConfigPayloadSchema = z.object({
  /** SSO provider type (oidc, entra_id, saml). */
  provider_type: ssoProviderTypeSchema,

  /** Human-readable name for UI display. */
  display_name: z.string().min(1, 'Display name is required').max(100, 'Display name is too long'),

  /**
   * OAuth client ID. Required for oidc / entra_id
   * (SSO_CLIENT_CREDENTIAL_PROVIDER_TYPES) — enforced by the strict schema;
   * not used by saml, and discarded by the API if sent.
   */
  client_id: z.string().min(1, 'Client ID is required').optional(),

  /**
   * OAuth client secret. Required for entra_id only (OIDC supports public
   * clients; SAML has none).
   */
  client_secret: z.string().optional(),

  /**
   * Azure AD tenant ID (required for entra_id only). See
   * customDomainSsoConfigCanonical for provider-specific requirements.
   */
  tenant_id: z.string().optional(),

  /**
   * OIDC issuer URL (required for oidc only). See
   * customDomainSsoConfigCanonical for provider-specific requirements.
   */
  issuer: z.string().url('Issuer must be a valid URL').optional(),

  /** SAML trio (#4450). Required for saml — enforced by the strict schema. */
  ...samlPayloadFields,

  /** Email domain allowlist. Empty array means no restriction. */
  allowed_domains: z.array(z.string()).optional(),

  /** Whether SSO is enabled. Defaults to false. */
  enabled: z.boolean().optional(),

  /** Whether to enforce SSO-only authentication for this domain. Defaults to false. */
  enforce_sso_only: z.boolean().optional(),

  /** Whether SSO users on this domain receive org-wide access. Defaults to false. */
  grant_org_scope: z.boolean().optional(),
});

/**
 * PUT SSO config payload with provider-specific validation.
 *
 * - oidc / entra_id require client_id (SSO_CLIENT_CREDENTIAL_PROVIDER_TYPES)
 * - Entra ID requires tenant_id
 * - OIDC requires issuer
 * - SAML requires idp_sso_service_url, idp_entity_id and idp_cert
 *
 * Mirrors the API's validate_client_credentials /
 * validate_provider_specific_fields (apps/api/domains/logic/sso_config/
 * put_sso_config.rb) and its 422 `field` names.
 */
export const putSsoConfigPayloadStrictSchema = putSsoConfigPayloadSchema.superRefine(
  (data, ctx) => {
    if (ssoProviderUsesClientCredentials(data.provider_type) && !data.client_id) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'Client ID is required',
        path: ['client_id'],
      });
    }

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

    if (data.provider_type === 'saml') {
      for (const field of SSO_SAML_FIELDS) {
        if (!data[field]) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `${field} is required for SAML provider`,
            path: [field],
          });
        }
      }
    }
  }
);

export type PutSsoConfigPayload = z.infer<typeof putSsoConfigPayloadSchema>;
export type PutSsoConfigPayloadStrict = z.infer<typeof putSsoConfigPayloadStrictSchema>;
