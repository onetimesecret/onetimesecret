// stores/customerStore.ts
import { createError } from '@/composables/useAsyncHandler';
import { responseSchemas } from '@/schemas/api/responses';
import type { Customer } from '@/schemas/models/customer';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, handleError, ref } from 'vue';

/**
 * Type definition for CustomerStore.
 */
export type CustomerStore = {
  // State
  currentCustomer: Customer | null;
  abortController: AbortController | null;
  _initialized: boolean;

  // Getters
  getPlanSize: number;

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
  // State
  const currentCustomer = ref<Customer | null>(null);
  const abortController = ref<AbortController | null>(null);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const getPlanSize = computed(() => {
    const DEFAULT_SIZE = 10000;
    const customerPlan = currentCustomer.value?.plan ?? window.available_plans?.anonymous;
    return customerPlan?.options?.size ?? DEFAULT_SIZE;
  });

  // Actions

  function init(this: CustomerStore) {
    if (_initialized.value) return { isInitialized };

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
  function abort(this: CustomerStore) {
    if (abortController.value) {
      abortController.value.abort();
      abortController.value = null;
    }
  }

  /**
   * Fetches the current customer's data from the API.
   * @throws Will handle and set any errors encountered during the API call.
   */
  async function fetch(this: CustomerStore) {
    // Abort any pending request before starting a new one
    this.abort();

    abortController.value = new AbortController();
    const response = await this.$api.get('/api/v2/account/customer', {
      signal: abortController.value.signal,
    });
    const validated = responseSchemas.customer.parse(response.data);
    currentCustomer.value = validated.record;
  }

  /**
   * Updates the current customer's data with the provided updates.
   * @param updates - Partial customer data to update.
   * @throws Will handle and set any errors encountered during the API call.
   */
  async function updateCustomer(this: CustomerStore, updates: Partial<Customer>) {
    if (!currentCustomer.value?.custid) {
      // Use handleError instead of throwing directly
      throw createError('No current customer to update', 'human', 'error');
    }

    const response = await this.$api.put(
      `/api/v2/account/customer/${currentCustomer?.value?.custid}`,
      updates
    );
    const validated = responseSchemas.customer.parse(response.data);
    currentCustomer.value = validated.record;
  }

  /**
   * Resets the store state to its initial values.
   */
  function $reset(this: CustomerStore) {
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

    // Getters
    getPlanSize,

    // Actions
    handleError,
    abort,
    fetch,
    updateCustomer,
    $reset,
  };
});
