// src/shared/stores/receiptStore.ts

import { createError } from '@/shared/composables/useAsyncHandler';
import { PiniaPluginOptions } from '@/plugins/pinia';
import { responseSchemas } from '@/schemas/api/v3/responses';
import { Receipt, ReceiptDetails } from '@/schemas/models/receipt';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref } from 'vue';

/**
 * API mode for endpoint selection.
 * - 'authenticated': Uses /api/v3/receipt/* endpoints (requires session)
 * - 'public': Uses /api/v3/guest/receipt/* endpoints (no auth required)
 */
export type ApiMode = 'authenticated' | 'public';

export const RECEIPT_STATUS = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  ORPHANED: 'orphaned',
} as const;

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for ReceiptStore.
 */
export type ReceiptStore = {
  // State
  record: Receipt | null;
  details: ReceiptDetails | null;
  apiMode: ApiMode;
  _initialized: boolean;

  // Getters
  isInitialized: boolean;
  canBurn: boolean;

  // Actions
  init: () => { isInitialized: boolean };
  fetch: (key: string) => Promise<void>;
  burn: (key: string, passphrase?: string) => Promise<void>;
  setApiMode: (mode: ApiMode) => void;
  $reset: () => void;
} & PiniaCustomProperties;

// eslint-disable-next-line max-lines-per-function -- Store definition naturally groups related functionality
export const useReceiptStore = defineStore('receipt', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<Receipt | null>(null);
  const details = ref<ReceiptDetails | null>(null);
  const _initialized = ref(false);
  const apiMode = ref<ApiMode>('authenticated');

  /**
   * Returns the appropriate endpoint path based on current API mode.
   * @param path - The path suffix (e.g., '/receipt/abc123')
   * @returns Full endpoint path with correct prefix
   */
  function getEndpoint(path: string): string {
    const prefix = apiMode.value === 'public' ? '/api/v3/guest' : '/api/v3';
    return `${prefix}${path}`;
  }

  /**
   * Sets the API mode for endpoint selection.
   * @param mode - 'authenticated' for /api/v3/receipt/*, 'public' for /api/v3/guest/receipt/*
   */
  function setApiMode(mode: ApiMode) {
    apiMode.value = mode;
  }

  // Getters
  const isInitialized = computed(() => _initialized.value);

  /**
   * Initializes the receipt store.
   * Idempotent - subsequent calls have no effect if already initialized.
   *
   * @returns Object containing initialization status
   */
  function init(options?: StoreOptions) {
    if (_initialized.value) return { isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;
    return { isInitialized };
  }

  const canBurn = computed((): boolean => {
    if (!record.value) return false;

    const validStates = [
      RECEIPT_STATUS.NEW,
      RECEIPT_STATUS.SHARED,
      RECEIPT_STATUS.VIEWED,
    ] as const;

    if (
      record.value.burned ||
      !validStates.includes(record.value.state as (typeof validStates)[number])
    ) {
      return false;
    }

    return true;
  });

  /**
   * Fetches receipt for given key from API.
   * Validates response against receipt schema using Zod.
   * Updates store state with validated response.
   *
   * @param key - Receipt identifier
   * @throws {ZodError} When response fails schema validation
   * @throws {AxiosError} When request fails
   */
  async function fetch(key: string) {
    const endpoint = getEndpoint(`/receipt/${key}`);
    const response = await $api.get(endpoint);
    const validated = responseSchemas.receipt.parse(response.data);
    record.value = validated.record;
    details.value = validated.details as any;
    return validated;
  }

  /**
   * Burns (destroys) receipt identified by key.
   * Validates current state allows burning via canBurn.
   * Updates store state with validated response.
   *
   * @param key - Receipt identifier
   * @param passphrase - Optional passphrase required for some secrets
   * @throws {ApplicationError} When receipt cannot be burned
   * @throws {ZodError} When response fails schema validation
   * @throws {AxiosError} When request fails
   */
  async function burn(key: string, passphrase?: string) {
    if (!canBurn.value) {
      throw createError('Cannot burn this receipt', 'human', 'error');
    }

    const endpoint = getEndpoint(`/receipt/${key}/burn`);
    const response = await $api.post(endpoint, {
      passphrase,
      continue: true,
    });

    const validated = responseSchemas.receipt.parse(response.data);
    record.value = validated.record;
    details.value = validated.details as any;

    return validated;
  }

  /**
   * Resets store state to initial values.
   * Clears record, details, API mode, and initialization status.
   */
  function $reset() {
    record.value = null;
    details.value = null;
    apiMode.value = 'authenticated';
    _initialized.value = false;
  }

  return {
    // State
    record,
    details,
    apiMode,

    // Getters
    canBurn,

    // Actions
    init,
    fetch,
    burn,
    setApiMode,
    $reset,
  };
});

// Legacy alias for backward compatibility during migration
// TODO: Remove after all consumers have been updated
export const useMetadataStore = useReceiptStore;
export const METADATA_STATUS = RECEIPT_STATUS;
export type MetadataStore = ReceiptStore;
