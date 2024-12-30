// stores/authStore.ts
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { responseSchemas } from '@/schemas/api';
import { ApplicationError } from '@/schemas/errors';
import { Customer } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
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
export const AUTH_CHECK_CONFIG = {
  /** Base interval between checks (15 minutes) */
  INTERVAL: 15 * 60 * 1000,
  /** Maximum random variation (±90 seconds) to prevent synchronized requests */
  JITTER: 90 * 1000,
  /** Number of consecutive failures before forced logout */
  MAX_FAILURES: 3,
  /** API endpoint for authentication checks */
  ENDPOINT: '/api/v2/authcheck',
} as const;

export interface StoreState {
  // Base properties required for all stores
  isLoading: boolean;
  error: ApplicationError | null;
  // Auth-specific properties
  isAuthenticated: boolean;
  isCheckingAuth: boolean;
  customer: Customer | undefined;
  authCheckTimer: ReturnType<typeof setTimeout> | null;
  failureCount: number | null;
  lastCheckTime: number | null;
  initialized: boolean;
  _visibilityHandler: ((this: Document, ev: Event) => void) | null;
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
    failureCount: null,
    lastCheckTime: null,
    initialized: false,
    _visibilityHandler: null,
  }),

  getters: {
    /**
     * Determines if the last auth check is older than the check interval.
     * Used to decide whether to perform a fresh check when a tab becomes visible.
     */
    needsCheck(state: StoreState): boolean {
      // First check if state exists
      if (!state) return true;

      // Then check lastCheckTime
      if (state.lastCheckTime === null) return true;

      return Date.now() - state.lastCheckTime > AUTH_CHECK_CONFIG.INTERVAL;
    },
  },

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    /**
     * Initializes the auth store.
     * Sets up the visibility listener, sets initial auth state, and customer data.
     *
     * The visibility listener helps maintain auth state when tabs become
     * active after being inactive for extended periods.
     */
    initialize() {
      if (this.initialized) return this;

      this.setupErrorHandler();

      // Set up visibility handler first
      const handler = this.handleVisibilityChange.bind(this);
      document.addEventListener('visibilitychange', handler);
      this._visibilityHandler = handler;

      // Then set initial state
      this._setInitialState();

      if (this.isAuthenticated) {
        this.$scheduleNextCheck();
      }

      this.initialized = true;
      return this;
    },

    _setupVisibilityHandler() {
      const handler = this.handleVisibilityChange.bind(this);
      document.addEventListener('visibilitychange', handler);
      this._visibilityHandler = handler;
    },

    _setInitialState() {
      this.$patch({
        isAuthenticated: Boolean(window.authenticated),
        customer: window.cust || undefined,
        initialized: true,
      });
    },

    // Add separate method for visibility handling
    handleVisibilityChange() {
      // Only check if document is visible AND we need a check
      if (
        document.visibilityState === 'visible' &&
        this.isAuthenticated &&
        this.needsCheck
      ) {
        // Ensure we call checkAuthStatus() directly
        void this.checkAuthStatus();
      }
    },

    // Add a separate method for async initialization if needed
    async initializeAsync() {
      this.initialize();
      if (this.isAuthenticated) {
        await this.checkAuthStatus();
      }
      return this;
    },

    // Separate method for async operations if needed
    async refreshInitialState() {
      if (this.isAuthenticated) {
        await this.checkAuthStatus();
        // Ensure lastCheckTime is set
        this.lastCheckTime = Date.now();
      }
    },

    _ensureErrorHandler() {
      if (!this._errorHandler) this.setupErrorHandler();
    },

    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify,
        log: options.log,
      });
    },

    /**
     * Checks the current authentication status with the server.
     *©196

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
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
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
      })
        .catch(() => {
          // Initialize failureCount if this is first failure
          this.failureCount = (this.failureCount ?? 0) + 1;
          if (this.failureCount >= AUTH_CHECK_CONFIG.MAX_FAILURES) {
            this.logout();
          }
          return false;
        })
        .finally(() => {
          this.isCheckingAuth = false;
        });
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

    // Add cleanup in $dispose
    $dispose() {
      if (this._visibilityHandler) {
        document.removeEventListener('visibilitychange', this._visibilityHandler);
        this._visibilityHandler = null;
      }
      this.$stopAuthCheck();
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
