// stores/csrfStore.ts

import {
  createError,
  ErrorHandlerOptions,
  useErrorHandler,
} from '@/composables/useErrorHandler';
import { responseSchemas } from '@/schemas/api/responses';
import { createApi } from '@/utils';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';

interface StoreState {
  isLoading: boolean;
  shrimp: string;
  isValid: boolean;
  intervalChecker: number | null;
}

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
 * // Ask the server whether the token is valid
 * csrfStore.checkShrimpValidity().then(() => {});
 *
 */
export const useCsrfStore = defineStore('csrf', {
  state: (): StoreState => ({
    isLoading: false,
    shrimp: window.shrimp || '',
    isValid: false,
    intervalChecker: null as number | null,
  }),

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    _ensureErrorHandler() {
      if (!this._errorHandler) this.setupErrorHandler();
    },

    // Allow passing options during initialization
    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify, // Allow UI layer to handle notifications if provided
        log: options.log, // Allow custom logging if provided
      });
    },

    updateShrimp(newShrimp: string) {
      this.shrimp = newShrimp;
      window.shrimp = newShrimp;
    },

    async checkShrimpValidity() {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const response = await fetch('/api/v2/validate-shrimp', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'O-Shrimp': this.shrimp,
          },
        });

        if (response.ok) {
          const data = responseSchemas.csrf.parse(await response.json());
          this.isValid = data.isValid;
          if (data.shrimp) {
            this.updateShrimp(data.shrimp);
          }
        } else {
          throw createError('Failed to validate CSRF token', 'technical', 'error');
        }
      });
    },

    startPeriodicCheck(intervalMs: number = 60000) {
      this.stopPeriodicCheck();
      this.intervalChecker = window.setInterval(() => {
        this.checkShrimpValidity();
      }, intervalMs);
    },

    stopPeriodicCheck() {
      if (this.intervalChecker !== null) {
        clearInterval(this.intervalChecker);
        this.intervalChecker = null;
      }
    },

    reset() {
      this.isLoading = false;
      this.shrimp = '';
      this.isValid = false;
      this.$reset();
      this.stopPeriodicCheck();
    },
  },
});
