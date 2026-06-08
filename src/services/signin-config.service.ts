// src/services/signin-config.service.ts

/**
 * Signin Configuration Service
 *
 * Provides methods for interacting with the per-domain signin
 * configuration API. Handles CRUD operations for the signin
 * method configuration on custom domains.
 */

import { createApi } from '@/api';
import type { PutSigninConfigRequest } from '@/schemas/api/domains/requests/signin-config';
import {
  getSigninConfigResponseSchema,
  putSigninConfigResponseSchema,
  deleteSigninConfigResponseSchema,
  type DeleteSigninConfigResponse,
} from '@/schemas/api/domains/responses/signin-config';
import type { CustomDomainSigninConfig } from '@/schemas/shapes/domains/signin-config';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import axios from 'axios';

const $api = createApi();

/**
 * Signin configuration response wrapper.
 *
 * Note: The record is non-null on success. When no config exists,
 * the API returns 404 (not 200 with null), so consumers should
 * handle AxiosError with status 404 for missing configs.
 */
export interface SigninConfigResponse {
  record: CustomDomainSigninConfig | null;
}

export const SigninConfigService = {
  /**
   * Get signin configuration for a specific domain.
   *
   * @param domainExtId - Domain external ID
   * @returns Signin configuration or { record: null } if not configured
   */
  async getConfigForDomain(domainExtId: string): Promise<SigninConfigResponse> {
    try {
      const response = await $api.get(`/api/domains/${domainExtId}/signin-config`);
      const result = gracefulParse(getSigninConfigResponseSchema, response.data, 'GetSigninConfigResponse');
      if (!result.ok) {
        return { record: null };
      }
      return { record: result.data.record };
    } catch (error: unknown) {
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        return { record: null };
      }
      throw error;
    }
  },

  /**
   * Create or replace signin configuration for a domain (PUT — full replacement).
   *
   * @param domainExtId - Domain external ID
   * @param payload - Full signin configuration data
   * @returns Updated signin configuration
   * @throws ZodError if response validation fails
   */
  async putConfigForDomain(
    domainExtId: string,
    payload: PutSigninConfigRequest
  ): Promise<SigninConfigResponse> {
    const response = await $api.put(`/api/domains/${domainExtId}/signin-config`, payload);
    const validated = strictParse(putSigninConfigResponseSchema, response.data);
    return { record: validated.record };
  },

  /**
   * Delete signin configuration for a domain.
   *
   * After deletion, signin on this domain falls back to the global
   * signin policy configuration.
   *
   * @param domainExtId - Domain external ID
   * @returns Deletion confirmation
   * @throws ZodError if response validation fails
   */
  async deleteConfigForDomain(domainExtId: string): Promise<DeleteSigninConfigResponse> {
    const response = await $api.delete(`/api/domains/${domainExtId}/signin-config`);
    return strictParse(deleteSigninConfigResponseSchema, response.data);
  },
};
