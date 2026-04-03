// src/services/recipients.service.ts

/**
 * Domain Recipients Service
 *
 * Provides methods for interacting with the domain incoming secrets
 * recipients API. Handles CRUD operations for recipient lists on custom domains.
 *
 * Note on data asymmetry:
 * - Requests use { email, name } (plaintext email for server to hash)
 * - Responses use { digest, display_name } (hashed email for privacy)
 */

import { createApi } from '@/api';
import type {
  PutDomainRecipientsRequest,
  DomainRecipientInput,
} from '@/schemas/api/domains/requests/domain-recipients';
import {
  getDomainRecipientsResponseSchema,
  putDomainRecipientsResponseSchema,
  deleteDomainRecipientsResponseSchema,
  type DeleteDomainRecipientsResponse,
  type DomainRecipientResponse,
} from '@/schemas/api/domains/responses/domain-recipients';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import axios from 'axios';

const $api = createApi();

/**
 * Recipients response wrapper
 *
 * Note: The recipients array is empty when no recipients are configured.
 * A 404 response indicates the domain itself doesn't exist, not that
 * recipients are unconfigured.
 */
export interface RecipientsResponse {
  recipients: DomainRecipientResponse[];
  canManage?: boolean;
  maxRecipients?: number;
}

export const RecipientsService = {
  /**
   * Get recipients for a specific domain
   *
   * @param domainExtId - Domain external ID
   * @returns Recipients list (empty array if none configured)
   */
  async getRecipientsForDomain(domainExtId: string): Promise<RecipientsResponse> {
    try {
      const response = await $api.get(`/api/domains/${domainExtId}/recipients`);
      const result = gracefulParse(
        getDomainRecipientsResponseSchema,
        response.data,
        'GetDomainRecipientsResponse'
      );
      if (!result.ok) {
        // Degrade gracefully on parse failure - treat as empty
        return { recipients: [] };
      }
      return {
        recipients: result.data.record.recipients,
        canManage: result.data.details?.can_manage,
        maxRecipients: result.data.details?.max_recipients,
      };
    } catch (error: unknown) {
      // Handle 404 (domain not found) differently from empty recipients
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        throw error; // Let the composable handle domain-not-found
      }
      throw error;
    }
  },

  /**
   * Set recipients for a domain (full replacement)
   *
   * Uses PUT semantics: the request body IS the new state.
   * Pass an empty array to clear all recipients.
   *
   * @param domainExtId - Domain external ID
   * @param recipients - Array of recipients to set
   * @returns Updated recipients list
   * @throws ZodError if response validation fails
   */
  async setRecipientsForDomain(
    domainExtId: string,
    recipients: DomainRecipientInput[]
  ): Promise<RecipientsResponse> {
    const payload: PutDomainRecipientsRequest = { recipients };
    const response = await $api.put(`/api/domains/${domainExtId}/recipients`, payload);
    const validated = strictParse(putDomainRecipientsResponseSchema, response.data);
    return {
      recipients: validated.record.recipients,
      canManage: validated.details?.can_manage,
      maxRecipients: validated.details?.max_recipients,
    };
  },

  /**
   * Delete all recipients for a domain
   *
   * @param domainExtId - Domain external ID
   * @returns Deletion confirmation
   * @throws ZodError if response validation fails
   */
  async deleteRecipientsForDomain(domainExtId: string): Promise<DeleteDomainRecipientsResponse> {
    const response = await $api.delete(`/api/domains/${domainExtId}/recipients`);
    return strictParse(deleteDomainRecipientsResponseSchema, response.data);
  },
};
