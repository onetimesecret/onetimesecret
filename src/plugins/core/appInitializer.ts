// src/plugins/core/appInitializer.ts

import { AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import i18n from '@/i18n';
import { createAppRouter } from '@/router';
import { loggingService } from '@/services/logging';
import { App, Plugin } from 'vue';
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

/** Makes initializeApp available as a proper Vue plugin */
export const AppInitializer: Plugin<AppInitializerOptions> = {
  install(app: App, options: AppInitializerOptions = {}) {
    initializeApp(app, options);
  },
};

/**
 * Initializes core application services in required order:
 * 1. State management (Pinia with plugins)
 *    - API client
 *    - Error handling
 *    - Auth/logout
 *    - Store initialization
 * 2. Global error boundary
 * 3. Internationalization
 * 4. Routing
 */
function initializeApp(app: App, options: AppInitializerOptions = {}) {
  // Configure Pinia and its plugin chain
  const pinia = initWithPlugins({
    errorHandler: {
      ...defaultErrorHandler,
      ...options.errorHandler,
    },
  });
  app.use(pinia);

  // Register core plugins in dependency order
  app.use(GlobalErrorBoundary, { debug: options.debug });
  app.use(i18n);
  app.use(createAppRouter());

  // Display startup banner
  loggingService.banner();
}
