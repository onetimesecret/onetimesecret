// types/declarations/pinia.d.ts

import type { AsyncHandler } from '@/composables/useAsyncHandler';
import type { AxiosInstance } from 'axios';
import { ComputedRef, Ref } from 'vue';
import 'pinia';

/**
 * Store Architecture & Error Handling
 *
 * Stores combine state management and API calls because:
 * 1. Single Source of Truth - stores serve as the service layer
 * 2. Schema Integration - Zod handles validation and typing
 * 3. Zero Abstraction - direct mapping of API to state
 *
 * Error Flow:
 * - Stores propagate errors up
 * - Composables handle errors and notifications
 * - Components use composables for error handling
 */
declare module 'pinia' {
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
     * @param api Optional API instance override
     * @returns Object containing initialization state
     */
    init?: (api?: AxiosInstance) => { isInitialized: ComputedRef<boolean> };
  }

  /**
   * Base store options that all stores should implement
   * Ensures consistent state management patterns
   */
  export interface DefineStoreOptionsBase<S, Store> {
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
  init: (api?: AxiosInstance) => { isInitialized: ComputedRef<boolean> };
}
