// src/plugins/core/appInitializer.ts

import { AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import i18n from '@/i18n';
import { createAppRouter } from '@/router';
import { loggingService } from '@/services/logging';
import { App } from 'vue';
import { initWithPlugins } from '../pinia/initPlugin';
import { GlobalErrorBoundary } from './globalErrorBoundary';

interface AppInitializerOptions {
  errorHandler?: AsyncHandlerOptions;
  debug?: boolean;
}

const defaultErrorHandler = {
  notify: (message: string, severity: string) =>
    loggingService.info(`[notify] ${severity}: ${message}`),
  log: (error: Error) => loggingService.error(error),
};

/**
 * Initializes core application services in required order:
 * 1. State management (Pinia)
 * 2. Error handling
 * 3. Internationalization
 * 4. Routing
 */
export function initializeApp(app: App, options: AppInitializerOptions = {}) {
  // Initialize state management
  const pinia = initWithPlugins({
    errorHandler: {
      ...defaultErrorHandler,
      ...options.errorHandler,
    },
  });
  app.use(pinia);

  // Initialize core services
  app.use(GlobalErrorBoundary, { debug: options.debug });
  app.use(i18n);
  app.use(createAppRouter());

  // Display startup banner
  loggingService.banner();
}
