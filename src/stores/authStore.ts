import router from '@/router'
import { Customer, CheckAuthDataApiResponse, CheckAuthDetails } from '@/types/onetime'
import axios from 'axios'
import { defineStore } from 'pinia'

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
    /** The currently authenticated customer, if any. */
    customer: undefined as Customer | undefined,
    /** Timeout for periodic authentication checks. */
    authCheckInterval: null as ReturnType<typeof setTimeout> | null,
    /** Current backoff interval for authentication checks. */
    currentBackoffInterval: BASE_AUTH_CHECK_INTERVAL_MS,
    /** Number of consecutive failed auth checks. */
    failedAuthChecks: 0,
  }),
  actions: {
    /**
     * Sets the authentication status and manages the auth check interval.
     * @param status - The new authentication status.
     */
    setAuthenticated(status: boolean) {
      this.isAuthenticated = status
      if (status) {
        this.startAuthCheck()
      } else {
        this.stopAuthCheck()
      }
    },

    /**
     * Sets the current customer.
     * @param customer - The customer object to set.
     */
    setCustomer(customer: Customer | undefined) {
      this.customer = customer
    },

    /**
     * Checks the current authentication status with the server.
     * Implements exponential backoff on failures and resets on success.
     */
    async checkAuthStatus() {
      try {
        const response = await axios.get<CheckAuthDataApiResponse & CheckAuthDetails>(AUTH_CHECK_ENDPOINT)
        this.isAuthenticated = response.data.details.authorized;
        this.customer = response.data.record;
        this.failedAuthChecks = 0;
        this.currentBackoffInterval = BASE_AUTH_CHECK_INTERVAL_MS;
      } catch (error) {
        this.failedAuthChecks++;
        this.currentBackoffInterval = Math.min(
          this.currentBackoffInterval * Math.pow(2, this.failedAuthChecks),
          MAX_AUTH_CHECK_INTERVAL_MS
        );
        if (this.failedAuthChecks >= 3) {
          this.logout()
        }
      } finally {
        this.startAuthCheck(); // Schedule the next check
      }
    },

    /**
     * Logs out the current user and resets the auth state.
     * Stops auth checks and redirects to the signin page.
     */
    logout() {
      this.isAuthenticated = false
      this.customer = undefined
      this.stopAuthCheck()
      // Perform any additional logout actions (e.g., clearing local storage, cookies)
      router.push('/signin')
    },

    /**
     * Starts the periodic authentication check with exponential backoff.
     * Uses a fuzzy interval to prevent synchronized requests from multiple clients.
     */
    startAuthCheck() {
      const intervalMillis = this.getFuzzyAuthCheckInterval();
      console.debug(`Starting auth check interval: ${intervalMillis}ms`);

      if (this.authCheckInterval === null) {
        this.authCheckInterval = setTimeout(() => {
          this.checkAuthStatus();
        }, intervalMillis);
      }
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
        clearTimeout(this.authCheckInterval)
        this.authCheckInterval = null
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
          if (error.response && error.response.status === 401) {
            this.logout()
          }
          return Promise.reject(error)
        }
      )
    },

    /**
     * Initializes the auth store.
     * Sets up the Axios interceptor, sets initial auth state, and customer data.
     */
    initialize() {
      this.setupAxiosInterceptor()
      const initialAuthState = window.authenticated ?? false
      this.setAuthenticated(initialAuthState)

      if (window.cust) {
        this.setCustomer(window.cust as Customer)
      }
    }
  }
})

/**
 * ABOUT PINIA'S storeToRefs
 *
 * The use of `storeToRefs` is an important concept in Pinia, and it's
 * worth explaining why you might want to use it:
 *
 * 1. Reactivity preservation:
 *    When you destructure properties directly from a Pinia store, you lose
 *    their reactivity. This means changes to these properties won't trigger
 *    re-renders in your components.
 *
 * 2. `storeToRefs` solution:
 *    `storeToRefs` is a utility function provided by Pinia that allows you
 *    to destructure reactive properties from the store while maintaining
 *    their reactivity.
 *
 * Here's an example to illustrate the difference:
 *
 * import { useAuthStore } from '@/stores/authStore'
 * import { storeToRefs } from 'pinia'
 *
 * // In a Vue component setup function or script setup
 * const authStore = useAuthStore()
 *
 * // Without storeToRefs (loses reactivity):
 * const { isAuthenticated, customer } = authStore
 * // Changes to isAuthenticated or customer won't trigger component updates
 *
 * // With storeToRefs (maintains reactivity):
 * const { isAuthenticated, customer } = storeToRefs(authStore)
 * // Changes to isAuthenticated or customer will trigger component updates
 *
 *
 * You would want to use `storeToRefs` in scenarios where:
 *
 * 1. You prefer destructured syntax for cleaner code.
 * 2. You need to use these properties in template expressions or computed
 *    properties.
 * 3. You want to pass these properties to child components while maintaining
 *    reactivity.
 *
 * Here's an example of how you might use it in a component:
 *
 * ```vue
 * <script setup lang="ts">
 * import { useAuthStore } from '@/stores/authStore'
 * import { storeToRefs } from 'pinia'
 *
 * const authStore = useAuthStore()
 * const { isAuthenticated, customer } = storeToRefs(authStore)
 *
 * // Now you can use isAuthenticated and customer reactively in your template
 * // or in computed properties
 * </script>
 *
 * <template>
 *   <div v-if="isAuthenticated">
 *     Welcome, {{ customer?.name }}!
 *   </div>
 * </template>
 * ```
 *
 * In this setup, changes to `isAuthenticated` or `customer` in the store
 * will automatically update your component's view.
 *
 * It's worth noting that you don't need to use `storeToRefs` for methods or
 * non-reactive properties. You can destructure those directly from the store
 * without losing functionality.
 *
 */
