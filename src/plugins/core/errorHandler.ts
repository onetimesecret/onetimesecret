// src/plugins/core/errorHandler.ts

import { ErrorHandlerOptions } from '@/composables/useErrorHandler';
import { classifyError, isOfHumanInterest } from '@/schemas/errors/classifier';
import { loggingService } from '@/services/logging';
import type { App, Plugin } from 'vue';

/**
 * Global error handling plugin for Vue 3 applications that connects
 * with Vue's built-in error handling system
 *
 * @description Provides a centralized error handling mechanism for the entire Vue application
 * @param {App} app - Vue application instance
 * @param {ErrorHandlerOptions} [options={}] - Plugin options
 */
export const ErrorHandlerPlugin: Plugin = {
  install(app: App, options: ErrorHandlerOptions = {}) {
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
      loggingService.error(error); // was: classifiedError

      // Only notify user for human-facing errors
      if (isOfHumanInterest(classifiedError) && options.notify) {
        options.notify(classifiedError.message, classifiedError.severity);
      }

      if (options.debug) {
        console.debug('[ErrorHandler]', { error, instance, info });
      }
    };
  },
};
