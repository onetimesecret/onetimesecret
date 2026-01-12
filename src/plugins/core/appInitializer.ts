// src/plugins/core/appInitializer.ts

import { createApi } from '@/api';
import i18n from '@/i18n';
import { createAppRouter } from '@/router';
import { consumeBootstrapData, getBootstrapValue } from '@/services/bootstrap.service';
import { loggingService } from '@/services/logging.service';
import type { DiagnosticsConfig } from '@/types/diagnostics';
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
  // Consume bootstrap data early, before Pinia is installed.
  // This populates the snapshot for getBootstrapValue() calls.
  consumeBootstrapData();

  const diagnostics = getBootstrapValue('diagnostics');
  const d9sEnabled = getBootstrapValue('d9s_enabled');
  const displayDomain = getBootstrapValue('display_domain');
  const siteHost = getBootstrapValue('site_host');
  const router = createAppRouter();
  const pinia = createPinia();
  const api = options.api ?? createApi();

  if (d9sEnabled && diagnostics) {
    // Create plugin instances. When d9sEnabled is true, host/config are guaranteed.
    const diagnosticsPlugin = createDiagnostics({
      host: (displayDomain ?? siteHost) as string,
      config: diagnostics as DiagnosticsConfig,
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
