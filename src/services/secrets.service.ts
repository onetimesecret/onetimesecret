// src/services/secrets.service.ts

import { inject } from 'vue';
import type { AxiosInstance } from 'axios';

// Type for status response
type SecretStatus = { valid: boolean; viewed: boolean; expired: boolean };

/**
 * Service for interacting with secrets-related API endpoints
 */
export const secretsService = {
  /**
   * Checks if a secret is still valid (not viewed or expired)
   * @param secretId The ID of the secret to check
   * @returns Promise that resolves to a status object
   */
  async checkSecretStatus(secretId: string): Promise<SecretStatus> {
    const api = inject('api') as AxiosInstance;
    // This would be the endpoint you'd implement on your backend
    const response = await api.get(`/api/v2/secret/${secretId}/status`);
    return response.data;
  },

  /**
   * Batch checks multiple secret statuses at once
   * @param secretIds Array of secret IDs to check
   * @returns Promise that resolves to a map of secret IDs to their status
   */
  async batchCheckSecretStatus(secretIds: string[]): Promise<Record<string, SecretStatus>> {
    const api = inject('api') as AxiosInstance;
    // More efficient endpoint that accepts multiple IDs
    const response = await api.post('/api/v2/secret/status', { keys: secretIds });
    return response.data;
  },
};
