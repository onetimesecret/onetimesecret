// src/stores/domainsStore.ts
import {
  customDomainInputSchema,
  type CustomDomain
} from '@/schemas/models/domain';
import type { UpdateDomainBrandRequest } from '@/types/api/requests';
import { ApiRecordResponse, apiRecordResponseSchema, ApiRecordsResponse, apiRecordsResponseSchema } from '@/types/api/responses';
import { createApi } from '@/utils/api';
import {
  isTransformError,
  transformResponse,
} from '@/utils/transforms';
import { defineStore } from 'pinia';
import type { ZodIssue } from 'zod';


//
// API Input (strings) -> Store/Component (shared types) -> API Output (serialized)
//                       ^                               ^
//                       |                               |
//                    transform                      serialize
//

const api = createApi()

/**
 * Domains store with simplified transformation boundaries
 * - Uses shared CustomDomain type with components
 * - Handles API transformation at edges only
 */
export const useDomainsStore = defineStore('domains', {
  state: (): {
    domains: CustomDomain[],
    isLoading: boolean
  } => ({
    domains: [],
    isLoading: false
  }),
  actions: {
    async refreshDomains() {
      this.isLoading = true
      try {
        const response = await api.get<ApiRecordsResponse<CustomDomain>>('/api/v2/account/domains')

        const validated = transformResponse(
          apiRecordsResponseSchema(customDomainInputSchema),
          response.data
        )

        this.domains = validated.records

      } catch (error) {
        if (isTransformError(error)) {

          // Log detailed validation errors to help debug data transform issues
          console.error('Domain validation failed:', {
            error: 'TRANSFORM_ERROR',
            details: formatErrorDetails(error.details),
            rawData: error.data
          })

        } else {
          console.error('Failed to refresh domains:', error)
        }
        throw error
      } finally {
        this.isLoading = false
      }
    },


    async updateDomainBrand(domain: string, brandUpdate: UpdateDomainBrandRequest) {
      try {
        const response = await api.put<ApiRecordResponse<CustomDomain>>(
          `/api/v2/account/domains/${domain}/brand`,
          brandUpdate
        )

        const validated = transformResponse(
          apiRecordResponseSchema(customDomainInputSchema),
          response.data
        )

        return validated.record

      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details)
        }
        throw error
      }
    }
  }
})

// Helper function to safely format error details
function formatErrorDetails(details: string | ZodIssue[]): unknown {
  return Array.isArray(details)
    ? details.map((detail: ZodIssue) => ({
        path: detail.path,
        expected: detail.expected,
        received: detail.received,
        message: detail.message
      }))
    : details
}
