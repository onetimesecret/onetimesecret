// src/stores/secretsStore.ts

import {
  secretResponseSchema,
  type SecretData,
  type SecretDetails,
  type SecretResponse
} from '@/schemas/models/secret';
import { createApi } from '@/utils/api';
import { isTransformError, transformResponse } from '@/utils/transforms';
import { defineStore } from 'pinia';

const api = createApi()

interface SecretState {
  record: SecretData | null
  details: SecretDetails | null
  isLoading: boolean
  error: string | null
}

/**
 * Store for managing secret state and API interactions
 * Handles both initial load and reveal flows with proper validation
 */
export const useSecretsStore = defineStore('secrets', {
  state: (): SecretState => ({
    record: null,
    details: null,
    isLoading: false,
    error: null
  }),

  actions: {
    /**
     * Initial load of secret details (no secret value)
     * Used by route resolver and initial component mount
     */
    async loadSecret(secretKey: string) {
      this.isLoading = true
      try {
        const response = await api.get<SecretResponse>(`/api/v2/secret/${secretKey}`)

        const validated = transformResponse(
          secretResponseSchema,
          response.data
        )

        this.record = validated.record
        this.details = validated.details
        this.error = null

        return validated

      } catch (error) {
        if (isTransformError(error)) {
          console.error('Secret validation failed:', error.details)
          this.error = 'Invalid server response'
        } else {
          this.error = error instanceof Error ? error.message : 'Failed to load secret'
        }
        throw error

      } finally {
        this.isLoading = false
      }
    },

    /**
     * Reveals secret value after user confirmation
     * Handles passphrase verification if required
     */
    async revealSecret(secretKey: string, passphrase?: string) {
      this.isLoading = true
      try {
        const response = await api.post<SecretResponse>(`/api/v2/secret/${secretKey}`, {
          passphrase,
          continue: true
        })

        const validated = transformResponse(
          secretResponseSchema,
          response.data
        )

        this.record = validated.record
        this.details = validated.details
        this.error = null

        return validated

      } catch (error) {
        if (isTransformError(error)) {
          console.error('Secret validation failed:', error.details)
          this.error = 'Invalid server response'
        } else {
          const message = error instanceof Error ? error.message : 'Failed to reveal secret'
          this.error = message
          // Preserve existing record/details on error
        }
        throw error

      } finally {
        this.isLoading = false
      }
    },

    /**
     * Clear current secret state
     * Used when navigating away or after errors
     */
    clearSecret() {
      this.record = null
      this.details = null
      this.error = null
    }
  }
})
