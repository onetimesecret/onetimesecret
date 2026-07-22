// src/shared/stores/csrfStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { defineStore, PiniaCustomProperties, storeToRefs } from 'pinia';
import { ref, watch } from 'vue';

interface StoreOptions extends PiniaPluginOptions {
  shrimp?: string;
}

/**
 * Store for managing CSRF token (shrimp) state.
 *
 * Key concepts:
 * - The current token is mirrored here from the bootstrap payload.
 * - Rotation is handled transparently by the axios response interceptor, and
 *   re-read from bootstrap when a native fetch bypasses axios.
 *
 * @example
 * import { useCsrfStore } from '@/stores/csrfStore';
 *
 * const csrfStore = useCsrfStore();
 *
 * // Read the current token (typically consumed by API interceptors / forms)
 * const token = csrfStore.shrimp;
 *
 * // Update token (typically handled by API interceptors)
 * csrfStore.updateShrimp(newToken);
 */

/**
 * Type definition for CsrfStore.
 */
export type CsrfStore = {
  // State
  shrimp: string;
  _initialized: boolean;

  // Actions
  init: () => void;
  updateShrimp: (newShrimp: string) => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useCsrfStore = defineStore('csrf', () => {
  const bootstrapStore = useBootstrapStore();
  const { shrimp: bootstrapShrimp, authenticated } = storeToRefs(bootstrapStore);

  // State
  const shrimp = ref('');
  const _initialized = ref(false);

  function init(options?: StoreOptions) {
    if (_initialized.value) return;
    shrimp.value = (options?.shrimp || bootstrapShrimp.value) ?? '';
    _initialized.value = true;

    // NOTE: There is deliberately no periodic or Page-Visibility CSRF
    // revalidation here. The token rotates transparently via the axios
    // response interceptor plus a refresh-before-submit path, so a client-side
    // validity probe adds no safety. The /api/v3/validate-shrimp endpoint was
    // intentionally NOT restored — see ADR-031 / issue #3839 before re-adding
    // any client-side polling.

    return _initialized;
  }

  // Auth-aware reset: clear CSRF state on logout
  watch(authenticated, (isAuthenticated) => {
    if (!isAuthenticated) {
      $reset();
    }
  });

  // Sync CSRF token when bootstrap refreshes (e.g., native fetch bypasses axios)
  watch(bootstrapShrimp, (newShrimp) => {
    if (newShrimp && _initialized.value) {
      shrimp.value = newShrimp;
    }
  });

  function updateShrimp(newShrimp: string) {
    shrimp.value = newShrimp;
  }

  /**
   * Resets store to initial state, including re-reading shrimp from bootstrap.
   * We read from bootstrapStore to maintain consistency with store
   * initialization and ensure predictable reset behavior across the app.
   */
  function $reset() {
    shrimp.value = bootstrapShrimp.value ?? '';
    _initialized.value = false;
  }

  return {
    // State
    shrimp,

    // Actions
    init,
    updateShrimp,
    $reset,
  };
});
