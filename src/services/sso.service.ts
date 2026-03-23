// src/services/sso.service.ts

/**
 * SSO Configuration Service
 *
 * Provides methods for interacting with the organization SSO configuration API.
 * Handles CRUD operations for SSO provider settings.
 */

import { createApi } from '@/api';
import type {
  CreateOrUpdateSsoConfigRequest,
  DeleteSsoConfigResponse,
} from '@/schemas/api/organizations/requests/sso-config';
import type { OrgSsoConfig, SsoProviderType } from '@/schemas/shapes/organizations/org-sso-config';

const $api = createApi();

/**
 * SSO configuration response wrapper
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
   * @returns SSO configuration or null if not configured
   */
  async getConfig(orgExtId: string): Promise<SsoConfigResponse> {
    const response = await $api.get(`/api/v2/organizations/${orgExtId}/sso-config`);
    return response.data;
  },

  /**
   * Create or update SSO configuration for an organization
   *
   * @param orgExtId - Organization external ID
   * @param payload - SSO configuration data
   * @returns Updated SSO configuration
   */
  async saveConfig(
    orgExtId: string,
    payload: CreateOrUpdateSsoConfigRequest
  ): Promise<SsoConfigResponse> {
    const response = await $api.put(`/api/v2/organizations/${orgExtId}/sso-config`, payload);
    return response.data;
  },

  /**
   * Delete SSO configuration for an organization
   *
   * @param orgExtId - Organization external ID
   * @returns Deletion confirmation
   */
  async deleteConfig(orgExtId: string): Promise<DeleteSsoConfigResponse> {
    const response = await $api.delete(`/api/v2/organizations/${orgExtId}/sso-config`);
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
};
