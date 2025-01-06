// src/types/declarations/pinia.d.ts

import type { AxiosInstance } from 'axios';
import 'pinia';
import { PiniaCustomProperties } from 'pinia';
import { ComputedRef, Ref } from 'vue';

/**
 * Core store functionality injected by plugins
 */
interface StoreCore {
  $api: AxiosInstance;
  $logout: () => Promise<void>;
}

/**
 * Store initialization pattern
 */
interface StoreInit {
  /**
   * Store initialization method
   * @returns Initialization state
   */
  init?: (this: PiniaCustomProperties) => {
    isInitialized: ComputedRef<boolean>;
  };
}

declare module 'pinia' {
  /**
   * Custom properties available on all stores
   */
  export interface PiniaCustomProperties extends StoreCore, StoreInit {}

  /**
   * Base configuration required for all stores
   */
  export interface DefineStoreOptionsBase {
    /**
     * Initialization state tracking
     */
    _initialized?: Ref<boolean>;
  }
}

/**
 * Plugin configuration options
 */
export interface PiniaPluginOptions {
  /**
   * API client instance
   */
  api?: AxiosInstance;
}

/**
 * Interface for stores implementing initialization pattern
 */
export interface InitializableStore {
  _initialized: Ref<boolean>;
  init: (this: PiniaCustomProperties) => {
    isInitialized: ComputedRef<boolean>;
  };
}
