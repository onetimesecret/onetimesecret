// src/stores/authStore.ts
import { PiniaPluginOptions } from '@/plugins/pinia/types';
import { responseSchemas } from '@/schemas/api';
import { loggingService } from '@/services/logging.service';
import { WindowService } from '@/services/window.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref } from 'vue';

/**
 * Configuration for window state refresh behavior.
 *
 * The timing strategy uses two mechanisms:
 * 1. Base interval (15 minutes) for regular checks
 * 2. Random jitter (±90 seconds) to prevent synchronized client requests
 *    across multiple browser sessions, reducing server load spikes
 *
 * The /window endpoint provides complete state refresh including:
 * - Authentication status and customer data
 * - CSRF token (shrimp) refresh
 * - Configuration and feature flags
 * - i18n and domain settings
 *
 * Note: Exponential backoff was intentionally removed in favor of a simpler
 * "3 strikes" model because:
 * 1. Immediate logout after 3 failures provides clearer UX
 * 2. The 15-minute base interval already provides adequate spacing
 * 3. Backoff could mask serious issues by waiting longer between retries
 *
 * @note We created a new src/composables/useAuth.ts for auth operations (login,
 * signup, logout, password reset) and are keeping this authStore.ts focused
 * on session state management and periodic window state refresh.
 */
export const AUTH_CHECK_CONFIG = {
  INTERVAL: 15 * 60 * 1000,
  JITTER: 90 * 1000,
  MAX_FAILURES: 3,
  ENDPOINT: '/window',
} as const;

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for AuthStore.
 */
export type AuthStore = {
  // State
  isAuthenticated: boolean | null;
  authCheckTimer: ReturnType<typeof setTimeout> | null;
  failureCount: number | null;
  lastCheckTime: number | null;
  _initialized: boolean;

  // Getters
  needsCheck: boolean;
  isInitialized: boolean;

  // Actions
  init: () => { needsCheck: boolean; isInitialized: boolean };
  checkWindowStatus: () => Promise<boolean>;
  refreshAuthState: () => Promise<boolean>;
  setAuthenticated: (value: boolean) => Promise<void>;
  logout: () => Promise<void>;
  $scheduleNextCheck: () => void;
  $stopAuthCheck: () => Promise<void>;
  $dispose: () => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Authentication store for managing user authentication state.
 * Uses Pinia for state management, providing reactive auth state
 * that can be observed using storeToRefs:
 *
 * @example
 * ```ts
 * import { useAuthStore } from '@/stores/authStore'
 * import { storeToRefs } from 'pinia'
 *
 * const authStore = useAuthStore()
 * const { isAuthenticated } = storeToRefs(authStore)
 *
 * // React to auth state changes
 * watch(isAuthenticated, (newValue) => {
 *   console.log('Auth state changed:', newValue)
 * })
 * ```
 */
/* eslint-disable max-lines-per-function */
export const useAuthStore = defineStore('auth', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const isAuthenticated = ref<boolean | null>(null);
  const authCheckTimer = ref<ReturnType<typeof setTimeout> | null>(null);
  const failureCount = ref<number | null>(null);
  const lastCheckTime = ref<number | null>(null);
  const _initialized = ref(false);

  // Getters
  const needsCheck = computed((): boolean => {
    /**
     * Determines if the last auth check is older than the check interval.
     * Used to decide whether to perform a fresh check when a tab becomes visible.
     */
    if (!lastCheckTime.value) return true;
    return Date.now() - lastCheckTime.value > AUTH_CHECK_CONFIG.INTERVAL;
  });

  const isInitialized = computed(() => _initialized.value);

  // Actions

  function init(options?: StoreOptions) {
    if (_initialized.value) return { needsCheck, isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    const inputValue = WindowService.get('authenticated');

    // Regardless of what the value is, if it isn't exactly true, it's false.
    // i.e. unlimited ways to fail, only one way to succeed.
    isAuthenticated.value = inputValue === true;

    if (isAuthenticated.value) {
      lastCheckTime.value = Date.now(); // Add this
      $scheduleNextCheck();
    }

    _initialized.value = true;
    return { needsCheck, isInitialized };
  }

  /**
   * Checks the current authentication status with the server.
   *
   * @description
   * This method implements a robust authentication check mechanism:
   * 1. Validates current auth state with server
   * 2. Updates local and window state
   * 3. Manages failure counting
   *
   * Key behaviors:
   * - Automatic logout after MAX_FAILURES consecutive failures
   * - Resets failure counter on successful check
   * - Maintains sync between local and window state
   *
   * @returns Current authentication state
   */
  async function checkWindowStatus() {
    if (!isAuthenticated.value) return false;
    try {
      const response = await $api.get(AUTH_CHECK_CONFIG.ENDPOINT);

      // Update entire window state with fresh data
      if (window.__ONETIME_STATE__ && response.data) {
        window.__ONETIME_STATE__ = response.data;
      }

      // Update local auth state from refreshed window data
      isAuthenticated.value = response.data.authenticated || false;
      failureCount.value = 0;
      lastCheckTime.value = Date.now();

      return isAuthenticated.value;
    } catch {
      failureCount.value = (failureCount.value ?? 0) + 1;
      if (failureCount.value >= AUTH_CHECK_CONFIG.MAX_FAILURES) {
        logout();
      }
      return false;
    }
  }

  /**
   * Forces an immediate window state refresh and reschedules next check.
   * Useful when the application needs to ensure fresh auth and config state.
   */
  async function refreshAuthState() {
    return checkWindowStatus().then(() => {
      $scheduleNextCheck();
    });
  }

  /**
   * Schedules the next authentication check with a randomized interval.
   *
   * The random jitter added to the base interval helps prevent
   * synchronized requests from multiple clients hitting the server
   * at the same time, which could cause load spikes.
   *
   * The jitter is ±90 seconds, providing a good balance between
   * regular checks and load distribution.
   */
  function $scheduleNextCheck() {
    $stopAuthCheck();

    if (!isAuthenticated.value) return;

    const jitter = (Math.random() - 0.5) * 2 * AUTH_CHECK_CONFIG.JITTER;
    const nextCheck = AUTH_CHECK_CONFIG.INTERVAL + jitter;

    authCheckTimer.value = setTimeout(async () => {
      await checkWindowStatus();
      $scheduleNextCheck();
    }, nextCheck);
  }

  /**
   * Stops the periodic authentication check.
   * Clears the existing timeout and resets the authCheckTimer.
   */
  async function $stopAuthCheck() {
    if (authCheckTimer.value !== null) {
      clearTimeout(authCheckTimer.value);
      authCheckTimer.value = null;
    }
  }

  /**
   * Logs out the current user and resets the auth state.
   *
   * - Clearing cookies
   * - Resetting all related stores
   * - Clearing session storage
   * - Updating window state
   * Clears authentication state and storage.
   *
   * This method resets the store state to its initial values using `this.$reset()`.
   * It also clears session storage and stops any ongoing authentication checks.
   * This is typically used during logout to ensure that all user-specific data
   * is cleared and the store is returned to its default state.
   */
  async function logout() {
    await $stopAuthCheck();

    $reset();

    // Sync window state
    window.__ONETIME_STATE__ = undefined;

    deleteCookie('sess');
    deleteCookie('locale');

    // Clear all session storage;
    sessionStorage.clear();

    // Remove any and all lingering store state
    // context.pinia.state.value = {};
  }
  /**
   * Disposes of the store, stopping the auth check.
   *
   * - Disposing of a store does not reset its state. If you recreate the store,
   *   it will start with its initial state as defined in the store definition.
   * - Once a store is disposed of, it should not be used again.
   *
   */
  async function $dispose() {
    await $stopAuthCheck();
  }

  function $reset() {
    isAuthenticated.value = null;
    authCheckTimer.value = null;
    failureCount.value = null;
    lastCheckTime.value = null;
    _initialized.value = false;
  }

  /**
   * Sets the authenticated state and updates window state
   *
   * @param value - The authentication state to set
   */
  async function setAuthenticated(value: boolean) {
    isAuthenticated.value = value;

    if (value) {
      // Fetch fresh window state immediately to get customer data
      await checkWindowStatus();
    } else {
      await $stopAuthCheck();
    }

    // Sync window state flag
    if (window.__ONETIME_STATE__) {
      window.__ONETIME_STATE__.authenticated = value;
    }
  }

  return {
    // State
    isAuthenticated,
    authCheckTimer,
    failureCount,
    lastCheckTime,
    _initialized,

    // Getters
    needsCheck,
    isInitialized,

    // Actions
    init,
    checkWindowStatus,
    refreshAuthState,
    logout,
    setAuthenticated,

    $scheduleNextCheck,
    $stopAuthCheck,
    $dispose,
    $reset,
  };
});

const deleteCookie = (name: string) => {
  console.debug('Deleting cookie:', name);
  document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;`;
};
