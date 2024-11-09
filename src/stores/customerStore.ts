// src/stores/customerStore.ts
import { customerInputSchema, type Customer } from '@/schemas/models/customer';
import { apiRecordResponseSchema } from '@/types';
import { createApi } from '@/utils/api';
import {
  isTransformError,
  transformResponse,
} from '@/utils/transforms';
import { defineStore } from 'pinia';

//
// API Input (strings) -> Store/Component (shared types) -> API Output (serialized)
//                     ^                                 ^
//                     |                                 |
//                  transform                        serialize
//

const api = createApi()
let abortController: AbortController | null = null;

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

    /**
     * Fetches the current customer data from the API.
     * Sets the loading state to true while the request is in progress.
     * Uses an AbortController to allow the request to be canceled if needed.
     * Transforms and validates the response data before storing it in the state.
     * Handles errors, including data validation errors and request abort errors.
     */
    async fetchCurrentCustomer() {
      this.isLoading = true;
      abortController = new AbortController();
      const { signal } = abortController;

      try {
        const response = await api.get('/api/v2/account/customer', { signal });

        // Transform at API boundary
        const validated = transformResponse(
          apiRecordResponseSchema(customerInputSchema),
          response.data
        );

        // Store uses shared type with components
        this.currentCustomer = validated.record;

      } catch (error: Error | unknown) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details);
        } else if (error instanceof Error && error.name === 'AbortError') {
          console.debug('Fetch aborted');
        }

        throw error;
      } finally {
        this.isLoading = false;
        abortController = null; // Reset the controller
      }
    },

    /**
     * Aborts the ongoing fetchCurrentCustomer request if it exists.
     * This function should be called to cancel the fetch request when it is no longer needed.
     */
    abortFetchCurrentCustomer() {
      if (abortController) {
        abortController.abort();
      }
    },

    /**
     * Updates the current customer data with the provided updates.
     * Throws an error if there is no current customer to update.
     * Transforms and validates the response data before storing it in the state.
     * @param updates - Partial customer data to update
     */
    async updateCustomer(updates: Partial<Customer>) {
      if (!this.currentCustomer?.custid) {
        throw new Error('No current customer to update');
      }

      try {
        const response = await api.put(
          `/api/v2/account/customer/${this.currentCustomer.custid}`,
          updates
        );

        // Transform response at API boundary
        const validated = transformResponse(
          apiRecordResponseSchema(customerInputSchema),
          response.data
        );

        // Store uses shared type with components
        this.currentCustomer = validated.record;

      } catch (error: Error | unknown) {
        if (isTransformError(error)) {
          console.error('Data validation failed:', error.details);
        } else {
          throw error;
        }
      }
    }
  }
});
