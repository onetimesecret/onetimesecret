// stores/customerStore.ts

import { createApiError, zodErrorToApiError } from '@/schemas/api/errors';
import { responseSchemas } from '@/schemas/api/responses';
import type { Customer } from '@/schemas/models/customer';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';
import { z } from 'zod';

const api = createApi();
let abortController: AbortController | null = null;

export const useCustomerStore = defineStore('customer', {
  state: () => ({
    currentCustomer: null as Customer | null,
    isLoading: false,
  }),

  getters: {
    getPlanSize(): number {
      const DEFAULT_SIZE = 10000;
      const customerPlan = this.currentCustomer?.plan ?? window.available_plans?.anonymous;
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

    async fetchCurrentCustomer() {
      this.isLoading = true;
      abortController = new AbortController();
      const { signal } = abortController;

      try {
        const response = await api.get('/api/v2/account/customer', { signal });
        const validated = responseSchemas.customer.parse(response.data);
        this.currentCustomer = validated.record;
      } catch (error) {
        if (error instanceof Error && error.name === 'AbortError') {
          console.debug('Fetch aborted');
          return;
        }
        this.handleApiError(error);
      } finally {
        this.isLoading = false;
        abortController = null;
      }
    },

    abortFetchCurrentCustomer() {
      if (abortController) {
        abortController.abort();
      }
    },

    async updateCustomer(updates: Partial<Customer>) {
      if (!this.currentCustomer?.custid) {
        throw createApiError('VALIDATION', 'VALIDATION_ERROR', 'No current customer to update');
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
