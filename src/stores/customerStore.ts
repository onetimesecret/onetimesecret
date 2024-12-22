// stores/customerStore.ts

import { createDomainError } from '@/schemas/api/errors';
import { responseSchemas } from '@/schemas/api/responses';
import type { Customer } from '@/schemas/models/customer';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

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
        throw createDomainError(
          'SERVER',
          'SERVER_ERROR',
          error instanceof Error ? error.message : 'Failed to fetch customer'
        );
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
        throw createDomainError('VALIDATION', 'VALIDATION_ERROR', 'No current customer to update');
      }

      try {
        const response = await api.put(
          `/api/v2/account/customer/${this.currentCustomer.custid}`,
          updates
        );
        const validated = responseSchemas.customer.parse(response.data);
        this.currentCustomer = validated.record;
      } catch (error) {
        throw createDomainError(
          'SERVER',
          'SERVER_ERROR',
          error instanceof Error ? error.message : 'Failed to update customer'
        );
      }
    },
  },
});
