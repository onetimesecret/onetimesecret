// plugins/pinia/errorHandlingPlugin.ts

import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { PiniaPluginContext } from 'pinia';
import { markRaw } from 'vue';

export function errorHandlingPlugin(options?: ErrorHandlerOptions) {
  return ({ store }: PiniaPluginContext) => {
    store.$errorHandler = markRaw(
      useErrorHandler({
        setLoading: (loading) => {
          if ('isLoading' in store) {
            store.isLoading = loading;
          }
        },
        ...options, // this spread overrides the defaults
      })
    );
  };
}
