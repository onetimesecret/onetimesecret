// src/plugins/core/globalErrorBoundary.ts
//
import { AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import { classifyError, errorGuards } from '@/schemas/errors';
import { loggingService } from '@/services/logging.service';
import type { App, Plugin } from 'vue';
import { inject } from 'vue';
import { SENTRY_KEY, SentryInstance } from './enableDiagnostics';

interface ErrorBoundaryOptions extends AsyncHandlerOptions {
  debug?: boolean;
}

/**
 * Creates a Vue plugin that provides global error handling
 *
 * @param {ErrorBoundaryOptions} options - Configuration options
 * @returns {Plugin} Vue plugin instance
 *
 * @example
 * ```ts
 * const errorBoundary = createErrorBoundary({
 *   debug: true,
 *   notify: (msg, severity) => notifications.add(msg, severity)
 * });
 * app.use(errorBoundary);
 * ```
 */
export function createErrorBoundary(options: ErrorBoundaryOptions = {}): Plugin {
  return {
    install(app: App) {
      /**
       * Vue 3 global error handler
       *
       * @param error: The error that was thrown
       * @param instance: The component instance that triggered the error
       * @param info: A string containing information about where the error was caught
       *
       * @see https://vuejs.org/api/application#app-config-errorhandler
       */
      app.config.errorHandler = (error, instance, info) => {
        const sentryInstance = inject(SENTRY_KEY, null) as SentryInstance | null;

        if (!sentryInstance?.client) {
          console.debug('Sentry not initialized');
          return;
        }

        const { scope } = sentryInstance;

        const classifiedError = classifyError(error);
        loggingService.error(error as Error);

        // Only notify user for human-facing errors
        if (errorGuards.isOfHumanInterest(classifiedError) && options.notify) {
          options.notify(classifiedError.message, classifiedError.severity);
        }

        console.debug('[GlobalErrorBoundary] Sending to Sentry', { scope, error });
        scope.captureException(error);

        if (options.debug) {
          loggingService.debug('[ErrorContext]', { instance, info });
        }
      };
    },
  };
}
