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
  type SignupConfigDetails,
} from '@/schemas/api/domains/responses/signup-config';
import type { CustomDomainSignupConfig } from '@/schemas/shapes/domains/signup-config';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import axios from 'axios';

const $api = createApi();

/**
 * Signup configuration response wrapper.
 *
 * `record` is null when the domain is unconfigured — the API returns 200
 * with a null record and resolution `details` (ADR-024). A 404 fallback is
 * kept for older backends; in that case `details` is null too.
 */
export interface SignupConfigResponse {
  record: CustomDomainSignupConfig | null;
  details: SignupConfigDetails | null;
}

export const SignupConfigService = {
  /**
   * Get signup configuration for a specific domain.
   *
   * @param domainExtId - Domain external ID
   * @returns Signup configuration (record null when unconfigured) plus
   *   resolution details (global/effective availability)
   */
  async getConfigForDomain(domainExtId: string): Promise<SignupConfigResponse> {
    try {
      const response = await $api.get(`/api/domains/${domainExtId}/signup-config`);
      const result = gracefulParse(getSignupConfigResponseSchema, response.data, 'GetSignupConfigResponse');
      if (!result.ok) {
        return { record: null, details: null };
      }
      return { record: result.data.record, details: result.data.details ?? null };
    } catch (error: unknown) {
      // Older backends return 404 for an unconfigured domain (pre-ADR-024).
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        return { record: null, details: null };
      }
      throw error;
    }
  },

  /**
   * Create or replace signup configuration for a domain (PUT — full replacement).
   *
   * @param domainExtId - Domain external ID
   * @param payload - Full signup configuration data
   * @returns Updated signup configuration plus post-write resolution details
   * @throws ZodError if response validation fails
   */
  async putConfigForDomain(
    domainExtId: string,
    payload: PutSignupConfigRequest
  ): Promise<SignupConfigResponse> {
    const response = await $api.put(`/api/domains/${domainExtId}/signup-config`, payload);
    const validated = strictParse(putSignupConfigResponseSchema, response.data);
    return { record: validated.record, details: validated.details ?? null };
  },

  /**
   * Delete signup configuration for a domain.
   *
   * After deletion, signup on this domain falls back to the global
   * signup policy configuration. The response carries post-delete
   * resolution details (effective == global).
   *
   * @param domainExtId - Domain external ID
   * @returns Deletion confirmation with resolution details
   * @throws ZodError if response validation fails
   */
  async deleteConfigForDomain(domainExtId: string): Promise<DeleteSignupConfigResponse> {
    const response = await $api.delete(`/api/domains/${domainExtId}/signup-config`);
    return strictParse(deleteSignupConfigResponseSchema, response.data);
  },
};
