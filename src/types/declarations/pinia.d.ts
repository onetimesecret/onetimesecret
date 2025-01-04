import type { AsyncHandler, AsyncHandlerOptions } from '@/composables/useAsyncHandler';
import type { AxiosInstance } from 'axios';
import 'pinia';
import { ComputedRef, Ref } from 'vue';

/**
 * Required properties injected into all stores
 * Provides consistent API access, error handling, and lifecycle methods
 */
export interface PiniaCustomProperties {
  $api: AxiosInstance;
  $errorHandler: AsyncHandler;
  $logout: () => void;

  /**
   * Store initialization method
   * @returns Object containing initialization state
   */
  init?: (this: PiniaCustomProperties) => { isInitialized: ComputedRef<boolean> };
}

declare module 'pinia' {
  // Extend the module to include custom properties
  export interface PiniaCustomProperties extends Omit<globalThis.PiniaCustomProperties, 'init'> {
    /**
     * Store initialization method
     * @returns Object containing initialization state
     */
    init?: (this: PiniaCustomProperties) => { isInitialized: ComputedRef<boolean> };
  }

  /**
   * Base store options that all stores should implement
   * Ensures consistent state management patterns
   */
  export interface DefineStoreOptionsBase {
    _initialized?: Ref<boolean>;
    isLoading?: Ref<boolean>;
  }
}

/**
 * Configuration options for Pinia plugins
 * Enables customization of API, error handling, and logging behavior
 */
export interface PiniaPluginOptions {
  api?: AxiosInstance;
  errorHandler?: AsyncHandlerOptions;
  enableLogging?: boolean;
}

/**
 * Interface for stores using the initialization pattern
 * Ensures consistent implementation of loading and initialization state
 */
export interface InitializableStore {
  _initialized: Ref<boolean>;
  isLoading: Ref<boolean>;
  init: (this: PiniaCustomProperties) => { isInitialized: ComputedRef<boolean> };
}
