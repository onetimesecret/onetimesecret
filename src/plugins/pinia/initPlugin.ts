// plugins/pinia/initPlugin.ts
//
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { createPinia } from 'pinia';
import { markRaw } from 'vue';

interface PiniaPluginOptions {
  errorHandler?: ErrorHandlerOptions;
  api?: AxiosInstance;
}

export function initWithPlugins(options: PiniaPluginOptions = {}) {
  const pinia = createPinia();

  pinia.use(({ store }) => {
    // Create API instance
    const api = markRaw(options.api || createApi())

    // Create error handler with provided options
    const errorHandler = markRaw(useErrorHandler({
      setLoading: (loading) => {
        if ('isLoading' in store) {
          store.isLoading = loading
        }
      },
      ...options.errorHandler // Spread any provided error handler options
    }))

    // Add shared services/utilities that all stores can access
    // markRaw prevents Vue from making these reactive
    store.$api = api;
    store.$errorHandler = errorHandler;

    // Optional: Add shared methods
    return {
      // Available as store.$reset() on all stores
      $reset() {
        // Default reset implementation
        const initialState = store.$state;
        store.$patch((state) => {
          Object.assign(state, initialState);
        });
      },
    };
  });

  return pinia;
}
