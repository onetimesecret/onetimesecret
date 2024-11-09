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


    // Debug specific vhost data
    console.log("keys:", Object.keys(response.data))
    console.log("records[0] keys:", Object.keys(response.data.records[0]))
    console.log("records[0]:", response.data.records[0])
    console.log('First record vhost:', response.data.records[0].vhost)
    console.log('First record vhost.created_at:', response.data.records[0].vhost.created_at)


        const validated = transformResponse(
          apiRecordsResponseSchema(customDomainInputSchema),
          response.data
        )

        this.domains = validated.records

      } catch (error) {
        if (isTransformError(error)) {
          // Enhanced error logging with path information
          console.error('Transform Error Details:', {
            path: error.details[0]?.path,
            expected: error.details[0]?.expected,
            received: error.details[0]?.received,
            message: error.details[0]?.message,
            raw: error.data
          })
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
