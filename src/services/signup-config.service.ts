// src/services/signup-config.service.ts

/**
 * Signup Configuration Service
 *
 * Provides methods for interacting with the per-domain signup validation
 * configuration API. Handles CRUD operations for the signup validation
 * strategy on custom domains.
 */

import { createApi } from '@/api';
import type { PutSignupConfigRequest } from '@/schemas/api/domains/requests/signup-config';
import {
  getSignupConfigResponseSchema,
  putSignupConfigResponseSchema,
  deleteSignupConfigResponseSchema,
  type DeleteSignupConfigResponse,
} from '@/schemas/api/domains/responses/signup-config';
import type { CustomDomainSignupConfig } from '@/schemas/shapes/domains/signup-config';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import axios from 'axios';

const $api = createApi();

/**
 * Signup configuration response wrapper.
 *
 * Note: The record is non-null on success. When no config exists,
 * the API returns 404 (not 200 with null), so consumers should
 * handle AxiosError with status 404 for missing configs.
 */
export interface SignupConfigResponse {
  record: CustomDomainSignupConfig | null;
}

export const SignupConfigService = {
  /**
   * Get signup configuration for a specific domain.
   *
   * @param domainExtId - Domain external ID
   * @returns Signup configuration or { record: null } if not configured
   */
  async getConfigForDomain(domainExtId: string): Promise<SignupConfigResponse> {
    try {
      const response = await $api.get(`/api/domains/${domainExtId}/signup-config`);
      const result = gracefulParse(getSignupConfigResponseSchema, response.data, 'GetSignupConfigResponse');
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
   * Create or replace signup configuration for a domain (PUT — full replacement).
   *
   * @param domainExtId - Domain external ID
   * @param payload - Full signup configuration data
   * @returns Updated signup configuration
   * @throws ZodError if response validation fails
   */
  async putConfigForDomain(
    domainExtId: string,
    payload: PutSignupConfigRequest
  ): Promise<SignupConfigResponse> {
    const response = await $api.put(`/api/domains/${domainExtId}/signup-config`, payload);
    const validated = strictParse(putSignupConfigResponseSchema, response.data);
    return { record: validated.record };
  },

  /**
   * Delete signup configuration for a domain.
   *
   * After deletion, signup on this domain falls back to the global
   * allowed_signup_domains configuration.
   *
   * @param domainExtId - Domain external ID
   * @returns Deletion confirmation
   * @throws ZodError if response validation fails
   */
  async deleteConfigForDomain(domainExtId: string): Promise<DeleteSignupConfigResponse> {
    const response = await $api.delete(`/api/domains/${domainExtId}/signup-config`);
    return strictParse(deleteSignupConfigResponseSchema, response.data);
  },
};
