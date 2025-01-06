// plugins/pinia/apiPlugin.ts

import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { PiniaPluginContext } from 'pinia';

export function apiPlugin(apiInstance?: AxiosInstance) {
  const api = apiInstance || createApi();

  return ({ store }: PiniaPluginContext) => {
    store.$api = api;
  };
}
