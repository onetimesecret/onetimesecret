// plugins/pinia/apiPlugin.ts

import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { PiniaPluginContext } from 'pinia';

export function apiPlugin(apiInstance?: AxiosInstance) {
  const api = apiInstance || createApi();

  return ({ store }: PiniaPluginContext) => {
    // const api = markRaw(;

    /* TODO: optional flags for shrimp interceptors and logging (e.g. like general access logs) */
    // if (enableLogging) {
    //   api.interceptors.request.use(config => {
    //     console.debug(`[API] ${config.method?.toUpperCase()} ${config.url}`);
    //     return config;
    //   });
    // }
    //
    //if (typeof store.setupAsyncHandler === 'function') {
    //  store.setupAsyncHandler(apiInstance);
    //}

    store.$api = api;
  };
}
