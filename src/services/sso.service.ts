// src/services/sso.service.ts

/**
 * SSO Configuration Service
 *
 * Provides methods for interacting with the organization SSO configuration API.
 * Handles CRUD operations for SSO provider settings.
 */

import { createApi } from '@/api';
import type {
  PutSsoConfigRequest,
  PatchSsoConfigRequest,
  DeleteSsoConfigResponse,
} from '@/schemas/api/organizations/requests/sso-config';
import type { OrgSsoConfig, SsoProviderType } from '@/schemas/shapes/organizations/org-sso-config';
import axios from 'axios';

const $api = createApi();

/**
 * SSO configuration response wrapper
 *
 * Note: The record is non-null on success. When no config exists,
 * the API returns 404 (not 200 with null), so consumers should
 * handle AxiosError with status 404 for missing configs.
 */
export interface SsoConfigResponse {
  record: OrgSsoConfig | null;
}

/**
 * Request payload for testing SSO connection
 */
export interface TestSsoConnectionRequest {
  provider_type: SsoProviderType;
  client_id: string;
  tenant_id?: string;
  issuer?: string;
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
    // Success details (OIDC/Entra/Google)
    issuer?: string;
    authorization_endpoint?: string;
    token_endpoint?: string;
    jwks_uri?: string;
    userinfo_endpoint?: string;
    scopes_supported?: string[];
    // GitHub-specific
    client_id_format?: string;
    note?: string;
    // Error details
    error_code?: string;
    http_status?: number;
    url?: string;
    description?: string;
    missing_fields?: string[];
    content_type?: string;
    timeout_seconds?: number;
  };
}

export const SsoService = {
  /**
   * Get SSO configuration for an organization
   *
   * @param orgExtId - Organization external ID
   * @returns SSO configuration or { record: null } if not configured
   */
  async getConfig(orgExtId: string): Promise<SsoConfigResponse> {
    try {
      const response = await $api.get(`/api/organizations/${orgExtId}/sso`);
      return response.data;
    } catch (error: unknown) {
      // Handle 404 (no SSO config exists) by returning { record: null }
      // This matches the SsoConfigResponse type and expected behavior
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        return { record: null };
      }
      throw error;
    }
  },

  /**
   * Create SSO configuration for an organization (full replacement)
   *
   * Uses PUT semantics: the request body IS the new state.
   * client_secret is required for full replacement.
   *
   * @param orgExtId - Organization external ID
   * @param payload - Full SSO configuration data including client_secret
   * @returns Updated SSO configuration
   */
  async putConfig(
    orgExtId: string,
    payload: PutSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    const response = await $api.put(`/api/organizations/${orgExtId}/sso`, payload);
    return response.data;
  },

  /**
   * Update SSO configuration for an organization (partial update)
   *
   * Uses PATCH semantics: only provided fields are updated.
   * client_secret is optional; omit to preserve existing secret.
   *
   * @param orgExtId - Organization external ID
   * @param payload - Partial SSO configuration data
   * @returns Updated SSO configuration
   */
  async patchConfig(
    orgExtId: string,
    payload: PatchSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    const response = await $api.patch(`/api/organizations/${orgExtId}/sso`, payload);
    return response.data;
  },

  /**
   * Create or update SSO configuration for an organization
   *
   * Automatically selects PUT or PATCH based on payload:
   * - If client_secret is provided and non-empty: uses PUT (full replacement)
   * - If client_secret is omitted or empty: uses PATCH (partial update)
   *
   * @param orgExtId - Organization external ID
   * @param payload - SSO configuration data
   * @returns Updated SSO configuration
   */
  async saveConfig(
    orgExtId: string,
    payload: PutSsoConfigRequest | PatchSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    // Use PUT when client_secret is provided (full replacement)
    // Use PATCH when client_secret is omitted (preserve existing secret)
    const hasClientSecret = 'client_secret' in payload && payload.client_secret && payload.client_secret.length > 0;

    if (hasClientSecret) {
      return this.putConfig(orgExtId, payload as PutSsoConfigRequest);
    } else {
      return this.patchConfig(orgExtId, payload as PatchSsoConfigRequest);
    }
  },

  /**
   * Delete SSO configuration for an organization
   *
   * @param orgExtId - Organization external ID
   * @returns Deletion confirmation
   */
  async deleteConfig(orgExtId: string): Promise<DeleteSsoConfigResponse> {
    const response = await $api.delete(`/api/organizations/${orgExtId}/sso`);
    return response.data;
  },

  /**
   * Test SSO connection credentials
   *
   * Validates that the provided SSO credentials can reach the IdP.
   * Uses credentials from request body (not stored config) to allow
   * testing before saving.
   *
   * For OIDC/Entra/Google: Fetches the discovery document and validates it.
   * For GitHub: Validates client_id format only (no OIDC discovery).
   *
   * @param orgExtId - Organization external ID
   * @param payload - Credentials to test
   * @returns Test result with success status and details
   */
  async testConnection(
    orgExtId: string,
    payload: TestSsoConnectionRequest
  ): Promise<TestSsoConnectionResponse> {
    const response = await $api.post(`/api/organizations/${orgExtId}/sso/test`, payload);
    return response.data;
  },

  // ─────────────────────────────────────────────────────────────────────────────
  // Domain-scoped SSO configuration methods
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Get SSO configuration for a specific domain
   *
   * @param domainExtId - Domain external ID
   * @returns SSO configuration or { record: null } if not configured
   */
  async getConfigForDomain(domainExtId: string): Promise<SsoConfigResponse> {
    try {
      const response = await $api.get(`/api/domains/${domainExtId}/sso`);
      return response.data;
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
   */
  async putConfigForDomain(
    domainExtId: string,
    payload: PutSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    const response = await $api.put(`/api/domains/${domainExtId}/sso`, payload);
    return response.data;
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
   */
  async patchConfigForDomain(
    domainExtId: string,
    payload: PatchSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    const response = await $api.patch(`/api/domains/${domainExtId}/sso`, payload);
    return response.data;
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
   */
  async deleteConfigForDomain(domainExtId: string): Promise<DeleteSsoConfigResponse> {
    const response = await $api.delete(`/api/domains/${domainExtId}/sso`);
    return response.data;
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
};
