// src/plugins/core/appInitializer.ts

import { createApi } from '@/api';
import i18n from '@/i18n';
import { createAppRouter } from '@/router';
import { loggingService } from '@/services/logging.service';
import { WindowService } from '@/services/window.service';
import { AxiosInstance } from 'axios';
import { createPinia } from 'pinia';
import { App, Plugin } from 'vue';

import { createDiagnostics } from './enableDiagnostics';
import { createErrorBoundary } from './globalErrorBoundary';
import { autoInitPlugin } from '../pinia/autoInitPlugin';

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
/*eslint max-statements: ["error", 20]*/
function initializeApp(app: App, options: AppInitializerOptions = {}) {
  const diagnostics = WindowService.get('diagnostics');
  const d9sEnabled = WindowService.get('d9s_enabled');
  const displayDomain = WindowService.get('display_domain');
  const siteHost = WindowService.get('site_host');
  const router = createAppRouter();
  const pinia = createPinia();
  const api = options.api ?? createApi();
  console.log(
    `Initializing app with options: ${JSON.stringify(options, null, 2)}`
  );
  if (d9sEnabled) {
    // Create plugin instances
    const diagnosticsPlugin = createDiagnostics({
      host: displayDomain ?? siteHost,
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

  // Register auto-init plugin before creating stores. We pass the api client
  // to the plugin so it can be used by stores.
  pinia.use(autoInitPlugin(options));

  // Make API client available to Vue app (and pinia stores)
  // NOTE: In our unit tests we need to explicitly provide an API client
  // for stores to use. See plugins/README.md.
  app.provide('api', api);

  app.use(pinia);
  app.use(errorBoundary);
  app.use(i18n);
  app.use(router);

  // Display startup banner
  loggingService.banner();
}
