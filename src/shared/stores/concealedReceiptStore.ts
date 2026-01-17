// src/shared/stores/concealedReceiptStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import { loggingService } from '@/services/logging.service';
import { type ConcealedMessage } from '@/types/ui/concealed-message';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, ref, watch } from 'vue';

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for ConcealedReceiptStore.
 */
export type ConcealedReceiptStore = {
  // State
  _initialized: boolean;
  concealedMessages: ConcealedMessage[];
  workspaceMode: boolean;

  // Getters
  isInitialized: boolean;
  hasMessages: boolean;

  // Actions
  init: (options?: StoreOptions) => { isInitialized: boolean };
  addMessage: (message: ConcealedMessage) => void;
  updateMemo: (id: string, memo: string) => void;
  clearMessages: () => void;
  setWorkspaceMode: (enabled: boolean) => void;
  toggleWorkspaceMode: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

// Local storage key for persisting receipts when not authenticated. It's
// actually session storage. Uses pascalCase convention (unlike cookies
// which use dot notation).
const STORAGE_KEY = 'onetimeReceiptCache';
const WORKSPACE_MODE_KEY = 'onetimeWorkspaceMode';
const MAX_STORED_RECEIPTS = 20;

/**
 * Loads concealed messages from sessionStorage
 */
function loadFromStorage(): ConcealedMessage[] {
  try {
    const stored = sessionStorage.getItem(STORAGE_KEY);
    if (stored) {
      const now = Date.now();
      const parsed = JSON.parse(stored) as ConcealedMessage[];
      // Filter out expired entries (createdAt + ttl has passed)
      return parsed.filter((m) => m.createdAt + m.ttl * 1000 > now);
    }
  } catch (error) {
    loggingService.error(new Error(`Failed to load concealed messages from storage: ${error}`));
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
 * Store for managing concealed receipt records during a user session.
 * This store persists links created during the current session so they
 * remain available when navigating between pages and browser refreshes.
 */
// eslint-disable-next-line max-lines-per-function
export const useConcealedReceiptStore = defineStore('concealedReceipt', () => {
  // State
  const _initialized = ref(false);
  const concealedMessages = ref<ConcealedMessage[]>(loadFromStorage());
  const workspaceMode = ref(loadWorkspaceModePreference());

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const hasMessages = computed(() => concealedMessages.value.length > 0);

  // Watch for changes to messages and save to sessionStorage
  watch(
    concealedMessages,
    (messages) => {
      try {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(messages));
      } catch (error) {
        loggingService.error(new Error(`Failed to save concealed messages to storage: ${error}`));
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
   * Initializes the concealed receipt store.
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
   * Adds a new concealed message to the store.
   * New messages are added to the beginning of the list.
   * Enforces maximum storage limit.
   *
   * @param message The concealed message to add
   */
  function addMessage(message: ConcealedMessage) {
    // Remove any existing message with same ID
    const filtered = concealedMessages.value.filter((m) => m.id !== message.id);
    // Add new message at beginning, enforce max limit
    concealedMessages.value = [message, ...filtered].slice(0, MAX_STORED_RECEIPTS);
  }

  /**
   * Updates the memo for a specific message.
   * Empty string removes the memo.
   *
   * @param id The message ID to update
   * @param memo The new memo value
   */
  function updateMemo(id: string, memo: string) {
    const index = concealedMessages.value.findIndex((m) => m.id === id);
    if (index !== -1) {
      const trimmed = memo.trim();
      if (trimmed) {
        concealedMessages.value[index].memo = trimmed;
      } else {
        delete concealedMessages.value[index].memo;
      }
      // Trigger reactivity by replacing the array
      concealedMessages.value = [...concealedMessages.value];
    }
  }

  /**
   * Clears all concealed messages from the store and sessionStorage.
   */
  function clearMessages() {
    concealedMessages.value = [];
    try {
      sessionStorage.removeItem(STORAGE_KEY);
    } catch (error) {
      loggingService.error(new Error(`Failed to clear concealed messages from storage: ${error}`));
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
    clearMessages();
    workspaceMode.value = false;
    _initialized.value = false;
  }

  return {
    // State
    _initialized,
    concealedMessages,
    workspaceMode,

    // Getters
    isInitialized,
    hasMessages,

    // Actions
    init,
    addMessage,
    updateMemo,
    clearMessages,
    setWorkspaceMode,
    toggleWorkspaceMode,
    $reset,
  };
});
