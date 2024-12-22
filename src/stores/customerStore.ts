// stores/customerStore.ts
import { createApiError, zodErrorToApiError } from '@/schemas/api/errors';
import { responseSchemas } from '@/schemas/api/responses';
import type { Customer } from '@/schemas/models/customer';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';
import { z } from 'zod';

const api = createApi();

interface CustomerState {
  currentCustomer: Customer | null;
  isLoading: boolean;
  abortController: AbortController | null;
}

export const useCustomerStore = defineStore('customer', {
  state: (): CustomerState => ({
    currentCustomer: null,
    isLoading: false,
    abortController: null,
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
    handleApiError(error: unknown): never {
      if (error instanceof z.ZodError) {
        throw zodErrorToApiError(error);
      }
      throw createApiError(
        'SERVER',
        'SERVER_ERROR',
        error instanceof Error ? error.message : 'Unknown error occurred'
      );
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

      this.isLoading = true;
      this.abortController = new AbortController();

      try {
        const response = await api.get('/api/v2/account/customer', {
          signal: this.abortController.signal,
        });
        const validated = responseSchemas.customer.parse(response.data);
        this.currentCustomer = validated.record;
      } catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
          console.debug('Customer fetch aborted');
          return;
        }
        this.handleApiError(error);
      } finally {
        this.isLoading = false;
        this.abortController = null;
      }
    },

    async updateCustomer(updates: Partial<Customer>) {
      if (!this.currentCustomer?.custid) {
        throw createApiError(
          'VALIDATION',
          'VALIDATION_ERROR',
          'No current customer to update'
        );
      }

      try {
        const response = await api.put(
          `/api/v2/account/customer/${this.currentCustomer.custid}`,
          updates
        );
        const validated = responseSchemas.customer.parse(response.data);
        this.currentCustomer = validated.record;
      } catch (error) {
        this.handleApiError(error);
      }
    },
  },
});
