// plugins/pinia/index.ts

import { ErrorHandlerOptions } from '@/composables/useErrorHandler';
import { AxiosInstance } from 'axios';

export interface PiniaPluginOptions {
  errorHandler?: ErrorHandlerOptions;
  api?: AxiosInstance;
}
