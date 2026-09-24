// src/shared/stores/receiptListStore.ts

import { responseSchemas } from '@/schemas/api/v3/responses';
import type { ReceiptList, ReceiptListDetails } from '@/schemas/shapes/v3/receipt';
import { gracefulParse } from '@/utils/schemaValidation';
import { useApi } from '@/shared/composables/useApi';
import type { AxiosRequestConfig } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, ref, type Ref } from 'vue';

/**
 * Options for filtering receipt list queries.
 */
export interface FetchListOptions {
  /**
   * Scope of the query: 'org' for organization, 'domain' for custom domain,
   * or undefined for customer
   */
  scope?: 'org' | 'domain';
  /** Required when scope is 'domain' - the external ID of the custom domain */
  domainExtid?: string;
  /** If true, errors will not trigger user notifications (for background refreshes) */
  silent?: boolean;
  /**
   * True when no person caused this fetch (a timer or a tab-visibility
   * refresh). The request is then declared passive and does not count as
   * session activity. Never set it for navigation or a user action.
   */
  passive?: boolean;
}

/**
 * Type definition for ReceiptListStore.
 */
export type ReceiptListStore = {
  // State
  _initialized: boolean;
  records: ReceiptList[];
  details: ReceiptListDetails | null;
  count: number | null;
  currentScope: FetchListOptions['scope'];
  scopeLabel: string | null;

  // Getters
  recordCount: number;
  isLoaded: boolean;

  // Actions
  fetchList: (options?: FetchListOptions) => Promise<void>;
  refreshRecords: (force?: boolean, options?: FetchListOptions) => Promise<void>;
  updateMemo: (id: string, memo: string) => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing receipt records and their related operations.
 * Handles fetching, caching, and state management of receipt listings.
 */

/* eslint max-lines-per-function: off */
export const useReceiptListStore = defineStore('receiptList', () => {
  const $api = useApi();

  // State
  const _initialized = ref(false);
  const records: Ref<ReceiptList[] | null> = ref(null);
  const details: Ref<ReceiptListDetails | null> = ref(null);
  const count = ref<number | null>(null);
  const currentScope = ref<FetchListOptions['scope']>(undefined);
  const scopeLabel = ref<string | null>(null);

  // Getters
  // Whether the list has been fetched. Not "init() has run": the auto-init
  // plugin runs init() at store creation, before anything is loaded.
  const isLoaded = computed(() => records.value !== null);
  const recordCount = () => count.value ?? 0;


  function init() {
    if (_initialized.value) return { isLoaded };

    _initialized.value = true;
    return { isLoaded };
  }

  async function fetchList(options: FetchListOptions = {}) {
    // Build query params based on options
    const params: Record<string, string> = {};
    if (options.scope) params.scope = options.scope;
    if (options.domainExtid) params.domain_extid = options.domainExtid;

    const config: AxiosRequestConfig = { params };
    if (options.passive === true) config.passive = true;

    const response = await $api.get('/api/v3/receipt/recent', config);

    const result = gracefulParse(
      responseSchemas.receiptList,
      response.data,
      'ReceiptListResponse'
    );

    if (!result.ok) {
      records.value = [];
      details.value = {} as ReceiptListDetails;
      count.value = 0;
      return null;
    }

    const validated = result.data;
    records.value = validated.records ?? [];
    details.value = (validated.details ?? {}) as ReceiptListDetails;
    count.value = validated.count ?? 0;
    currentScope.value = options.scope;
    scopeLabel.value = validated.details?.scope_label ?? null;

    return validated;
  }

  /**
   * Load the list unless it is already loaded; `force` reloads it.
   *
   * Gated on `isLoaded`, never on "init() has run": gating on that made this
   * a no-op in the running app (a direct visit to /recent showed an empty list).
   */
  async function refreshRecords(force = false, options: FetchListOptions = {}) {
    if (!force && isLoaded.value) return;

    await fetchList(options);
  }

  async function updateMemo(id: string, memo: string) {
    const response = await $api.patch(`/api/v3/receipt/${id}`, { memo });

    // Update the local record with the response from the API
    if (records.value && response.data?.record) {
      const updatedRecord = response.data.record;
      const index = records.value.findIndex((r) =>
        r.identifier === updatedRecord.identifier ||
        r.key === updatedRecord.key
      );

      if (index !== -1) {
        // Update just the memo field to preserve reactivity
        records.value[index].memo = updatedRecord.memo;
      }
    }

    return response.data;
  }

  /**
   * Reset store state to initial values.
   * Implementation of $reset() for setup stores since it's not automatically available.
   */
  function $reset() {
    records.value = null;
    details.value = null;
    count.value = null;
    currentScope.value = undefined;
    scopeLabel.value = null;
  }

  return {
    init,

    // State
    records,
    details,
    count,
    currentScope,
    scopeLabel,

    // Getters
    recordCount,
    isLoaded,

    // Actions
    fetchList,
    refreshRecords,
    updateMemo,
    $reset,
  };
});
