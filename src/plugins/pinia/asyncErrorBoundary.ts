// src/plugins/pinia/asyncErrorBoundary.ts

import { AsyncHandlerOptions, useAsyncHandler } from '@/composables/useAsyncHandler';
import { PiniaPluginContext } from 'pinia';
import { markRaw } from 'vue';

export function asyncErrorBoundary(options?: AsyncHandlerOptions) {
  return ({ store }: PiniaPluginContext) => {
    store.$asyncHandler = markRaw(
      useAsyncHandler({
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
