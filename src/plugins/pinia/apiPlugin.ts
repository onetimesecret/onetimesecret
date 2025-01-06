// plugins/pinia/apiPlugin.ts

import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { PiniaPluginContext } from 'pinia';
import { ref, toRef } from 'vue';

export function apiPlugin(apiInstance?: AxiosInstance) {
  const api = apiInstance || createApi();

  return ({ store, options }: PiniaPluginContext) => {
    if (!store.$state.hasOwnProperty('$api')) {
      store.$state.$api = ref(api);
    }
    store.api = toRef(store.$state, '$api');
  };
}
