// src/shared/composables/useRecentSecrets.ts

import type { ReceiptRecords } from '@/schemas/api/account/endpoints/recent';
import type { ApplicationError } from '@/schemas/errors';
import { useAuthStore } from '@/shared/stores/authStore';
import { useConcealedReceiptStore } from '@/shared/stores/concealedReceiptStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { useReceiptListStore, type FetchListOptions } from '@/shared/stores/receiptListStore';
import type { LocalReceipt } from '@/types/ui/local-receipt';
import { storeToRefs } from 'pinia';
import { computed, ref, watch, type ComputedRef, type Ref } from 'vue';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Unified record type for recent secrets display.
 * Abstracts differences between local (LocalReceipt) and API (ReceiptRecords) sources.
 */
export interface RecentSecretRecord {
  /** Unique identifier for the record */
  id: string;
  /** External ID for URL routing (metadata identifier) */
  extid: string;
  /** Short ID for display (truncated version) */
  shortid: string;
  /** Secret identifier for the secret link */
  secretExtid: string;
  /** Whether the secret has a passphrase */
  hasPassphrase: boolean;
  /** TTL in seconds */
  ttl: number;
  /** Creation timestamp */
  createdAt: Date;
  /** Domain for share URL construction */
  shareDomain?: string;
  /** Whether the secret has been viewed */
  isViewed: boolean;
  /** Whether the secret has been received */
  isReceived: boolean;
  /** Whether the secret has been burned */
  isBurned: boolean;
  /** Whether the secret has expired */
  isExpired: boolean;
  /** Whether any of the burned, expired etc are true */
  isDestroyed: boolean;
  /** Original source data for advanced usage */
  source: 'local' | 'api';
  /** Original record for type-specific operations */
  originalRecord: LocalReceipt | ReceiptRecords;
  /** Optional user-defined memo for identifying the secret */
  memo?: string;
}

/**
 * Return type for useRecentSecrets composable
 */
export interface UseRecentSecretsReturn {
  /** Unified list of recent secret records */
  records: ComputedRef<RecentSecretRecord[]>;
  /** Loading state */
  isLoading: Ref<boolean>;
  /** Error state */
  error: Ref<ApplicationError | null>;
  /** Whether any records exist */
  hasRecords: ComputedRef<boolean>;
  /** Fetch/refresh records from source */
  fetch: (options?: FetchListOptions) => Promise<void>;
  /** Refresh receipt statuses from server (local mode only, updates isReceived/isBurned) */
  refreshStatuses: () => Promise<void>;
  /** Clear all records */
  clear: () => void;
  /** Update memo for a record (local mode only for now) */
  updateMemo: (id: string, memo: string) => void;
  /** Workspace mode toggle state (local mode only, always false for API mode) */
  workspaceMode: ComputedRef<boolean>;
  /** Toggle workspace mode (no-op for API mode) */
  toggleWorkspaceMode: () => void;
  /** Whether using authenticated API source */
  isAuthenticated: ComputedRef<boolean>;
  /** Current scope being displayed (org, domain, or undefined for customer) */
  currentScope: ComputedRef<FetchListOptions['scope']>;
  /** Label for the current scope (org name or domain name) */
  scopeLabel: ComputedRef<string | null>;
}

/**
 * Transform a LocalReceipt (local storage) to unified RecentSecretRecord
 */
function transformLocalRecord(message: LocalReceipt): RecentSecretRecord {
  const isReceived = message.isReceived ?? false;
  const isBurned = message.isBurned ?? false;
  const isExpired = message.createdAt + message.ttl * 1000 < Date.now();
  // isDestroyed means the secret is no longer accessible (received, burned, or expired)
  const isDestroyed = isReceived || isBurned || isExpired;

  return {
    id: message.id,
    extid: message.receiptExtid,
    shortid: message.secretShortid, // Use secret shortid for display, not receipt
    secretExtid: message.secretExtid,
    hasPassphrase: message.hasPassphrase,
    ttl: message.ttl,
    createdAt: new Date(message.createdAt),
    shareDomain: message.shareDomain ?? undefined,
    isViewed: isReceived, // For local records, viewed === received
    isReceived,
    isBurned,
    isExpired,
    isDestroyed,
    source: 'local',
    originalRecord: message,
    memo: message.memo,
  };
}

/**
 * Extract identifier fields from API record with defaults
 */
function extractApiRecordIds(record: ReceiptRecords) {
  // Use full identifier for API operations, shortid for display
  const id = record.identifier ?? record.shortid ?? '';
  const secretId = record.secret_identifier ?? record.secret_shortid ?? '';
  const extid = record.identifier ?? id;
  const shortid = record.secret_shortid ?? '';
  return { id, secretId, extid, shortid };
}

/**
 * Transform a ReceiptRecords (API) to unified RecentSecretRecord
 */
function transformApiRecord(record: ReceiptRecords): RecentSecretRecord {
  const { id, secretId, extid, shortid } = extractApiRecordIds(record);
  const createdAt = record.created instanceof Date ? record.created : new Date();
  // NOTE: is_destroyed is true for received, burned, expired, or orphaned states.
  // Use is_burned specifically for the burned state - don't combine with is_destroyed.
  const isBurned = Boolean(record.is_burned);
  const isDestroyed = Boolean(record.is_destroyed);

  return {
    id,
    extid,
    shortid,
    secretExtid: secretId,
    hasPassphrase: record.has_passphrase ?? false,
    ttl: record.secret_ttl ?? 0,
    createdAt,
    shareDomain: record.share_domain ?? undefined,
    isViewed: record.is_viewed ?? false,
    isReceived: record.is_received ?? false,
    isBurned,
    isExpired: record.is_expired ?? false,
    isDestroyed,
    source: 'api',
    originalRecord: record,
    memo: record.memo ?? undefined,
  };
}

/**
 * Internal composable for local storage source (guests/unauthenticated users)
 */
function useLocalRecentSecrets() {
  const store = useConcealedReceiptStore();
  const { concealedMessages, workspaceMode, hasMessages } = storeToRefs(store);

  // Transform local messages to unified format
  const records = computed<RecentSecretRecord[]>(() =>
    concealedMessages.value.map(transformLocalRecord)
  );

  const hasRecords = computed(() => hasMessages.value);

  const fetch = async () => {
    // Local storage is synchronous, no fetch needed
    // Initialize store if not already done
    if (!store.isInitialized) {
      store.init();
    }
  };

  const clear = () => {
    store.clearMessages();
  };

  const toggleWorkspaceMode = () => {
    store.toggleWorkspaceMode();
  };

  const updateMemo = (id: string, memo: string) => {
    store.updateMemo(id, memo);
  };

  const refreshStatuses = async () => {
    await store.refreshReceiptStatuses();
  };

  return {
    records,
    hasRecords,
    workspaceMode,
    fetch,
    refreshStatuses,
    clear,
    toggleWorkspaceMode,
    updateMemo,
  };
}

/**
 * Internal composable for API source (authenticated users)
 */
function useApiRecentSecrets(wrap: <T>(operation: () => Promise<T>) => Promise<T | undefined>) {
  const store = useReceiptListStore();
  const { records: storeRecords, currentScope, scopeLabel } = storeToRefs(store);

  // Transform API records to unified format
  // Filter out records with missing secret_shortid to prevent broken share links
  const records = computed<RecentSecretRecord[]>(() => {
    if (!storeRecords.value) return [];
    return storeRecords.value.filter((record) => !!record.secret_shortid).map(transformApiRecord);
  });

  const hasRecords = computed(() => records.value.length > 0);

  // Workspace mode is not applicable for API source
  const workspaceMode = computed(() => false);

  const fetch = async (options: FetchListOptions = {}) => {
    await wrap(async () => {
      await store.fetchList(options);
    });
  };

  const clear = () => {
    store.$reset();
  };

  const toggleWorkspaceMode = () => {
    // No-op for API mode - workspace mode is a local-only feature
  };

  const updateMemo = async (id: string, memo: string) => {
    await wrap(async () => {
      await store.updateMemo(id, memo);
    });
  };

  const refreshStatuses = async () => {
    // For API mode, fetch already returns fresh data from the server
    // No separate refresh needed
  };

  return {
    records,
    hasRecords,
    workspaceMode,
    fetch,
    refreshStatuses,
    clear,
    toggleWorkspaceMode,
    updateMemo,
    currentScope,
    scopeLabel,
  };
}

/**
 * Composable for managing recent secrets display.
 *
 * Abstracts the data source based on authentication state:
 * - Guest users: Uses sessionStorage via concealedReceiptStore
 * - Authenticated users: Uses API via receiptListStore
 *
 * Security: When authenticated, data is always fetched from the API.
 * This is more secure than local storage as the server enforces access controls.
 *
 * @example
 * ```ts
 * const {
 *   records,
 *   isLoading,
 *   hasRecords,
 *   fetch,
 *   clear,
 *   workspaceMode,
 *   toggleWorkspaceMode,
 * } = useRecentSecrets();
 *
 * // Fetch on mount
 * onMounted(() => fetch());
 *
 * // Use in template
 * // <div v-for="record in records" :key="record.id">
 * //   {{ record.extid }}
 * // </div>
 * ```
 */
// eslint-disable-next-line max-lines-per-function
export function useRecentSecrets(): UseRecentSecretsReturn {
  const authStore = useAuthStore();
  const notifications = useNotificationsStore();

  // Local state for async handling
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  // Determine authentication state
  const isAuthenticated = computed(() => authStore.isFullyAuthenticated);

  // Initialize both internal composables
  // Only one will be active based on auth state
  const local = useLocalRecentSecrets();
  const api = useApiRecentSecrets(wrap);

  // Clear local storage on auth state changes to prevent:
  // - Stale guest data mixing with authenticated API data on login
  // - Old secrets lingering after logout (unsettling UX)
  // flush: 'sync' ensures clearing happens immediately, not deferred
  watch(
    isAuthenticated,
    () => {
      local.clear();
    },
    { flush: 'sync' }
  );

  // Unified interface that switches based on auth state
  const records = computed<RecentSecretRecord[]>(() =>
    isAuthenticated.value ? api.records.value : local.records.value
  );

  const hasRecords = computed(() =>
    isAuthenticated.value ? api.hasRecords.value : local.hasRecords.value
  );

  const workspaceMode = computed(() =>
    isAuthenticated.value ? api.workspaceMode.value : local.workspaceMode.value
  );

  const fetch = async (options: FetchListOptions = {}) => {
    error.value = null;
    if (isAuthenticated.value) {
      await api.fetch(options);
    } else {
      await local.fetch();
    }
  };

  const clear = () => {
    if (isAuthenticated.value) {
      api.clear();
    } else {
      local.clear();
    }
  };

  const toggleWorkspaceMode = () => {
    if (isAuthenticated.value) {
      api.toggleWorkspaceMode();
    } else {
      local.toggleWorkspaceMode();
    }
  };

  const updateMemo = (id: string, memo: string) => {
    if (isAuthenticated.value) {
      api.updateMemo(id, memo);
    } else {
      local.updateMemo(id, memo);
    }
  };

  const refreshStatuses = async () => {
    if (isAuthenticated.value) {
      await api.refreshStatuses();
    } else {
      await local.refreshStatuses();
    }
  };

  // Scope properties (only relevant for authenticated users)
  const currentScope = computed(() =>
    isAuthenticated.value ? api.currentScope.value : undefined
  );

  const scopeLabel = computed(() =>
    isAuthenticated.value ? api.scopeLabel.value : null
  );

  return {
    records,
    isLoading,
    error,
    hasRecords,
    fetch,
    refreshStatuses,
    clear,
    updateMemo,
    workspaceMode,
    toggleWorkspaceMode,
    isAuthenticated,
    currentScope,
    scopeLabel,
  };
}
