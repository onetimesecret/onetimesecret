// src/services/sso.service.ts

/**
 * SSO Configuration Service
 *
 * Provides methods for interacting with the domain SSO configuration API.
 * Handles CRUD operations for SSO provider settings on custom domains.
 */

import { createApi } from '@/api';
import type {
  PutSsoConfigRequest,
  PatchSsoConfigRequest,
} from '@/schemas/api/domains/requests/sso-config';
import {
  getSsoConfigResponseSchema,
  putSsoConfigResponseSchema,
  patchSsoConfigResponseSchema,
  deleteSsoConfigResponseSchema,
  type DeleteSsoConfigResponse,
} from '@/schemas/api/domains/responses/sso-config';
import type {
  CustomDomainSsoConfig,
  SsoProviderType,
  SsoTokenEndpointAuthMethodRequest,
} from '@/schemas/shapes/domains/sso-config';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import axios from 'axios';

const $api = createApi();

/**
 * SSO configuration response wrapper
 *
 * Note: The record is non-null on success. When no config exists,
 * the API returns 404 (not 200 with null), so consumers should
 * handle AxiosError with status 404 for missing configs.
 *
 * Response parsing applies Zod schema transforms:
 * - `created_at` and `updated_at` are transformed from Unix epoch to Date objects
 * - Optional fields are normalized (nullish -> null or default)
 */
export interface SsoConfigResponse {
  record: CustomDomainSsoConfig | null;
}

/**
 * Request payload for testing SSO connection
 */
export interface TestSsoConnectionRequest {
  provider_type: SsoProviderType;
  /** Required for oidc / entra_id; absent for saml (no client credential, #4450). */
  client_id?: string;
  tenant_id?: string;
  issuer?: string;
  /**
   * OIDC only (#4764): the selected token endpoint auth method, '' when
   * none. The test reports whether the discovery document advertises it.
   */
  token_endpoint_auth_method?: SsoTokenEndpointAuthMethodRequest;
  /** SAML trio (#4450) — all three required for provider_type 'saml'. */
  idp_sso_service_url?: string;
  idp_entity_id?: string;
  idp_cert?: string;
}

/**
 * Response from SSO connection test
 */
export interface TestSsoConnectionResponse {
  user_id: string;
  success: boolean;
  provider_type: SsoProviderType;
  message: string;
  details: {
    // Success details (OIDC/Entra)
    issuer?: string;
    authorization_endpoint?: string;
    token_endpoint?: string;
    jwks_uri?: string;
    userinfo_endpoint?: string;
    scopes_supported?: string[];
    /**
     * OIDC / Entra (#4764): the discovery document's
     * token_endpoint_auth_methods_supported list, null when it omits the
     * field (OIDC Discovery then implies client_secret_basic).
     */
    token_endpoint_auth_methods_supported?: string[] | null;
    /**
     * Whether the selected token_endpoint_auth_method is advertised by the
     * document; null when nothing was selected. Advisory: false does NOT
     * fail the test (an IdP may accept a method it does not list) — it
     * comes with a `note` explaining the gap.
     */
    token_endpoint_auth_method_supported?: boolean | null;
    note?: string;
    // Success details (SAML, #4450). The test is LOCAL — the IdP is not
    // contacted — so what it reports is what it parsed: the trio as
    // submitted and the certificate's subject / expiry.
    idp_entity_id?: string;
    idp_sso_service_url?: string;
    certificate_subject?: string;
    /**
     * ISO 8601 validity window. Both bounds also accompany a
     * `certificate_expired` / `certificate_not_yet_valid` failure, so the
     * UI can say when the certificate expired or when it becomes valid.
     */
    certificate_not_before?: string;
    certificate_not_after?: string;
    certificate_expires_in_days?: number;
    // Error details
    error_code?: string;
    http_status?: number;
    url?: string;
    description?: string;
    missing_fields?: string[];
    content_type?: string;
    timeout_seconds?: number;
    max_bytes?: number;
    // issuer_mismatch (generic OIDC only): exact values, never normalized.
    // discovery_issuer is null when the document's issuer is not a string.
    configured_issuer?: string;
    discovery_issuer?: string | null;
    /**
     * SAML: the offending field (idp_sso_service_url | idp_entity_id |
     * idp_cert) for error_code invalid_sso_url | invalid_entity_id |
     * invalid_certificate | certificate_expired | certificate_not_yet_valid.
     */
    field?: string;
  };
}

/**
 * Outcome of one diagnostic check (POST /api/domains/:extid/sso/diagnostics).
 *
 * - passed / failed: the check ran and is evidence about the saved record.
 * - inconclusive: the check ran but what it saw is not evidence about the
 *   configuration (the IdP could not be reached, an unmapped provider error).
 * - unsupported: no safe check exists for this provider (a generic OIDC
 *   credential probe).
 * - skipped: an earlier check failed, so this one did not run.
 */
export type SsoDiagnosticStatus = 'passed' | 'failed' | 'inconclusive' | 'unsupported' | 'skipped';

/**
 * The roll-up: failed if any check failed; else inconclusive if any check
 * is inconclusive; else passed. unsupported / skipped do not count.
 */
export type SsoDiagnosticOverall = 'passed' | 'failed' | 'inconclusive';

/**
 * Check names the API emits today, in the order they run. `check` on the
 * wire is a string so a new check renders under its raw name until a label
 * is added, rather than breaking the response.
 */
export const SSO_DIAGNOSTIC_CHECK_NAMES = [
  'stored_configuration',
  'discovery',
  'certificate',
  'credential',
] as const;

export type SsoDiagnosticCheckName = (typeof SSO_DIAGNOSTIC_CHECK_NAMES)[number];

/**
 * One layer of the saved configuration, reported separately. Which checks
 * appear depends on provider_type: stored_configuration for every provider;
 * discovery and credential for oidc / entra_id; certificate for saml.
 */
export interface SsoDiagnosticCheck {
  check: SsoDiagnosticCheckName | (string & {});
  status: SsoDiagnosticStatus;
  /** One human sentence. Never carries the secret, a token or the raw IdP error. */
  message: string;
  details: {
    // stored_configuration (failed): SsoConfig#validation_errors, no secret values.
    errors?: string[];
    // discovery: the same vocabulary as TestSsoConnectionResponse.details.
    issuer?: string;
    token_endpoint?: string;
    token_endpoint_auth_methods_supported?: string[] | null;
    token_endpoint_auth_method_supported?: boolean | null;
    // certificate (saml): local parse of the stored idp_cert.
    certificate_subject?: string;
    certificate_not_after?: string;
    certificate_expires_in_days?: number;
    // credential (entra_id): a client-credentials token request with the
    // STORED secret. error_code is one of invalid_client_secret |
    // client_secret_expired | app_not_found_in_tenant | provider_error |
    // timeout | connection_failed | invalid_response.
    error_code?: string;
    http_status?: number;
    /**
     * provider_error only: the AADSTS code alone (e.g. "AADSTS50034"). The
     * API never echoes error_description, which carries correlation ids
     * and the app id.
     */
    aadsts_code?: string;
    /**
     * entra_id, independent of the probe outcome: "uuid" when the stored
     * secret has the shape of an Entra Secret ID rather than its Value.
     */
    secret_shape?: string;
    /** Caveats about what the check does and does not prove. */
    note?: string;
  };
}

/**
 * Response from the saved-configuration diagnostics
 *
 * Unlike Test Connection, which tests the FORM fields and never uses the
 * client secret, this runs against the SAVED record — including the stored
 * client secret for Entra — and reports each layer separately.
 */
export interface SsoDiagnosticsResponse {
  user_id: string;
  provider_type: SsoProviderType;
  /** ISO 8601 UTC. */
  checked_at: string;
  /**
   * SsoConfig#updated as stored (string, may be empty): ties the result to
   * the record it describes, so a result that outlives a save is visibly
   * about the previous revision.
   */
  configuration_revision: string;
  overall: SsoDiagnosticOverall;
  checks: SsoDiagnosticCheck[];
}

export const SsoService = {
  /**
   * Get SSO configuration for a specific domain
   *
   * @param domainExtId - Domain external ID
   * @returns SSO configuration or { record: null } if not configured
   */
  async getConfigForDomain(domainExtId: string): Promise<SsoConfigResponse> {
    try {
      const response = await $api.get(`/api/domains/${domainExtId}/sso`);
      const result = gracefulParse(getSsoConfigResponseSchema, response.data, 'GetSsoConfigResponse');
      if (!result.ok) {
        // Degrade gracefully on parse failure - treat as missing config
        return { record: null };
      }
      return { record: result.data.record };
    } catch (error: unknown) {
      // Handle 404 (no SSO config exists) by returning { record: null }
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        return { record: null };
      }
      throw error;
    }
  },

  /**
   * Create SSO configuration for a domain (full replacement)
   *
   * Uses PUT semantics: the request body IS the new state.
   * client_secret is required for full replacement.
   *
   * @param domainExtId - Domain external ID
   * @param payload - Full SSO configuration data including client_secret
   * @returns Updated SSO configuration
   * @throws ZodError if response validation fails
   */
  async putConfigForDomain(
    domainExtId: string,
    payload: PutSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    const response = await $api.put(`/api/domains/${domainExtId}/sso`, payload);
    const validated = strictParse(putSsoConfigResponseSchema, response.data);
    return { record: validated.record };
  },

  /**
   * Update SSO configuration for a domain (partial update)
   *
   * Uses PATCH semantics: only provided fields are updated.
   * client_secret is optional; omit to preserve existing secret.
   *
   * @param domainExtId - Domain external ID
   * @param payload - Partial SSO configuration data
   * @returns Updated SSO configuration
   * @throws ZodError if response validation fails
   */
  async patchConfigForDomain(
    domainExtId: string,
    payload: PatchSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    const response = await $api.patch(`/api/domains/${domainExtId}/sso`, payload);
    const validated = strictParse(patchSsoConfigResponseSchema, response.data);
    return { record: validated.record };
  },

  /**
   * Create or update SSO configuration for a domain
   *
   * Automatically selects PUT or PATCH based on payload:
   * - If client_secret is provided and non-empty: uses PUT (full replacement)
   * - If client_secret is omitted or empty: uses PATCH (partial update)
   *
   * @param domainExtId - Domain external ID
   * @param payload - SSO configuration data
   * @returns Updated SSO configuration
   */
  async saveConfigForDomain(
    domainExtId: string,
    payload: PutSsoConfigRequest | PatchSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    // A saml payload never carries client_secret, so it always takes the
    // PATCH path; PATCH creates when no record exists and, for saml, requires
    // the full IdP trio on create or on a switch to saml (#4450).
    const hasClientSecret = 'client_secret' in payload && payload.client_secret && payload.client_secret.length > 0;

    if (hasClientSecret) {
      return this.putConfigForDomain(domainExtId, payload as PutSsoConfigRequest);
    } else {
      return this.patchConfigForDomain(domainExtId, payload as PatchSsoConfigRequest);
    }
  },

  /**
   * Delete SSO configuration for a domain
   *
   * @param domainExtId - Domain external ID
   * @returns Deletion confirmation
   * @throws ZodError if response validation fails
   */
  async deleteConfigForDomain(domainExtId: string): Promise<DeleteSsoConfigResponse> {
    const response = await $api.delete(`/api/domains/${domainExtId}/sso`);
    return strictParse(deleteSsoConfigResponseSchema, response.data);
  },

  /**
   * Test SSO connection credentials for a domain
   *
   * Validates that the provided SSO credentials can reach the IdP.
   * Uses credentials from request body (not stored config) to allow
   * testing before saving.
   *
   * @param domainExtId - Domain external ID
   * @param payload - Credentials to test
   * @returns Test result with success status and details
   */
  async testConnectionForDomain(
    domainExtId: string,
    payload: TestSsoConnectionRequest
  ): Promise<TestSsoConnectionResponse> {
    const response = await $api.post(`/api/domains/${domainExtId}/sso/test`, payload);
    return response.data;
  },

  /**
   * Run diagnostics against the SAVED SSO configuration of a domain
   *
   * No body: the API reloads the stored record and checks each layer
   * (stored configuration, discovery, certificate or credential). For
   * entra_id the credential check sends the stored client secret to
   * Microsoft, so the API rate-limits this per customer.
   *
   * @param domainExtId - Domain external ID
   * @returns Per-check statuses and the overall roll-up
   */
  async runDiagnosticsForDomain(domainExtId: string): Promise<SsoDiagnosticsResponse> {
    const response = await $api.post(`/api/domains/${domainExtId}/sso/diagnostics`);
    return response.data;
  },
};
