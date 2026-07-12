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
  type SigninConfigDetails,
} from '@/schemas/api/domains/responses/signin-config';
import type { CustomDomainSigninConfig } from '@/schemas/shapes/domains/signin-config';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import axios from 'axios';

const $api = createApi();

/**
 * Signin configuration response wrapper.
 *
 * `record` is null when the domain is unconfigured — the API returns 200
 * with a null record and resolution `details` (ADR-024). A 404 fallback is
 * kept for older backends; in that case `details` is null too.
 */
export interface SigninConfigResponse {
  record: CustomDomainSigninConfig | null;
  details: SigninConfigDetails | null;
}

export const SigninConfigService = {
  /**
   * Get signin configuration for a specific domain.
   *
   * @param domainExtId - Domain external ID
   * @returns Signin configuration (record null when unconfigured) plus
   *   resolution details (global/effective availability)
   */
  async getConfigForDomain(domainExtId: string): Promise<SigninConfigResponse> {
    try {
      const response = await $api.get(`/api/domains/${domainExtId}/signin-config`);
      const result = gracefulParse(getSigninConfigResponseSchema, response.data, 'GetSigninConfigResponse');
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
   * Create or replace signin configuration for a domain (PUT — full replacement).
   *
   * @param domainExtId - Domain external ID
   * @param payload - Full signin configuration data
   * @returns Updated signin configuration plus post-write resolution details
   * @throws ZodError if response validation fails
   */
  async putConfigForDomain(
    domainExtId: string,
    payload: PutSigninConfigRequest
  ): Promise<SigninConfigResponse> {
    const response = await $api.put(`/api/domains/${domainExtId}/signin-config`, payload);
    const validated = strictParse(putSigninConfigResponseSchema, response.data);
    return { record: validated.record, details: validated.details ?? null };
  },

  /**
   * Delete signin configuration for a domain.
   *
   * After deletion, signin on this domain falls back to the global
   * signin policy configuration. The response carries post-delete
   * resolution details (effective == global).
   *
   * @param domainExtId - Domain external ID
   * @returns Deletion confirmation with resolution details
   * @throws ZodError if response validation fails
   */
  async deleteConfigForDomain(domainExtId: string): Promise<DeleteSigninConfigResponse> {
    const response = await $api.delete(`/api/domains/${domainExtId}/signin-config`);
    return strictParse(deleteSigninConfigResponseSchema, response.data);
  },
};
