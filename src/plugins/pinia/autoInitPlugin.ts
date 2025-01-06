// src/plugins/pinia/autoInitPlugin.ts

import { PiniaPluginContext } from 'pinia';
import type { PiniaPluginOptions } from './types';

/**
 * Store initialization must run synchronously to ensure store state
 * is ready before router guards or components access it.
 *
 * Previous plugins have already injected required dependencies:
 * - $api from apiPlugin
 * - $logout from logoutPlugin
 */
export function autoInitPlugin(options: PiniaPluginOptions = {}) {
  console.log('[autoInit0]', options.api);
  return ({ store }: PiniaPluginContext) => {
    if (typeof store.init === 'function') {
      console.log('[autoInit1]', options.api);
      store.init({ api: options.api });
    }
  };
}
