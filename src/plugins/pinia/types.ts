// plugins/pinia/index.ts

import { AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import { AxiosInstance } from 'axios';

export interface PiniaPluginOptions {
  errorHandler?: AsyncHandlerOptions;
  api?: AxiosInstance;
}
