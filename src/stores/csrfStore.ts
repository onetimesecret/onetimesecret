// stores/csrfStore.ts

import { ApiError } from '@/schemas';
import { responseSchemas } from '@/schemas/api/responses';
import { defineStore } from 'pinia';

interface StoreState {
  isLoading: boolean;
  error: ApiError | null;
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
 * // Check if token is valid according to server
 * if (csrfStore.isValid) {
 *   // Proceed with protected action
 * } else {
 *   // Handle invalid token scenario
 * }
 */
export const useCsrfStore = defineStore('csrf', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    shrimp: window.shrimp || '',
    isValid: false,
    intervalChecker: null as number | null,
  }),

  actions: {
    handleError(error: unknown): ApiError {
      const apiError = {
        message: error instanceof Error ? error.message : 'CSRF validation error',
        code: 500,
        name: 'CsrfError',
      };
      console.error('[CSRF]', apiError.message, error);
      this.error = apiError;
      return apiError;
    },

    updateShrimp(newShrimp: string) {
      this.shrimp = newShrimp;
      window.shrimp = newShrimp;
    },

    async checkShrimpValidity() {
      try {
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
          throw this.handleError('Failed to validate CSRF token');
        }
      } catch (error) {
        this.isValid = false;
        throw this.handleError(error);
      }
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
      this.error = null;
      this.shrimp = '';
      this.isValid = false;
      this.$reset();
      this.stopPeriodicCheck();
    },
  },
});
