// src/shared/stores/concealedMetadataStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import { loggingService } from '@/services/logging.service';
import { type ConcealedMessage } from '@/types/ui/concealed-message';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { ref, computed, watch } from 'vue';

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for ConcealedMetadataStore.
 */
export type ConcealedMetadataStore = {
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
  clearMessages: () => void;
  setWorkspaceMode: (enabled: boolean) => void;
  toggleWorkspaceMode: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

// Local storage key for persisting concealed messages
const STORAGE_KEY = 'oneTimeSecret_concealedMessages';
const WORKSPACE_MODE_KEY = 'oneTimeSecret_workspaceMode';

/**
 * Loads concealed messages from sessionStorage
 */
function loadFromStorage(): ConcealedMessage[] {
  try {
    const stored = sessionStorage.getItem(STORAGE_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      // Ensure dates are properly restored as Date objects
      return parsed.map((message: any) => ({
        ...message,
        clientInfo: {
          ...message.clientInfo,
          createdAt: new Date(message.clientInfo.createdAt),
        },
      }));
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
 * Store for managing concealed metadata records during a user session.
 * This store persists links created during the current session so they
 * remain available when navigating between pages and browser refreshes.
 */
export const useConcealedMetadataStore = defineStore('concealedMetadata', () => {
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
   * Initializes the concealed metadata store.
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
   *
   * @param message The concealed message to add
   */
  function addMessage(message: ConcealedMessage) {
    // Check for existing message with the same ID and remove if found
    const existingIndex = concealedMessages.value.findIndex((m) => m.id === message.id);
    if (existingIndex !== -1) {
      concealedMessages.value.splice(existingIndex, 1);
    }

    // Add new message to the beginning of the array
    concealedMessages.value.unshift(message);
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
    clearMessages,
    setWorkspaceMode,
    toggleWorkspaceMode,
    $reset,
  };
});
