// src/stores/secretStore.ts
import { defineStore } from 'pinia'
import { createApi } from '@/utils/api'
import {
  transformResponse,
  apiRecordResponseSchema,
  isTransformError
} from '@/utils/transforms'
import { secretSchema, type Secret, type SecretData } from '@/schemas/models/secret'
import { metadataSchema, type Metadata } from '@/schemas/models/metadata'

const api = createApi()

/**
 * Secret store with schema-based transformations
 * - Uses shared Secret type with components
 * - Handles API transformation at edges only
 * - Maintains single source of truth for secret data
 */
export const useSecretStore = defineStore('secret', {
  state: (): {
    currentSecret: Secret | null
    relatedMetadata: Metadata | null
    isLoading: boolean
  } => ({
    currentSecret: null,
    relatedMetadata: null,
    isLoading: false
  }),

  actions: {
    async fetchSecret(secretKey: string) {
      this.isLoading = true
      try {
        const response = await api.get(`/api/v2/secret/${secretKey}`)

        // Transform at API boundary
        const validated = transformResponse(
          apiRecordResponseSchema(secretSchema),
          response.data
        )

        this.currentSecret = validated.record

        // If metadata is included, transform it too
        if (response.data.metadata) {
          const validatedMetadata = transformResponse(
            apiRecordResponseSchema(metadataSchema),
            { record: response.data.metadata }
          )
          this.relatedMetadata = validatedMetadata.record
        }

        return validated.record
      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details)
        }
        throw error
      } finally {
        this.isLoading = false
      }
    },

    async createSecret(secretData: Partial<SecretData>) {
      this.isLoading = true
      try {
        const response = await api.post('/api/v2/secret', secretData)

        // Transform response at API boundary
        const validated = transformResponse(
          apiRecordResponseSchema(secretSchema),
          response.data
        )

        this.currentSecret = validated.record

        return validated.record
      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details)
        }
        throw error
      } finally {
        this.isLoading = false
      }
    },

    async burnSecret(secretKey: string) {
      this.isLoading = true
      try {
        const response = await api.post(`/api/v2/secret/${secretKey}/burn`, {})

        // Transform response at API boundary
        const validated = transformResponse(
          apiRecordResponseSchema(secretSchema),
          response.data
        )

        this.currentSecret = validated.record

        return validated.record
      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details)
        }
        throw error
      } finally {
        this.isLoading = false
      }
    }
  }
})
