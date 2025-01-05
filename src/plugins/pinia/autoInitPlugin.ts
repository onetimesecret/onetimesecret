// src/plugins/pinia/autoInitPlugin.ts

import { PiniaPluginContext } from 'pinia';

/**
 * Store initialization must run synchronously to ensure store state
 * is ready before router guards or components access it.
 *
 * Previous plugins have already injected required dependencies:
 * - $api from apiPlugin
 * - $logout from logoutPlugin
 */
export function autoInitPlugin() {
  return ({ store }: PiniaPluginContext) => {
    if (typeof store.init === 'function') {
      store.init();
    }
  };
}
