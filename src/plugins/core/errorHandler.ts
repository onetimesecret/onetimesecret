// src/plugins/errorHandler/index.ts
import { useErrorHandler } from '@/composables/useErrorHandler';
import type { App, Plugin } from 'vue';

export interface ErrorHandlerOptions {
  debug?: boolean;
}

/**
 * Global error handling plugin for Vue 3 applications
 * @description Provides a centralized error handling mechanism for the entire Vue application
 * @param {App} app - Vue application instance
 * @param {ErrorHandlerOptions} [options={}] - Plugin options
 */
export const ErrorHandlerPlugin: Plugin = {
  install(app: App, options: ErrorHandlerOptions = {}) {
    console.log('[ErrorHandlerPlugin] Plugin installed');

    if (options.debug) {
      console.debug('[ErrorHandlerPlugin] Plugin installed with debug mode enabled');
    }

    /**
     * Vue 3 global error handler
     * @param error: The error that was thrown
     * @param instance: The component instance that triggered the error
     * @param info: A string containing information about where the error was caught
     *
     * @see https://vuejs.org/api/application#app-config-errorhandler
     */
    app.config.errorHandler = (error, instance, info) => {
      console.log('[ErrorHandlerPlugin] Error caught', { error, instance, info }); // Unconditional logging

      const { handleError } = useErrorHandler();

      if (options.debug) {
        console.error('[ErrorHandlerPlugin]', {
          error,
          componentName: instance?.$.type?.name,
          info,
        });
      }

      handleError(error);
    };
  },
};
