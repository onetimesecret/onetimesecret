// stores/authStore.ts
import { useStoreError } from '@/composables/useStoreError';
import { ApiError, responseSchemas } from '@/schemas/api';
import { Customer } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';

const api = createApi();

/**
 * Configuration for authentication check behavior.
 *
 * The timing strategy uses two mechanisms:
 * 1. Base interval (15 minutes) for regular checks
 * 2. Random jitter (±90 seconds) to prevent synchronized client requests
 *    across multiple browser sessions, reducing server load spikes
 *
 * Note: Exponential backoff was intentionally removed in favor of a simpler
 * "3 strikes" model because:
 * 1. Immediate logout after 3 failures provides clearer UX
 * 2. The 15-minute base interval already provides adequate spacing
 * 3. Backoff could mask serious issues by waiting longer between retries
 */
const AUTH_CHECK_CONFIG = {
  /** Base interval between checks (15 minutes) */
  INTERVAL: 15 * 60 * 1000,
  /** Maximum random variation (±90 seconds) to prevent synchronized requests */
  JITTER: 90 * 1000,
  /** Number of consecutive failures before forced logout */
  MAX_FAILURES: 3,
  /** API endpoint for authentication checks */
  ENDPOINT: '/api/v2/authcheck',
} as const;

interface StoreState {
  // Base properties required for all stores
  isLoading: boolean;
  error: ApiError | null;
  // Auth-specific properties
  isAuthenticated: boolean;
  isCheckingAuth: boolean;
  customer: Customer | undefined;
  authCheckTimer: ReturnType<typeof setTimeout> | null;
  failureCount: number;
  lastCheckTime: number;
}

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
 * const { isAuthenticated, customer } = storeToRefs(authStore)
 *
 * // React to auth state changes
 * watch(isAuthenticated, (newValue) => {
 *   console.log('Auth state changed:', newValue)
 * })
 * ```
 */
export const useAuthStore = defineStore('auth', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    isAuthenticated: false,
    isCheckingAuth: false,
    customer: undefined,
    authCheckTimer: null,
    failureCount: 0,
    lastCheckTime: 0,
  }),

  getters: {
    /**
     * Determines if the last auth check is older than the check interval.
     * Used to decide whether to perform a fresh check when a tab becomes visible.
     */
    needsCheck(): boolean {
      return Date.now() - this.lastCheckTime > AUTH_CHECK_CONFIG.INTERVAL;
    },
  },

  actions: {
    /**
     * Initializes the auth store.
     * Sets up the visibility listener, sets initial auth state, and customer data.
     *
     * The visibility listener helps maintain auth state when tabs become
     * active after being inactive for extended periods.
     */
    async initialize() {
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && this.needsCheck) {
          this.checkAuthStatus();
        }
      });

      // Ensure boolean value and sync with window state
      this.isAuthenticated = Boolean(window.authenticated ?? false);
      if (window.cust) {
        this.customer = window.cust;
      }

      if (this.isAuthenticated) {
        this.lastCheckTime = Date.now();
        await this.checkAuthStatus(); // Initial check
        this.$scheduleNextCheck();
      }
    },

    handleError(error: unknown): ApiError {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      return this.error;
    },

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
    async checkAuthStatus() {
      if (!this.isAuthenticated) return false;
      this.isCheckingAuth = true;

      try {
        const response = await api.get(AUTH_CHECK_CONFIG.ENDPOINT);
        const validated = responseSchemas.checkAuth.parse(response.data);

        this.isAuthenticated = validated.details.authenticated;
        this.customer = validated.record;
        this.failureCount = 0;
        this.lastCheckTime = Date.now();

        // Keep window state in sync
        window.authenticated = this.isAuthenticated;
        window.cust = this.customer;

        return this.isAuthenticated;
      } catch (error) {
        this.handleError(error);
        this.failureCount++;

        if (this.failureCount >= AUTH_CHECK_CONFIG.MAX_FAILURES) {
          this.logout();
        }

        return false;
      } finally {
        this.isCheckingAuth = false;
      }
    },

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
    $scheduleNextCheck() {
      this.$stopAuthCheck();

      if (!this.isAuthenticated) return;

      const jitter = (Math.random() - 0.5) * 2 * AUTH_CHECK_CONFIG.JITTER;
      const nextCheck = AUTH_CHECK_CONFIG.INTERVAL + jitter;

      this.authCheckTimer = setTimeout(() => {
        this.checkAuthStatus();
        this.$scheduleNextCheck();
      }, nextCheck);
    },

    /**
     * Stops the periodic authentication check.
     * Clears the existing timeout and resets the authCheckTimer.
     */
    $stopAuthCheck() {
      if (this.authCheckTimer !== null) {
        clearTimeout(this.authCheckTimer);
        this.authCheckTimer = null;
      }
    },

    /**
     * Logs out the current user and resets the auth state.
     * Uses the global $logout plugin which handles:
     * - Clearing cookies
     * - Resetting all related stores
     * - Clearing session storage
     * - Updating window state
     */
    logout() {
      this.$stopAuthCheck();
      this.$logout();
    },

    /**
     * Forces an immediate auth check and reschedules next check.
     * Useful when the application needs to ensure fresh auth state.
     */
    async refreshAuthState() {
      return this.checkAuthStatus().then(() => {
        this.$scheduleNextCheck();
      });
    },
  },
});
