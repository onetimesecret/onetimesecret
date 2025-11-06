// src/stores/customerStore.ts
import { createError } from '@/composables/useAsyncHandler';
import { PiniaPluginOptions } from '@/plugins/pinia';
import { responseSchemas } from '@/schemas/api/v3/responses';
import type { Customer } from '@/schemas/models/customer';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, handleError, inject, ref } from 'vue';

/**
 * Type definition for CustomerStore.
 */
export type CustomerStore = {
  // State
  currentCustomer: Customer | null;
  abortController: AbortController | null;
  _initialized: boolean;

  // Actions
  abort: () => void;
  fetch: () => Promise<void>;
  updateCustomer: (updates: Partial<Customer>) => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing customer data, including current customer information and related actions.
 */
/* eslint-disable max-lines-per-function */
export const useCustomerStore = defineStore('customer', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const currentCustomer = ref<Customer | null>(null);
  const abortController = ref<AbortController | null>(null);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);

  // Actions

  interface StoreOptions extends PiniaPluginOptions {}

  function init(options?: StoreOptions) {
    if (_initialized.value) return { isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;

    return { isInitialized };
  }

  /**
   * Cancels any in-flight customer data request.
   * Critical for:
   * - Preventing race conditions on rapid view switches
   * - Cleanup during logout
   * - Explicit cancellation when data is no longer needed
   */
  function abort() {
    if (abortController.value) {
      abortController.value.abort();
      abortController.value = null;
    }
  }

  /**
   * Fetches the current customer's data from the API.
   * @throws Will handle and set any errors encountered during the API call.
   */
  async function fetch() {
    // Abort any pending request before starting a new one
    abort();

    abortController.value = new AbortController();
    const response = await $api.get('/api/account/account/customer', {
      signal: abortController.value.signal,
    });
    const validated = responseSchemas.customer.parse(response.data);
    currentCustomer.value = validated.record as Customer;
  }

  /**
   * Updates the current customer's data with the provided updates.
   * @param updates - Partial customer data to update.
   * @throws Will handle and set any errors encountered during the API call.
   */
  async function updateCustomer(updates: Partial<Customer>) {
    if (!currentCustomer.value?.objid) {
      // Use handleError instead of throwing directly
      throw createError('No current customer to update', 'human', 'error');
    }

    const response = await $api.put(
      `/api/account/customer/${currentCustomer?.value?.objid}`,
      updates
    );
    const validated = responseSchemas.customer.parse(response.data);
    currentCustomer.value = validated.record as Customer;
  }

  /**
   * Resets the store state to its initial values.
   */
  function $reset() {
    currentCustomer.value = null;
    abortController.value = null;
    _initialized.value = false;
  }

  return {
    // State
    init,
    currentCustomer,
    abortController,
    _initialized,

    // Actions
    handleError,
    abort,
    fetch,
    updateCustomer,
    $reset,
  };
});
