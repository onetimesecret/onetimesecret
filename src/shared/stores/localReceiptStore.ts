// src/shared/stores/localReceiptStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import {
  guestReceiptsResponseSchema,
  localReceiptsArraySchema,
  type LocalReceipt,
} from '@/schemas/ui/local-receipt';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref, watch } from 'vue';

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for LocalReceiptStore.
 */
export type LocalReceiptStore = {
  // State
  _initialized: boolean;
  localReceipts: LocalReceipt[];
  workspaceMode: boolean;

  // Getters
  isInitialized: boolean;
  hasReceipts: boolean;

  // Actions
  init: (options?: StoreOptions) => { isInitialized: boolean };
  addReceipt: (receipt: LocalReceipt) => void;
  updateMemo: (id: string, memo: string) => void;
  markAsPreviewed: (secretExtid: string) => void;
  markAsRevealed: (secretExtid: string) => void;
  markAsBurned: (secretExtid: string) => void;
  refreshReceiptStatuses: () => Promise<boolean>;
  clearReceipts: () => void;
  setWorkspaceMode: (enabled: boolean) => void;
  toggleWorkspaceMode: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

// Local storage key for persisting receipts when not authenticated. It's
// actually session storage. Uses pascalCase convention (unlike cookies
// which use dot notation).
const STORAGE_KEY = 'onetimeReceiptCache';
const WORKSPACE_MODE_KEY = 'onetimeWorkspaceMode';
const MAX_STORED_RECEIPTS = 25;

/**
 * Loads local receipts from sessionStorage with schema validation.
 * Gracefully handles corrupted, tampered, or version-mismatched data.
 */
function loadFromStorage(): LocalReceipt[] {
  try {
    const stored = sessionStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      const result = localReceiptsArraySchema.safeParse(parsed);

      if (!result.success) {
        // Data is malformed - clear it and start fresh
        loggingService.warn(
          `Invalid local receipts in storage, clearing: ${result.error.message}`
        );
        sessionStorage.removeItem(STORAGE_KEY);
        return [];
      }

      // Filter out expired entries (createdAt + ttl has passed)
      const now = Date.now();
      return result.data.filter((r) => r.createdAt + r.ttl * 1000 > now);
    }
  } catch (error) {
    loggingService.error(new Error(`Failed to load local receipts from storage: ${error}`));
  }
  return [];
}

/**
 * Loads workspace mode preference from localStorage
 * Uses localStorage (not sessionStorage) so preference persists across sessions
 */
function loadWorkspaceModePreference(): boolean {
  try {
    const stored = localStorage.getItem(WORKSPACE_MODE_KEY);
    return stored === 'true';
  } catch (error) {
    loggingService.error(new Error(`Failed to load workspace mode preference: ${error}`));
  }
  return false;
}

/**
 * Store for managing local receipt records during a user session.
 * This store persists links created during the current session so they
 * remain available when navigating between pages and browser refreshes.
 */
// eslint-disable-next-line max-lines-per-function
export const useLocalReceiptStore = defineStore('localReceipt', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const _initialized = ref(false);
  const localReceipts = ref<LocalReceipt[]>(loadFromStorage());
  const workspaceMode = ref(loadWorkspaceModePreference());

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const hasReceipts = computed(() => localReceipts.value.length > 0);

  // Watch for changes to receipts and save to sessionStorage
  watch(
    localReceipts,
    (receipts) => {
      try {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(receipts));
      } catch (error) {
        loggingService.error(new Error(`Failed to save local receipts to storage: ${error}`));
      }
    },
    { deep: true }
  );

  // Watch for changes to workspaceMode and save to localStorage
  watch(workspaceMode, (enabled) => {
    try {
      localStorage.setItem(WORKSPACE_MODE_KEY, String(enabled));
    } catch (error) {
      loggingService.error(new Error(`Failed to save workspace mode preference: ${error}`));
    }
  });

  /**
   * Initializes the local receipt store.
   * Idempotent - subsequent calls have no effect if already initialized.
   *
   * @param options Optional store options
   * @returns Object containing initialization status
   */
  function init(options?: StoreOptions) {
    if (_initialized.value) return { isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;
    return { isInitialized };
  }

  /**
   * Adds a new local receipt to the store.
   * New receipts are added to the beginning of the list.
   * Enforces maximum storage limit.
   *
   * @param receipt The local receipt to add
   */
  function addReceipt(receipt: LocalReceipt) {
    // Remove any existing receipt with same ID
    const filtered = localReceipts.value.filter((r) => r.id !== receipt.id);
    // Add new receipt at beginning, enforce max limit
    localReceipts.value = [receipt, ...filtered].slice(0, MAX_STORED_RECEIPTS);
  }

  /**
   * Updates the memo for a specific receipt.
   * Empty string removes the memo.
   *
   * @param id The receipt ID to update
   * @param memo The new memo value
   */
  function updateMemo(id: string, memo: string) {
    const index = localReceipts.value.findIndex((r) => r.id === id);
    if (index !== -1) {
      const trimmed = memo.trim();
      if (trimmed) {
        localReceipts.value[index].memo = trimmed;
      } else {
        delete localReceipts.value[index].memo;
      }
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Marks a secret as previewed (link accessed, confirmation shown).
   * Called when the recipient accesses the secret link.
   *
   * @param secretExtid The secret external ID to mark as previewed
   */
  function markAsPreviewed(secretExtid: string) {
    const index = localReceipts.value.findIndex((r) => r.secretExtid === secretExtid);
    if (index !== -1) {
      localReceipts.value[index].isPreviewed = true;
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Marks a secret as revealed (content decrypted/consumed).
   * Called when the secret content is actually revealed to the recipient.
   *
   * @param secretExtid The secret external ID to mark as revealed
   */
  function markAsRevealed(secretExtid: string) {
    const index = localReceipts.value.findIndex((r) => r.secretExtid === secretExtid);
    if (index !== -1) {
      localReceipts.value[index].isRevealed = true;
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Marks a secret as burned (manually destroyed before being revealed).
   * Called when the creator burns the secret from the receipt page.
   *
   * @param secretExtid The secret external ID to mark as burned
   */
  function markAsBurned(secretExtid: string) {
    const index = localReceipts.value.findIndex((r) => r.secretExtid === secretExtid);
    if (index !== -1) {
      localReceipts.value[index].isBurned = true;
      // Trigger reactivity by replacing the array
      localReceipts.value = [...localReceipts.value];
    }
  }

  /**
   * Refreshes the status of all stored receipts from the server.
   * Calls POST /api/v3/guest/receipts with receipt identifiers to get current status.
   * Updates local storage with server state (isPreviewed, isRevealed, isBurned).
   *
   * @returns true if refresh succeeded, false if it failed (stale data shown)
   */
  async function refreshReceiptStatuses(): Promise<boolean> {
    if (localReceipts.value.length === 0) return true;

    // Send full receipt identifiers (receiptExtid) - backend uses Receipt.load_multi
    const identifiers = localReceipts.value.map((r) => r.receiptExtid);

    try {
      const response = await $api.post('/api/v3/guest/receipts', {
        identifiers,
      });

      // Validate API response with schema
      const parseResult = guestReceiptsResponseSchema.safeParse(response.data);
      if (!parseResult.success) {
        loggingService.error(
          new Error(`Invalid API response from guest/receipts: ${parseResult.error.message}`)
        );
        return false;
      }

      const { records } = parseResult.data;
      let hasUpdates = false;

      // Update local receipts with server status
      // Match on full receipt identifier (returned as 'identifier' in safe_dump)
      for (const serverRecord of records) {
        const localIndex = localReceipts.value.findIndex(
          (r) => r.receiptExtid === serverRecord.identifier
        );
        if (localIndex === -1) continue;

        const local = localReceipts.value[localIndex];
        // Only update if status changed
        if (serverRecord.is_previewed && !local.isPreviewed) {
          localReceipts.value[localIndex].isPreviewed = true;
          hasUpdates = true;
        }
        if (serverRecord.is_revealed && !local.isRevealed) {
          localReceipts.value[localIndex].isRevealed = true;
          hasUpdates = true;
        }
        if (serverRecord.is_burned && !local.isBurned) {
          localReceipts.value[localIndex].isBurned = true;
          hasUpdates = true;
        }
      }

      // Trigger reactivity if any updates occurred
      if (hasUpdates) {
        localReceipts.value = [...localReceipts.value];
      }
      return true;
    } catch (error) {
      loggingService.error(new Error(`Failed to refresh receipt statuses: ${error}`));
      return false;
    }
  }

  /**
   * Clears all local receipts from the store and sessionStorage.
   */
  function clearReceipts() {
    localReceipts.value = [];
    try {
      sessionStorage.removeItem(STORAGE_KEY);
    } catch (error) {
      loggingService.error(new Error(`Failed to clear local receipts from storage: ${error}`));
    }
  }

  /**
   * Sets the workspace mode preference.
   * When enabled, form stays on page after creation instead of navigating to receipt.
   *
   * @param enabled Whether workspace mode should be enabled
   */
  function setWorkspaceMode(enabled: boolean) {
    workspaceMode.value = enabled;
  }

  /**
   * Toggles the workspace mode preference.
   */
  function toggleWorkspaceMode() {
    workspaceMode.value = !workspaceMode.value;
  }

  /**
   * Reset store state to initial values.
   * Implementation of $reset() for setup stores since it's not automatically available.
   * Also clears sessionStorage.
   */
  function $reset() {
    clearReceipts();
    workspaceMode.value = false;
    _initialized.value = false;
  }

  return {
    // State
    _initialized,
    localReceipts,
    workspaceMode,

    // Getters
    isInitialized,
    hasReceipts,

    // Actions
    init,
    addReceipt,
    updateMemo,
    markAsPreviewed,
    markAsRevealed,
    markAsBurned,
    refreshReceiptStatuses,
    clearReceipts,
    setWorkspaceMode,
    toggleWorkspaceMode,
    $reset,
  };
});
