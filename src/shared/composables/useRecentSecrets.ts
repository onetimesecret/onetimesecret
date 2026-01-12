// src/shared/composables/useRecentSecrets.ts

import type { ApplicationError } from '@/schemas/errors';
import type { ReceiptRecords } from '@/schemas/api/account/endpoints/recent';
import type { ConcealedMessage } from '@/types/ui/concealed-message';
import { useAuthStore } from '@/shared/stores/authStore';
import { useConcealedReceiptStore } from '@/shared/stores/concealedReceiptStore';
import { useReceiptListStore } from '@/shared/stores/receiptListStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { computed, ref, watch, type ComputedRef, type Ref } from 'vue';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Unified record type for recent secrets display.
 * Abstracts differences between local (ConcealedMessage) and API (ReceiptRecords) sources.
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
  /** Whether the secret has been burned/destroyed */
  isBurned: boolean;
  /** Whether the secret has expired */
  isExpired: boolean;
  /** Original source data for advanced usage */
  source: 'local' | 'api';
  /** Original record for type-specific operations */
  originalRecord: ConcealedMessage | ReceiptRecords;
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
  fetch: () => Promise<void>;
  /** Clear all records */
  clear: () => void;
  /** Workspace mode toggle state (local mode only, always false for API mode) */
  workspaceMode: ComputedRef<boolean>;
  /** Toggle workspace mode (no-op for API mode) */
  toggleWorkspaceMode: () => void;
  /** Whether using authenticated API source */
  isAuthenticated: ComputedRef<boolean>;
}

/**
 * Transform a ConcealedMessage (local storage) to unified RecentSecretRecord
 */
function transformLocalRecord(message: ConcealedMessage): RecentSecretRecord {
  // Extract shortid from response if available
  const shortid = message.response?.record?.secret?.shortid ?? message.secret_identifier;

  return {
    id: message.id,
    extid: message.receipt_identifier,
    shortid,
    secretExtid: message.secret_identifier,
    hasPassphrase: message.clientInfo.hasPassphrase,
    ttl: message.clientInfo.ttl,
    createdAt: message.clientInfo.createdAt,
    shareDomain: message.response?.record?.share_domain ?? undefined,
    isViewed: false, // Local records start as not viewed
    isReceived: false, // Local records are never marked received
    isBurned: false, // Local records track this separately if needed
    isExpired: message.clientInfo.ttl <= 0,
    source: 'local',
    originalRecord: message,
  };
}

/**
 * Transform a ReceiptRecords (API) to unified RecentSecretRecord
 */
function transformApiRecord(record: ReceiptRecords): RecentSecretRecord {
  // Use shortid as the primary identifier; identifier is a fallback
  const id = record.shortid ?? record.identifier ?? '';
  const secretId = record.secret_shortid ?? '';
  const createdAt =
    record.created instanceof Date ? record.created : new Date();
  // extid uses identifier for receipt page URLs (not shortid)
  const extid = record.identifier ?? id;
  // Combine burned states using boolean OR to reduce complexity
  const isBurned = Boolean(record.is_burned || record.is_destroyed);

  return {
    id,
    extid,
    shortid: secretId,
    secretExtid: secretId,
    hasPassphrase: record.has_passphrase ?? false,
    ttl: record.secret_ttl ?? 0,
    createdAt,
    shareDomain: record.share_domain ?? undefined,
    isViewed: record.is_viewed ?? false,
    isReceived: record.is_received ?? false,
    isBurned,
    isExpired: record.is_expired ?? false,
    source: 'api',
    originalRecord: record,
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

  return {
    records,
    hasRecords,
    workspaceMode,
    fetch,
    clear,
    toggleWorkspaceMode,
  };
}

/**
 * Internal composable for API source (authenticated users)
 */
function useApiRecentSecrets(
  wrap: <T>(operation: () => Promise<T>) => Promise<T | undefined>
) {
  const store = useReceiptListStore();
  const { records: storeRecords } = storeToRefs(store);

  // Transform API records to unified format
  // Filter out records with missing secret_shortid to prevent broken share links
  const records = computed<RecentSecretRecord[]>(() => {
    if (!storeRecords.value) return [];
    return storeRecords.value
      .filter((record) => !!record.secret_shortid)
      .map(transformApiRecord);
  });

  const hasRecords = computed(() => records.value.length > 0);

  // Workspace mode is not applicable for API source
  const workspaceMode = computed(() => false);

  const fetch = async () => {
    await wrap(async () => {
      await store.fetchList();
    });
  };

  const clear = () => {
    store.$reset();
  };

  const toggleWorkspaceMode = () => {
    // No-op for API mode - workspace mode is a local-only feature
  };

  return {
    records,
    hasRecords,
    workspaceMode,
    fetch,
    clear,
    toggleWorkspaceMode,
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

  const fetch = async () => {
    error.value = null;
    if (isAuthenticated.value) {
      await api.fetch();
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

  return {
    records,
    isLoading,
    error,
    hasRecords,
    fetch,
    clear,
    workspaceMode,
    toggleWorkspaceMode,
    isAuthenticated,
  };
}
