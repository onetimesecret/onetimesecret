// src/plugins/core/globalErrorBoundary.ts
//
import { AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import { classifyError, errorGuards } from '@/schemas/errors';
import { loggingService } from '@/services/logging.service';
import type { App, Plugin } from 'vue';

import * as Sentry from '@sentry/vue';

/**
 * Global error handling plugin for Vue 3 applications that connects
 * with Vue's built-in error handling system
 *
 * @description Provides a centralized error handling mechanism for the entire Vue application
 * @param {App} app - Vue application instance
 * @param {AsyncHandlerOptions} [options={}] - Plugin options
 */
export const GlobalErrorBoundary: Plugin = {
  install(app: App, options: AsyncHandlerOptions = {}) {
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
      const classifiedError = classifyError(error);
      loggingService.error(error as Error); // was: classifiedError

      // Only notify user for human-facing errors
      if (errorGuards.isOfHumanInterest(classifiedError) && options.notify) {
        options.notify(classifiedError.message, classifiedError.severity);
      }

      Sentry.captureException(error, {
        extra: {
          componentName: instance?.$.type.name,
          info,
        },
      });

      if (options.debug) {
        loggingService.debug('[ErrorContext]', { instance, info });
      }
    };
  },
};
