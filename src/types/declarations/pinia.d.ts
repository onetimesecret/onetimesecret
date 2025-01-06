// src/types/declarations/pinia.d.ts

import type { AxiosInstance } from 'axios';
import 'pinia';

declare module 'pinia' {
  export interface PiniaCustomProperties {
    $api: AxiosInstance;
  }
}
