// src/composables/useErrorHandler.ts

import type { ApplicationError, ErrorSeverity } from '@/schemas/errors';
import {
  classifyError,
  createError,
  isOfHumanInterest,
} from '@/schemas/errors/classifier';

export interface ErrorHandlerOptions {
  /**
   * Optional handler for user-facing notifications
   */
  notify?: (message: string, severity: ErrorSeverity) => void;
  /**
   * Optional error logging implementation
   */
  log?: (error: ApplicationError) => void;
  /**
   * Optional loading state handler
   */
  setLoading?: (isLoading: boolean) => void;
  /**
   * Optional callback for when an error occurs, called before error is thrown
   * Useful for state cleanup, invalidation, etc.
   */
  onError?: (error: ApplicationError) => void;
  debug?: boolean;
}

export { createError }; // Re-export createError

/**
 * Composable for handling async operations with consistent error handling.
 * Primarily used for API calls and other async operations that need:
 * - Loading state management
 * - Structured error classification
 * - User notifications for human-facing errors
 *
 * NOTE: For component-level error boundaries, use Vue's built-in
 * errorCaptured hook instead.
 *
 * We use the errorHandler composable across our pinia stores. We also have a global
 * ErrorHandlerPlugin that logs and notifies users of errors. The useDomainsManager
 * composable uses the errorHandler to for async errors. Other exceptions propogate
 * up to Vue 3 handle errors.
 *
 * Raison d'être:
 *
 * This composable exists to solve three specific problems in async operations:
 *
 * 1. Loading State Management
 *    - Automatically handles loading states for async operations
 *    - Ensures loading state is always cleared, even when errors occur
 *
 * 2. Structured Error Classification
 *    - Transforms various error types into a consistent ApplicationError format
 *    - Distinguishes between technical and human-facing errors
 *    - Enables consistent error handling patterns across the application
 *
 * 3. User Feedback
 *    - Automatically shows notifications for human-facing errors
 *    - Logs technical errors without user notification
 *
 * When NOT to use this composable:
 * - For component error boundaries (use Vue's errorCaptured hook)
 * - For global error handling (use Vue's app.config.errorHandler)
 * - For synchronous operations
 *
 * Example usage:
 *
 *    ```ts
 *    const { withErrorHandling } = useErrorHandler({
 *      notify: useNotifications(),
 *      setLoading: useLoadingState(),
 *      log: useLogger()
 *    });
 *
 *    // In an async operation:
 *    const data = await withErrorHandling(async () => {
 *      const response = await api.fetchData();
 *      return response.data;
 *    });
 * ```
 */
export function useErrorHandler(options: ErrorHandlerOptions = {}) {
  // Default implementations that will be used if no options provided
  const handlers = {
    notify:
      options.notify ??
      ((message: string, severity: ErrorSeverity) => {
        console.warn(`[${severity}] ${message}`);
      }),
    log:
      options.log ??
      ((error: ApplicationError) => {
        console.error('[ErrorHandler]', error);
      }),
    setLoading: options.setLoading ?? (() => {}),
    onError: options.onError,
  };

  /**
   * Wraps an async operation with consistent error handling
   *
   * @example
   * ```ts
   * const { withErrorHandling } = useErrorHandler({
   *   notify: (msg, severity) => toast(msg, severity),
   *   setLoading: (isLoading) => store.setLoading(isLoading)
   * });
   *
   * // In a component or service:
   * const data = await withErrorHandling(() => api.fetchData());
   * ```
   */
  async function withErrorHandling<T>(operation: () => Promise<T>): Promise<T> {
    try {
      handlers.setLoading?.(true);
      return await operation(); // <-- run the async operation
    } catch (error) {
      const classifiedError = classifyError(error);

      // Call onError callback first
      if (handlers.onError) {
        try {
          handlers.onError(classifiedError);
        } catch (callbackError) {
          // Log but don't throw callback errors to preserve original error
          handlers.log?.(classifyError(callbackError));
        }
      }

      // Log all errors regardless
      handlers.log?.(classifiedError);

      // Only notify for human-facing errors
      if (isOfHumanInterest(classifiedError) && handlers.notify) {
        try {
          handlers.notify(classifiedError.message, classifiedError.severity);
        } catch (notifyError) {
          // Swallow notification errors to preserve original error
          handlers.log?.(classifyError(notifyError));
        }
      }

      throw classifiedError;
    } finally {
      handlers.setLoading?.(false);
    }
  }

  return { withErrorHandling };
}
