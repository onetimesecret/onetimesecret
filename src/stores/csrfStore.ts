import { type CsrfResponse } from '@/schemas/api/responses';
import { defineStore } from 'pinia';

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
  state: () => ({
    shrimp: window.shrimp || '',
    isValid: false,
    intervalChecker: null as number | null,
  }),

  actions: {
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
          const data = (await response.json()) as CsrfResponse;
          this.isValid = data.isValid;
          if (data.shrimp) {
            this.updateShrimp(data.shrimp);
          }
        } else {
          this.isValid = false;
        }
      } catch (error) {
        console.error('Failed to check CSRF token validity:', error);
        this.isValid = false;
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
  },
});
