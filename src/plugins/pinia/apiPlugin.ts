// plugins/pinia/apiPlugin.ts

import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { PiniaPluginContext } from 'pinia';
import { markRaw } from 'vue';

export function apiPlugin(customApi?: AxiosInstance) {
  return ({ store }: PiniaPluginContext) => {
    const api = markRaw(customApi || createApi());

    /* TODO: optional flags for shrimp interceptors and logging (e.g. like general access logs) */
    // if (enableLogging) {
    //   api.interceptors.request.use(config => {
    //     console.debug(`[API] ${config.method?.toUpperCase()} ${config.url}`);
    //     return config;
    //   });
    // }

    store.$api = api;
  };
}
