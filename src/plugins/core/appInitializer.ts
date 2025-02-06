// src/plugins/core/appInitializer.ts

import i18n from '@/i18n';
import { createAppRouter } from '@/router';
import { loggingService } from '@/services/logging.service';
import { WindowService } from '@/services/window.service';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { createPinia } from 'pinia';
import { App, Plugin } from 'vue';
import { autoInitPlugin } from '../pinia/autoInitPlugin';

import { createDiagnostics } from './enableDiagnotics';
import { createErrorBoundary } from './globalErrorBoundary';

interface AppInitializerOptions {
  api?: AxiosInstance;
  debug?: boolean;
}

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
 *
 * We separate this from the main plugin to interface for testing purposes.
 */
function initializeApp(app: App, options: AppInitializerOptions = {}) {
  const diagnostics = WindowService.get('diagnostics');
  const d9sEnabled = WindowService.get('d9s_enabled');
  const displayDomain = WindowService.get('display_domain');
  const router = createAppRouter();
  const pinia = createPinia();
  const api = options.api ?? createApi();

  if (d9sEnabled) {
    // Create plugin instances
    const diagnosticsPlugin = createDiagnostics({
      host: displayDomain,
      config: diagnostics,
      router,
    });

    // Must be before GlobalErrorBoundary. The earlier the better.
    app.use(diagnosticsPlugin);
  }

  const errorBoundary = createErrorBoundary({
    debug: options.debug,
    // notify: notifications.add,
  });

  // Register auto-init plugin before creating stores
  pinia.use(autoInitPlugin(options));

  // Make API client available to Vue app (and pinia stores)
  app.provide('api', api);

  app.use(pinia);
  app.use(errorBoundary);
  app.use(i18n);
  app.use(router);

  // Display startup banner
  loggingService.banner();
}
