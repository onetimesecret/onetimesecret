// src/stores/customerStore.ts
import { defineStore } from 'pinia'
import { createApi } from '@/utils/api'
import {
  transformResponse,
  apiRecordResponseSchema,
  isTransformError
} from '@/utils/transforms'
import { customerInputSchema, type Customer } from '@/schemas/models/customer'

//
// API Input (strings) -> Store/Component (shared types) -> API Output (serialized)
//                     ^                                 ^
//                     |                                 |
//                  transform                        serialize
//

const api = createApi()

/**
 * Customer store with simplified transformation boundaries
 * - Uses shared Customer type with components
 * - Handles API transformation at edges only
 * - Maintains single source of truth for customer data
 */
export const useCustomerStore = defineStore('customer', {
  state: (): {
    currentCustomer: Customer | null
    isLoading: boolean
  } => ({
    currentCustomer: null,
    isLoading: false
  }),

  actions: {
    async fetchCurrentCustomer() {
      this.isLoading = true
      try {
        const response = await api.get('/api/v2/account/customer')

        // Transform at API boundary
        const validated = transformResponse(
          apiRecordResponseSchema(customerInputSchema),
          response.data
        )

        // Store uses shared type with components
        this.currentCustomer = validated.record

      } catch (error) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details)
        }
        throw error
      } finally {
        this.isLoading = false
      }
    },

    async updateCustomer(updates: Partial<Customer>) {
      if (!this.currentCustomer?.custid) {
        throw new Error('No current customer to update')
      }

      try {
        const response = await api.put(
          `/api/v2/account/customer/${this.currentCustomer.custid}`,
          updates
        )

        // Transform response at API boundary
        const validated = transformResponse(
          apiRecordResponseSchema(customerInputSchema),
          response.data
        )

        // Update store with validated data
        this.currentCustomer = validated.record

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
