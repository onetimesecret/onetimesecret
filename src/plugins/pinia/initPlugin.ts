import { createPinia } from 'pinia';

import { apiPlugin } from './apiPlugin';
import { errorHandlingPlugin } from './errorHandlingPlugin';
import { logoutPlugin } from './logoutPlugin';
import type { PiniaPluginOptions } from './types';

export function initWithPlugins(options: PiniaPluginOptions = {}) {
  const pinia = createPinia();

  try {
    // Add plugins in order of dependency
    pinia.use(apiPlugin(options.api));
    pinia.use(errorHandlingPlugin(options.errorHandler));
    pinia.use(logoutPlugin);
    console.debug('[Pinia] Initialized Pinia with plugins:', pinia);
  } catch (error) {
    console.error('[Pinia] Error initializing Pinia with plugins:', error);
    throw error;
  }

  return pinia;
}
