// src/plugins/errorHandler/index.ts
import { useErrorHandler } from '@/composables/useErrorHandler';
import type { App, Plugin } from 'vue';

export interface ErrorHandlerOptions {
  debug?: boolean;
}

export const ErrorHandlerPlugin: Plugin = {
  install(app: App, options: ErrorHandlerOptions = {}) {
    /**
     * Vue 3 global error handler
     * @param error: The error that was thrown
     * @param instance: The component instance that triggered the error
     * @param info: A string containing information about where the error was caught
     *
     * @see https://vuejs.org/api/application#app-config-errorhandler
     */
    app.config.errorHandler = (error, instance, info) => {
      const { handleError } = useErrorHandler();

      if (options.debug) {
        console.error('[ErrorHandler]', {
          error,
          componentName: instance?.$.type?.name,
          info,
        });
      }

      handleError(error);
    };
  },
};
