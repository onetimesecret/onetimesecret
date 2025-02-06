// src/composables/useAsyncHandler.ts
import type { ApplicationError } from '@/schemas/errors';
import { classifyError, createError, errorGuards, wrapError } from '@/schemas/errors';
import { loggingService } from '@/services/logging.service';
import type {} from '@/stores/notificationsStore';
import type { NotificationSeverity } from '@/types/ui/notifications';
import { inject } from 'vue';
import { SENTRY_KEY, SentryInstance } from '@/plugins/core/enableDiagnotics';

export interface AsyncHandlerOptions {
  /**
   * Optional handler for user-facing notifications
   */
  notify?: ((message: string, severity: NotificationSeverity) => void) | false;
  /**
   * Optional error logging implementation
   */
  log?: ((error: ApplicationError) => void) | false;
  /**
   * Optional Sentry error tracking client
   */
  sentry?: SentryInstance;
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

export { createError, errorGuards, wrapError }; // Re-export for convenience

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
 * GlobalErrorBoundary that logs and notifies users of errors. The useDomainsManager
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
 *    const { wrap } = useAsyncHandler({
 *      notify: useNotifications(),
 *      setLoading: useLoadingState(),
 *      log: useLogger()
 *    });
 *
 *    // In an async operation:
 *    const data = await wrap(async () => {
 *      const response = await api.fetchData();
 *      return response.data;
 *    });
 * ```
 */
export function useAsyncHandler(options: AsyncHandlerOptions = {}) {
  const sentry = inject(SENTRY_KEY) as SentryInstance;

  // Default implementations that will be used if no options provided
  const handlers = {
    notify:
      options.notify === false || options.notify === null
        ? undefined
        : (options.notify ??
          ((message: string, severity: NotificationSeverity) => {
            loggingService.info(`[notify] [${severity}] ${message}`);
          })),
    // Only set default logger if log isn't explicitly false/null
    log:
      options.log === false || options.log === null
        ? undefined
        : (options.log ??
          ((error: ApplicationError) => {
            loggingService.error(error);
          })),
    setLoading: options.setLoading ?? (() => {}),
    onError: options.onError,
  };

  /**
   * Wraps an async operation with consistent error handling
   *
   * Key features:
   * - Loading state management
   * - Error classification and structured handling
   * - User notifications for human-facing errors
   * - Error logging and optional error callbacks
   * - Error boundary - stops error propagation
   *
   * @example
   * ```ts
   * const { wrap } = useAsyncHandler({
   *   notify: (msg, severity) => toast(msg, severity),
   *   setLoading: (isLoading) => store.setLoading(isLoading),
   *   onError: (error) => store.reset()
   * });
   *
   * // In a component or service:
   * const data = await wrap(() => api.fetchData());
   * ```
   */
  async function wrap<T>(operation: () => Promise<T>): Promise<T | undefined> {
    try {
      handlers.setLoading?.(true);
      return await operation();
    } catch (error) {
      const classifiedError = classifyError(error as Error);

      // Call onError callback before  everything else
      if (handlers.onError) {
        try {
          handlers.onError(classifiedError);
        } catch (callbackError) {
          // Log but don't throw callback errors
          handlers.log?.(classifyError(callbackError as Error));
        }
      }

      // Only log technical and security errors
      if (!errorGuards.isOfHumanInterest(classifiedError)) {
        handlers.log?.(classifiedError);

        if (sentry) {
          sentry.scope.captureException(error);
        }
      }

      // Notify for human-facing errors, but don't log
      if (errorGuards.isOfHumanInterest(classifiedError) && handlers.notify) {
        handlers.notify(classifiedError.message, classifiedError.severity);
      }

      return undefined;
    } finally {
      handlers.setLoading?.(false);
    }
  }

  return { wrap, wrapError, createError };
}
