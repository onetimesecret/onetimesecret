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
import type { OrgSsoConfig } from '@/schemas/shapes/organizations/org-sso-config';

const $api = createApi();

/**
 * SSO configuration response wrapper
 */
export interface SsoConfigResponse {
  record: OrgSsoConfig | null;
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
};
