// src/stores/domainsStore.ts
import { defineStore } from 'pinia'
import type { UpdateDomainBrandRequest } from '@/types/api/requests'
import type { ApiRecordResponse, ApiRecordsResponse } from '@/types/api/responses'
import { createApi } from '@/utils/api'
import {
  transformResponse,
  isTransformError,
  apiRecordResponseSchema,
  apiRecordsResponseSchema
} from '@/utils/transforms'
import {
  customDomainInputSchema,
  type CustomDomain
} from '@/schemas/models/domain'

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

        // Transform at API boundary
        const validated = transformResponse(
          apiRecordsResponseSchema(customDomainInputSchema),
          response.data
        )

        // Store uses shared type with components
        this.domains = validated.records as CustomDomain[]

      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details)
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

        return validated.record as CustomDomain

      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details)
        }
        throw error
      }
    }
  }
})
