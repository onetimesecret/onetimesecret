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

  // Add plugins in order of dependency
  pinia.use(apiPlugin(options.api));
  pinia.use(asyncErrorBoundary(options.errorHandler));
  pinia.use(logoutPlugin);
  pinia.use(initializeStores());
  console.debug('[Pinia] Initialized Pinia with plugins:', pinia);

  return pinia;
}
