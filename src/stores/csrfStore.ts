import { defineStore } from 'pinia';

/**
 * Store for managing CSRF token (shrimp) state and validation.
 *
 * @example
 * import { useCsrfStore } from '@/stores/csrfStore';
 *
 * const csrfStore = useCsrfStore();
 *
 * // Start periodic checks
 * csrfStore.startPeriodicCheck(60000); // Check every minute
 *
 * // Stop checks when no longer needed
 * csrfStore.stopPeriodicCheck();
 *
 * // Update the token
 * csrfStore.updateShrimp(newToken);
 *
 * // Check if the token is valid
 * if (csrfStore.isValid) {
 *   // Proceed with protected action
 * } else {
 *   // Handle invalid token scenario
 * }
 */
export const useCsrfStore = defineStore('csrf', {
  state: () => ({
    /** The current CSRF token */
    shrimp: window.shrimp || '',
    /** Whether the current token is valid */
    isValid: true,
    /** ID of the interval timer for periodic checks */
    checkInterval: null as number | null,
  }),
  actions: {
    /**
     * Updates the CSRF token (shrimp).
     * @param {string} newShrimp - The new CSRF token.
     */
    updateShrimp(newShrimp: string) {
      this.shrimp = newShrimp;
      window.shrimp = newShrimp;
      this.isValid = true;
    },

    /**
     * Checks the validity of the current CSRF token with the server.
     *
     * Expected server API:
     * - Endpoint: '/api/v2/check-shrimp'
     * - Method: POST
     * - Headers:
     *   - 'Content-Type': 'application/json'
     *   - 'O-Shrimp': The current token
     * - Response: JSON object with `isValid` boolean property
     *
     * @example
     * // Server-side pseudocode (Python with Flask)
     * @app.route('/api/v2/check-shrimp', methods=['POST'])
     * def check_csrf_token():
     *     token = request.headers.get('O-Shrimp')
     *     is_valid = validate_csrf_token(token)  # Your validation logic
     *     return jsonify({'isValid': is_valid})
     */
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
          const data = await response.json();
          this.isValid = data.isValid;
        } else {
          this.isValid = false;
        }
      } catch (error) {
        console.error('Failed to check CSRF token validity:', error);
        this.isValid = false;
      }
    },

    /**
     * Starts periodic checks of the CSRF token validity.
     * @param {number} intervalMs - The interval in milliseconds between checks. Defaults to 60000 (1 minute).
     */
    startPeriodicCheck(intervalMs: number = 60000) {
      this.stopPeriodicCheck();
      this.checkInterval = window.setInterval(() => {
        this.checkShrimpValidity();
      }, intervalMs);
    },

    /**
     * Stops the periodic checks of the CSRF token validity.
     */
    stopPeriodicCheck() {
      if (this.checkInterval !== null) {
        clearInterval(this.checkInterval);
        this.checkInterval = null;
      }
    },
  },
});
