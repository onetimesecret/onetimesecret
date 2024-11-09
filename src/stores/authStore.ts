
import { CheckAuthDataApiResponse, CheckAuthDetails, Customer } from '@/types';
import axios, { AxiosError } from 'axios';
import { defineStore } from 'pinia';

/**
 * Backoff Logic Summary:
 *
 * 1. Initial interval: Starts at BASE_AUTH_CHECK_INTERVAL_MS (15 minutes).
 *
 * 2. On successful auth check:
 *    - Reset failedAuthChecks to 0
 *    - Reset currentBackoffInterval to BASE_AUTH_CHECK_INTERVAL_MS
 *
 * 3. On failed auth check:
 *    - Increment failedAuthChecks
 *    - Double the currentBackoffInterval (capped at MAX_AUTH_CHECK_INTERVAL_MS)
 *    - If failedAuthChecks reaches 3, trigger logout
 *
 * 4. Fuzzy interval:
 *    - Add/subtract up to 90 seconds from currentBackoffInterval
 *    - Ensure final interval is between BASE_AUTH_CHECK_INTERVAL_MS and MAX_AUTH_CHECK_INTERVAL_MS
 *
 * 5. Next check scheduling:
 *    - Always schedule next check after current check completes (success or failure)
 *    - Use setTimeout with the calculated fuzzy interval
 *
 * This approach provides exponential backoff on failures, quick recovery on success,
 * and randomization to prevent synchronized requests from multiple clients.
 */

/** Base interval for authentication checks (15 minutes) */
const BASE_AUTH_CHECK_INTERVAL_MS = 15 * 60 * 1000;
/** Maximum interval for authentication checks (1 hour) */
const MAX_AUTH_CHECK_INTERVAL_MS = 60 * 60 * 1000;
/** Endpoint for authentication checks */
const AUTH_CHECK_ENDPOINT = '/api/v2/authcheck';

/**
 * Authentication store for managing user authentication state.
 *
 * @example
 * ```typescript
 * import { useAuthStore } from '@/stores/authStore'
 *
 * // In a Vue component setup function or script setup
 * const authStore = useAuthStore()
 *
 * // Initialize the store
 * authStore.initialize()
 *
 * // Check authentication status
 * await authStore.checkAuthStatus()
 *
 * // Access store state
 * console.log(authStore.isAuthenticated)
 * console.log(authStore.customer)
 *
 * // If you want to destructure reactive properties, use
 * // storeToRefs. See more info at the end of this file.
 * import { storeToRefs } from 'pinia'
 * const { isAuthenticated, customer } = storeToRefs(authStore)
 *
 * // Logout
 * authStore.logout()
 * ```
 */
export const useAuthStore = defineStore('auth', {
  state: () => ({
    /** Indicates whether the user is currently authenticated. */
    isAuthenticated: false,
    /** Add loading state */
    isCheckingAuth: false,
    /** The currently authenticated customer, if any. */
    customer: undefined as Customer | undefined,
    /** Timeout for periodic authentication checks. */
    authCheckInterval: null as ReturnType<typeof setTimeout> | null,
    /** Current backoff interval for authentication checks. */
    currentBackoffInterval: BASE_AUTH_CHECK_INTERVAL_MS,
    /** Number of consecutive failed auth checks. */
    failedAuthChecks: 0,
    lastAuthCheck: 0,
  }),
  getters: {
    isAuthStale(): boolean {
      return Date.now() - this.lastAuthCheck > BASE_AUTH_CHECK_INTERVAL_MS;
    },
  },
  actions: {
    /**
     * Initializes the auth store.
     * Sets up the Axios interceptor, visibility listener, sets initial auth state, and customer data.
     */
    initialize() {
      this.setupAxiosInterceptor();
      this.setupVisibilityListener();

      // Ensure boolean value and log
      const initialAuthState = Boolean(window.authenticated ?? false);

      this.isAuthenticated = initialAuthState;

      if (window.cust) {
        this.setCustomer(window.cust as Customer);
      }

      // Set initial lastAuthCheck if we start authenticated
      if (this.isAuthenticated) {
        this.lastAuthCheck = Date.now();
      }
    },

    /**
     * Sets up a visibility change listener to check auth status when tab becomes visible
     * after being inactive for a while.
     */
    setupVisibilityListener() {
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && this.isAuthStale) {
          this.refreshAuthState();
        }
      });
    },

    /**
     * Checks the current authentication status with the server.
     *
     * @description
     * This method implements a robust authentication check mechanism:
     * 1. Exponential backoff: Increases wait time between checks on consecutive failures.
     * 2. Graceful degradation: Handles authentication failures with increasing severity.
     * 3. Auto-recovery: Resets failure count and backoff interval on successful checks.
     *
     * Key behaviors:
     * - Immediate logout on 401 or 403 status codes.
     * - Applies exponential backoff for 500+ status codes.
     * - Logs out the user after 3 failed attempts.
     * - Resets failed check counter on success.
     *
     * Implications:
     *  + Allows immediate recovery after a successful check
     *  + Prevents accumulation of sporadic failures over time
     *  - May not accurately represent patterns of intermittent failures
     *  - Could potentially hide underlying issues if failures are frequent
     *    but not consecutive
     */
    async checkAuthStatus() {
      // If we already know we're not authenticated, don't make a request
      if (!this.isAuthenticated) {
        return false;
      }

      try {
        const response = await axios.get<CheckAuthDataApiResponse & CheckAuthDetails>(AUTH_CHECK_ENDPOINT);

        this.isAuthenticated = Boolean(response.data.details.authenticated);
        this.customer = response.data.record;

        this.failedAuthChecks = 0;
        this.currentBackoffInterval = BASE_AUTH_CHECK_INTERVAL_MS;
        this.lastAuthCheck = Date.now();

      } catch (error: unknown) {
        console.error('Auth check error:', error);
        this.handleAuthCheckError(error);

      } finally {
        if (this.isAuthenticated) {
          this.startAuthCheck();
        }
      }

      return this.isAuthenticated;
    },

    // Add method to force refresh auth state
    async refreshAuthState() {
      await this.checkAuthStatus();
    },

    /**
     * Applies exponential backoff to the current check interval.
     * Doubles the interval on each consecutive failure, up to MAX_AUTH_CHECK_INTERVAL_MS.
     */
    applyBackoff() {
      this.currentBackoffInterval = Math.min(
        this.currentBackoffInterval * Math.pow(2, this.failedAuthChecks),
        MAX_AUTH_CHECK_INTERVAL_MS
      );
    },

    /**
     * Handles authentication check errors with specific responses based on error type.
     *
     * Error handling strategy:
     * - 401/403: Immediate auth state update (unauthorized/forbidden)
     * - 500+: Apply exponential backoff for server errors
     * - After 3 consecutive failures: Force logout
     *
     * @param error - The error object from the failed auth check
     */
    handleAuthCheckError(error: unknown) {
      this.failedAuthChecks++;

      // Type guard and detailed error logging
      if (!(error instanceof AxiosError)) {
        console.error('Unexpected auth check error type:', error);
        this.isAuthenticated = false;
        return;
      }

      const statusCode = error.response?.status;
      const errorMessage = error.response?.data?.message || error.message;

      // Log detailed error information
      console.error('Auth check failed:', {
        statusCode,
        message: errorMessage,
        failedAttempts: this.failedAuthChecks,
      });

      // Handle specific HTTP status codes
      switch (statusCode) {
        case 401:
        case 403:
          // Authentication or authorization failure
          return this.$logout();

        case 500:
        case 502:
        case 503:
        case 504:
          // Server-side errors: apply backoff strategy
          this.applyBackoff();
          this.isAuthenticated = false;
          break;

        default:
          return this.$logout();
      }

      // Force logout after repeated failures - move this check to the top
      if (this.failedAuthChecks >= 3) {
        console.warn('Auth check failed 3 times, forcing logout');
        this.$logout();
        return;
      }

    },

    /**
     * Handles HTTP error responses, logging out the user if the status is 401 or 403.
     * This function can be extended to handle additional status codes as needed.
     *
     * @param error - The error object containing the HTTP response.
     */
    handleHttpError(error: AxiosError, withPessimism?: boolean): void {
      const status = error.response?.status || 0;
      const logoutStatuses = [401, 403];

      if (logoutStatuses.includes(status) || withPessimism) {
        this.logout();
      }
    },

    /**
     * Logs out the current user and resets the auth state.
     * Stops auth checks and redirects to the signin page.
     */
    logout() {
      // Use the global logout function
      this.$logout();
    },

    /**
     * Starts the periodic authentication check with exponential backoff.
     * Uses a fuzzy interval to prevent synchronized requests from multiple clients.
     */
    startAuthCheck() {
      this.stopAuthCheck(); // Clear any existing interval
      const intervalMillis = this.getFuzzyAuthCheckInterval();

      this.authCheckInterval = setTimeout(() => {
        this.checkAuthStatus();
      }, intervalMillis);
    },

    /**
     * Returns a fuzzy authentication check interval with exponential backoff.
     * Adds or subtracts up to 90 seconds to the current backoff interval.
     * Ensures the returned interval is between BASE_AUTH_CHECK_INTERVAL_MS and MAX_AUTH_CHECK_INTERVAL_MS.
     * @returns {number} Fuzzy authentication check interval in milliseconds.
     */
    getFuzzyAuthCheckInterval(): number {
      const maxFuzz = 90 * 1000; // 90 seconds in milliseconds
      const fuzz = Math.floor(Math.random() * (2 * maxFuzz + 1)) - maxFuzz;
      const interval = Math.min(this.currentBackoffInterval + fuzz, MAX_AUTH_CHECK_INTERVAL_MS);
      return Math.max(interval, BASE_AUTH_CHECK_INTERVAL_MS);
    },

    /**
     * Stops the periodic authentication check.
     * Clears the existing timeout and resets the authCheckInterval.
     */
    stopAuthCheck() {
      if (this.authCheckInterval !== null) {
        clearTimeout(this.authCheckInterval);
        this.authCheckInterval = null;
      }
    },

    /**
     * Sets up an Axios interceptor to handle 401 errors.
     * Automatically logs out the user on receiving a 401 response.
     */
    setupAxiosInterceptor() {
      axios.interceptors.response.use(
        (response) => response,
        (error) => {
          this.handleHttpError(error);
          return Promise.reject(error);
        }
      );
    },

    /**
     * Sets the authentication status and manages the auth check interval.
     * @param status - The new authentication status.
     */
    setAuthenticated(status: boolean) {
      this.isAuthenticated = status;
      if (status) {
        this.startAuthCheck();
      } else {
        this.stopAuthCheck();
      }
    },

    /**
     * Sets the current customer.
     * @param customer - The customer object to set.
     */
    setCustomer(customer: Customer | undefined) {
      this.customer = customer;
    },
  }
})
