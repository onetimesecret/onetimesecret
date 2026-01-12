// src/shared/stores/authStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia/types';
import { classifyError, errorGuards } from '@/schemas/errors';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties, storeToRefs } from 'pinia';
import { computed, inject, ref } from 'vue';
import { useBootstrapStore } from './bootstrapStore';

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * AUTHENTICATION STATE MANAGEMENT
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * This store manages client-side authentication state and coordinates with
 * the server via the /bootstrap/me endpoint. It works in concert with:
 *
 * - useAuth composable: Handles auth operations (login, logout, signup)
 * - useMfa composable: Handles MFA setup and verification
 * - bootstrapStore: Provides reactive access to server-injected state
 * - Route guards: Enforce authentication requirements on navigation
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * AUTHENTICATION STATES
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * The system recognizes three distinct authentication states:
 *
 * 1. UNAUTHENTICATED (isAuthenticated=false, awaitingMfa=false)
 *    - No valid session
 *    - User sees: Sign In / Create Account links
 *    - Access: Public pages only
 *
 * 2. AWAITING MFA (isAuthenticated=false, awaitingMfa=true)
 *    - Password verified, OTP pending
 *    - Server returns authenticated=false until MFA completes
 *    - User sees: Limited menu with "Complete MFA" option
 *    - Access: MFA verification page only, guards redirect elsewhere to /mfa-verify
 *    - Session has awaiting_mfa=true flag from server
 *
 * 3. FULLY AUTHENTICATED (isAuthenticated=true, awaitingMfa=false)
 *    - All auth steps complete
 *    - User sees: Full navigation menu
 *    - Access: All authorized pages
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * STATE SYNCHRONIZATION (CRITICAL)
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * State is stored in bootstrapStore which is the single source of truth.
 *
 * When refreshing state from /bootstrap/me endpoint:
 * - ALWAYS use bootstrapStore.update() to update state
 * - All computed properties derive from bootstrapStore refs
 *
 * The awaitingMfa computed property reads from bootstrapStore. Route guards
 * will see updated values immediately after bootstrapStore.update().
 *
 * LOGIN WITH MFA: The login response includes mfa_required=true, so useAuth
 * updates bootstrapStore directly with awaiting_mfa=true. No /window fetch is
 * needed - the state flows naturally from the login response to the route guard.
 *
 * ───────────────────────────────────────────────────────────────────────────────
 * PERIODIC REFRESH CONFIGURATION
 * ───────────────────────────────────────────────────────────────────────────────
 *
 * The timing strategy uses two mechanisms:
 * 1. Base interval (15 minutes) for regular checks
 * 2. Random jitter (±90 seconds) to prevent synchronized client requests
 *    across multiple browser sessions, reducing server load spikes
 *
 * The /bootstrap/me endpoint provides complete state refresh including:
 * - Authentication status (authenticated, awaiting_mfa)
 * - Customer data and entitlements
 * - CSRF token (shrimp) refresh
 * - Configuration and feature flags
 *
 * Note: Exponential backoff was intentionally removed in favor of a simpler
 * "3 strikes" model because immediate logout after failures provides clearer UX.
 */
export const AUTH_CHECK_CONFIG = {
  INTERVAL: 15 * 60 * 1000,
  JITTER: 90 * 1000,
  MAX_FAILURES: 3,
  ENDPOINT: '/bootstrap/me',
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
  awaitingMfa: boolean;
  isFullyAuthenticated: boolean;
  isUserPresent: boolean;

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
  const bootstrapStore = useBootstrapStore();

  // Get reactive refs from bootstrapStore
  const {
    authenticated: bsAuthenticated,
    awaiting_mfa: bsAwaitingMfa,
    had_valid_session: bsHadValidSession,
    cust: bsCust,
    email: bsEmail,
  } = storeToRefs(bootstrapStore);

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

  /**
   * Whether user is awaiting MFA verification (password OK, OTP pending).
   * This is a transitional state between unauthenticated and fully authenticated.
   * Derives from bootstrapStore for reactivity.
   */
  const awaitingMfa = computed(() => bsAwaitingMfa.value ?? false);

  /**
   * Whether user has completed ALL authentication steps.
   * False if MFA is pending, even if password auth succeeded.
   * Use this for route protection and access control.
   */
  const isFullyAuthenticated = computed(() =>
    isAuthenticated.value === true && !awaitingMfa.value
  );

  /**
   * Whether a user is present (logged in partially or fully).
   * True for both MFA-pending and fully authenticated states.
   * Use this for UI decisions (show user menu, hide sign-in links).
   * Derives from bootstrapStore refs for reactivity.
   */
  const isUserPresent = computed(() => !!((isAuthenticated.value && bsCust.value) || (awaitingMfa.value && bsEmail.value)));

  // Actions

  function init(options?: StoreOptions) {
    if (_initialized.value) {
      loggingService.debug('[AuthStore.init] Already initialized, skipping');
      return { needsCheck, isInitialized };
    }

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    // Read from bootstrapStore refs (already hydrated from window state)
    const inputValue = bsAuthenticated.value;
    const hadValidSession = bsHadValidSession.value;
    const storedAuthState = sessionStorage.getItem('ots_auth_state');

    // Debug logging for auth initialization flow
    loggingService.debug('[AuthStore.init] Auth state from bootstrapStore:', {
      authenticated: inputValue,
      authenticatedType: typeof inputValue,
      hadValidSession,
      storedAuthState,
      bootstrapInitialized: bootstrapStore.isInitialized,
    });

    // Detect if this might be an error page masquerading as unauthenticated:
    // - Window says authenticated = false
    // - But server indicates there was a valid session (had_valid_session = true)
    // - And we have a recent auth state stored in sessionStorage
    // This scenario happens when server returns 500 error page which defaults
    // to authenticated = false even though the user has a valid session.
    // The server sets had_valid_session by checking the session cookie on its side.
    if (inputValue === false && hadValidSession === true && storedAuthState === 'true') {
      // Likely a server error page, preserve the stored auth state
      loggingService.warn(
        'Window state shows unauthenticated but server had valid session - ' +
        'likely server error page, preserving auth state'
      );
      isAuthenticated.value = true;
    } else {
      // Normal flow: trust window state
      // Regardless of what the value is, if it isn't exactly true, it's false.
      // i.e. unlimited ways to fail, only one way to succeed.
      isAuthenticated.value = inputValue === true;
    }

    // Store auth state for error recovery
    if (isAuthenticated.value) {
      sessionStorage.setItem('ots_auth_state', 'true');
      lastCheckTime.value = Date.now();
      $scheduleNextCheck();
    } else {
      sessionStorage.removeItem('ots_auth_state');
    }

    _initialized.value = true;

    // Debug logging for final auth state after init
    loggingService.debug('[AuthStore.init] Initialization complete:', {
      isAuthenticated: isAuthenticated.value,
      lastCheckTime: lastCheckTime.value,
      needsCheck: needsCheck.value,
      initialized: _initialized.value,
    });

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
   * - Allows refresh during MFA pending state (awaiting_mfa=true)
   *
   * @returns Current authentication state
   */
  async function checkWindowStatus() {
    // Allow refresh if authenticated OR if awaiting MFA completion.
    // When isAuthenticated is null (uncertain/initial state), we should verify.
    // Skip only when definitively unauthenticated and not awaiting MFA.
    const shouldSkip = isAuthenticated.value === false && !awaitingMfa.value;
    loggingService.debug('[AuthStore.checkWindowStatus] Called with state:', {
      isAuthenticated: isAuthenticated.value,
      isAuthenticatedType: typeof isAuthenticated.value,
      awaitingMfa: awaitingMfa.value,
      willSkip: shouldSkip,
    });

    if (shouldSkip) {
      loggingService.debug('[AuthStore.checkWindowStatus] Skipping check - user definitively not authenticated and not awaiting MFA');
      return false;
    }

    loggingService.debug('[AuthStore.checkWindowStatus] Making API call to /window');

    try {
      const response = await $api.get(AUTH_CHECK_CONFIG.ENDPOINT);

      // Update bootstrapStore with server response - single source of truth.
      // All computed properties derive from bootstrapStore refs, so route guards
      // and components will see updated values immediately.
      if (response.data) {
        bootstrapStore.update(response.data);
      }

      // Update local auth state from refreshed window data
      isAuthenticated.value = response.data.authenticated || false;
      failureCount.value = 0;
      lastCheckTime.value = Date.now();

      loggingService.debug('[AuthStore.checkWindowStatus] API response:', {
        authenticated: response.data.authenticated,
        awaiting_mfa: response.data.awaiting_mfa,
        newIsAuthenticated: isAuthenticated.value,
      });

      return isAuthenticated.value;
    } catch (error) {
      // Classify error and log technical/security errors
      const classified = classifyError(error);

      // Log technical/security errors (not human errors)
      if (!errorGuards.isOfHumanInterest(classified)) {
        loggingService.error(classified);
      }

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

    // Reset bootstrapStore to typed defaults - single source of truth
    bootstrapStore.$reset();

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
    sessionStorage.removeItem('ots_auth_state');
  }

  /**
   * Sets the authenticated state and refreshes window state from server.
   *
   * Called after successful authentication operations (login, MFA verification).
   * Triggers a /window refresh to get complete server state including:
   * - Customer data and entitlements
   * - Updated awaiting_mfa flag (critical for MFA flow completion)
   * - Fresh CSRF token
   *
   * @param value - The authentication state to set
   */
  async function setAuthenticated(value: boolean) {
    isAuthenticated.value = value;

    // Update sessionStorage for error recovery
    if (value) {
      sessionStorage.setItem('ots_auth_state', 'true');
      // Fetch fresh window state immediately to get customer data
      // and updated awaiting_mfa flag (critical after MFA verification)
      await checkWindowStatus();
    } else {
      sessionStorage.removeItem('ots_auth_state');
      await $stopAuthCheck();
    }

    // Sync flags via bootstrapStore for reactivity. When setting authenticated to true,
    // we also set awaiting_mfa to false. This optimistic update prevents getting
    // stuck if the subsequent checkWindowStatus() call fails.
    bootstrapStore.update({
      authenticated: value,
      ...(value ? { awaiting_mfa: false } : {}),
    });
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
    awaitingMfa,
    isFullyAuthenticated,
    isUserPresent,

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
  document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;`;
};
