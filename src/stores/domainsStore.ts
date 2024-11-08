// src/stores/domainsStore.ts
import { defineStore } from 'pinia';
import type { UpdateDomainBrandRequest } from '@/types/api/requests';
import type { CustomDomain } from '@/types/custom_domains';
import { createApi } from '@/utils/api';
import {
  transformResponse,
  //transformRecordsResponse,
  isTransformError,
  apiRecordResponseSchema,
  apiRecordsResponseSchema
} from '@/utils/transforms';
import {
  //customDomainSchema,
  customDomainInputSchema,
  //brandSettingsSchema
} from '@/schemas/domains';

//
// API Input (strings) -> Store/Component (shared types) -> API Output (serialized)
//                       ^                               ^
//                       |                               |
//                    transform                      serialize
//

const api = createApi();


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
        const response = await api.get('/api/v2/account/domains')

        // Transform at API boundary
        const validated = transformResponse(
          apiRecordsResponseSchema(customDomainInputSchema),
          response.data
        )

        // Store uses shared type with components
        this.domains = validated.records

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
        const response = await api.put(`/api/v2/account/domains/${domain}/brand`, brandUpdate);

        return transformResponse(
          apiRecordResponseSchema(customDomainInputSchema),
          response.data
        );

      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details);
        }
        throw error;
      }
    }
  }
});
