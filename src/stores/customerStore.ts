// stores/customerStore.ts

import { useAsyncHandler } from '@/composables/useAsyncHandler';
import { ApiError } from '@/schemas';
import { responseSchemas } from '@/schemas/api/responses';
import type { Customer } from '@/schemas/models/customer';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

interface StoreState {
  isLoading: boolean;
  error: ApiError | null;
  currentCustomer: Customer | null;
  abortController: AbortController | null;
  _initialized: boolean;
}

export const useCustomerStore = defineStore('customer', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    currentCustomer: null,
    abortController: null,
    _initialized: false,
  }),

  getters: {
    getPlanSize(): number {
      const DEFAULT_SIZE = 10000;
      const customerPlan =
        this.currentCustomer?.plan ?? window.available_plans?.anonymous;
      return customerPlan?.options?.size ?? DEFAULT_SIZE;
    },
  },

  actions: {
    handleError(error: unknown): ApiError {
      const { handleError } = useAsyncHandler();
      this.error = handleError(error);
      return this.error;
    },

    /**
     * Cancels any in-flight customer data request.
     * Critical for:
     * - Preventing race conditions on rapid view switches
     * - Cleanup during logout
     * - Explicit cancellation when data is no longer needed
     */
    abortPendingRequest() {
      if (this.abortController) {
        this.abortController.abort();
        this.abortController = null;
      }
    },

    async fetchCurrentCustomer() {
      // Abort any pending request before starting new one
      this.abortPendingRequest();

      return await this.withLoading(async () => {
        this.abortController = new AbortController();
        const response = await api.get('/api/v2/account/customer', {
          signal: this.abortController.signal,
        });
        const validated = responseSchemas.customer.parse(response.data);
        this.currentCustomer = validated.record;
        this.error = null;
        this.abortController = null;
      });
    },

    async updateCustomer(updates: Partial<Customer>) {
      if (!this.currentCustomer?.custid) {
        // Use handleError instead of throwing directly
        return this.handleError(new Error('No current customer to update'));
      }

      try {
        const response = await api.put(
          `/api/v2/account/customer/${this.currentCustomer.custid}`,
          updates
        );
        const validated = responseSchemas.customer.parse(response.data);
        this.currentCustomer = validated.record;
      } catch (error) {
        this.handleError(error);
      }
    },
  },
});
