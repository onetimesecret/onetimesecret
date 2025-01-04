// stores/csrfStore.ts
import { AsyncHandlerOptions, useAsyncHandler } from '@/composables/useAsyncHandler';
import { responseSchemas } from '@/schemas/api/responses';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { handleError, ref } from 'vue';

/**
 * Store for managing CSRF token (shrimp) state and validation.
 *
 * Key concepts:
 * - Token validity is determined by server validation, not just presence
 * - Server returns both validity status and optionally a new token
 * - Periodic validation ensures token stays valid during session
 *
 * @example
 * import { useCsrfStore } from '@/stores/csrfStore';
 *
 * const csrfStore = useCsrfStore();
 *
 * // Start periodic validation
 * csrfStore.startPeriodicCheck(60000); // Check every minute
 *
 * // Stop validation when no longer needed
 * csrfStore.stopPeriodicCheck();
 *
 * // Update token (typically handled by API interceptors)
 * csrfStore.updateShrimp(newToken);
 *
 * // Check if token is valid according to server
 * if (csrfStore.isValid) {
 *   // Proceed with protected action
 * } else {
 *   // Handle invalid token scenario
 * }
 */

/* eslint-disable max-lines-per-function */
export const useCsrfStore = defineStore('csrf', () => {
  // State
  const isLoading = ref(false);
  const shrimp = ref('');
  const isValid = ref(false);
  const intervalChecker = ref<number | null>(null);
  const _initialized = ref(false);

  // Private state
  let _api: AxiosInstance | null = null;
  let _errorHandler: ReturnType<typeof useAsyncHandler> | null = null;

  // Actions
  function init(api?: AxiosInstance) {
    shrimp.value = window.shrimp || '';
    _ensureAsyncHandler(api);
  }

  function _ensureAsyncHandler(api?: AxiosInstance) {
    if (!_errorHandler) setupAsyncHandler(api);
  }

  function setupAsyncHandler(
    api: AxiosInstance = createApi(),
    options: AsyncHandlerOptions = {}
  ) {
    _api = api;
    _errorHandler = useAsyncHandler({
      setLoading: (loading) => (isLoading.value = loading),
      notify: options.notify,
      log: options.log,
      onError: () => {
        // Any error invalidates the token
        isValid.value = false;
      },
    });
  }

  function updateShrimp(newShrimp: string) {
    shrimp.value = newShrimp;
  }

  async function checkShrimpValidity() {
    _ensureAsyncHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!('/api/v2/validate-shrimp', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'O-Shrimp': shrimp.value,
        },
      });

      const validated = responseSchemas.csrf.parse(response.data);
      isValid.value = validated.isValid;
      if (validated.isValid) {
        updateShrimp(validated.shrimp);
      }
      return validated;
    });
  }

  function startPeriodicCheck(intervalMs: number = 60000) {
    stopPeriodicCheck();
    intervalChecker.value = window.setInterval(() => {
      checkShrimpValidity();
    }, intervalMs);
  }

  function stopPeriodicCheck() {
    if (intervalChecker.value !== null) {
      clearInterval(intervalChecker.value);
      intervalChecker.value = null;
    }
  }

  /**
   * Resets store to initial state, including re-reading window.shrimp.
   * We preserve window.shrimp behavior to maintain consistency with store
   * initialization and ensure predictable reset behavior across the app.
   */
  function $reset() {
    isLoading.value = false;
    shrimp.value = window.shrimp || ''; // back to how it all began
    isValid.value = false;
    _initialized.value = false;
    stopPeriodicCheck();
  }

  return {
    // State
    isLoading,
    shrimp,
    isValid,
    intervalChecker,

    // Actions
    init,
    handleError,
    updateShrimp,
    checkShrimpValidity,
    startPeriodicCheck,
    stopPeriodicCheck,
    $reset,
  };
});
