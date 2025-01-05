// src/plugins/pinia/initializeStores.ts

import { PiniaPluginContext } from 'pinia';

export function initializeStores() {
  return ({ store }: PiniaPluginContext) => {
    // Store initialization must run synchronously to ensure store state
    // is ready before router guards or components access it.
    // Previous plugins have already injected required dependencies:
    // - $api from apiPlugin
    // - $asyncHandler from asyncErrorBoundary
    // - $logout from logoutPlugin
    if (typeof store.init === 'function') {
      store.init();
    }
  };
}
