// stores/concealedMetadataStore.ts
import { PiniaPluginOptions } from '@/plugins/pinia';
import { loggingService } from '@/services/logging.service';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { ref, computed, watch } from 'vue';
import { type ConcealedMessage } from '@/types/ui/concealed-message';

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for ConcealedMetadataStore.
 */
export type ConcealedMetadataStore = {
  // State
  _initialized: boolean;
  concealedMessages: ConcealedMessage[];

  // Getters
  isInitialized: boolean;
  hasMessages: boolean;

  // Actions
  init: (options?: StoreOptions) => { isInitialized: boolean };
  addMessage: (message: ConcealedMessage) => void;
  clearMessages: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

// Local storage key for persisting concealed messages
const STORAGE_KEY = 'oneTimeSecret_concealedMessages';

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
 * Store for managing concealed metadata records during a user session.
 * This store persists links created during the current session so they
 * remain available when navigating between pages and browser refreshes.
 */
export const useConcealedMetadataStore = defineStore('concealedMetadata', () => {
  // State
  const _initialized = ref(false);
  const concealedMessages = ref<ConcealedMessage[]>(loadFromStorage());

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
   * Reset store state to initial values.
   * Implementation of $reset() for setup stores since it's not automatically available.
   * Also clears sessionStorage.
   */
  function $reset() {
    clearMessages();
    _initialized.value = false;
  }

  return {
    // State
    _initialized,
    concealedMessages,

    // Getters
    isInitialized,
    hasMessages,

    // Actions
    init,
    addMessage,
    clearMessages,
    $reset,
  };
});
