// plugins/pinia/initPlugin.ts
//
import { createPinia } from 'pinia';
import { apiPlugin } from './apiPlugin';
import { asyncErrorBoundary } from './asyncErrorBoundary';
import { initializeStores } from './initializeStores';
import { logoutPlugin } from './logoutPlugin';
import type { PiniaPluginOptions } from './types';

export function initWithPlugins(options: PiniaPluginOptions = {}) {
  const pinia = createPinia();

  // Plugins must be added in specific order to ensure dependencies are available:
  // 1. API plugin provides $api instance for HTTP requests
  pinia.use(apiPlugin(options.api));

  // 2. Error boundary adds $asyncHandler for consistent error handling
  pinia.use(asyncErrorBoundary(options.errorHandler));

  // 3. Logout plugin adds $logout for auth state cleanup
  pinia.use(logoutPlugin);

  // 4. Store initializer runs last when all required plugins are ready
  pinia.use(initializeStores());

  return pinia;
}
