// src/stores/jurisdictionStore.ts

import {
  createError,
  ErrorHandlerOptions,
  useErrorHandler,
} from '@/composables/useErrorHandler';
import type { Jurisdiction, RegionsConfig } from '@/schemas/models';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
/**
 * N.B.
 * For the time being (i.e. for our first few locations), the region and
 * jurisdiction are the same. EU is EU, US is US. They will differentiate
 * once we get to for example, "California" is US and also California. The
 * reason we make the distinction is that there can be (and are) "layers"
 * of regulations and market forces involved. If I have a business in the
 * US, I probably would prefer to use a US data center given the choice
 * even if the business I'm in is not a regulated industry. I find it
 * helpful to think of it as "compliant by default".
 */

interface StoreState {
  isLoading: boolean;
  enabled: boolean;
  currentJurisdiction: Jurisdiction | null;
  jurisdictions: Jurisdiction[];
  _initialized: boolean;
}

export const useJurisdictionStore = defineStore('jurisdiction', {
  state: (): StoreState => ({
    isLoading: false,
    enabled: true,
    currentJurisdiction: null,
    jurisdictions: [],
    _initialized: false,
  }),

  getters: {
    getCurrentJurisdiction(): StoreState['currentJurisdiction'] {
      return this.currentJurisdiction;
    },
    getAllJurisdictions(state): Jurisdiction[] {
      return state.jurisdictions;
    },
  },

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    /**
     * Initialize the jurisdiction store with configuration from API
     * Handles both enabled and disabled region scenarios
     */
    init(config: RegionsConfig | null) {
      if (this._initialized) return;

      this._ensureErrorHandler();

      if (!config) {
        this.enabled = false;
        this.jurisdictions = [];
        this.currentJurisdiction = null;
        return;
      }

      this.enabled = config.enabled;
      this.jurisdictions = config.jurisdictions;

      const jurisdiction = this.findJurisdiction(config.current_jurisdiction);
      this.currentJurisdiction = jurisdiction;

      // If regions are disabled, ensure we only have the current jurisdiction
      if (!config.enabled) {
        this.jurisdictions = [jurisdiction];
      }
    },

    _ensureErrorHandler() {
      if (!this._errorHandler) this.setupErrorHandler();
    },

    // Allow passing options during initialization
    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify, // Allow UI layer to handle notifications if provided
        log: options.log, // Allow custom logging if provided
      });
    },

    /**
     * Find a jurisdiction by its identifier.
     * @throws ApiError if no jurisdiction is found with the given identifier.
     * @param identifier - The identifier of the jurisdiction to find.
     * @returns The found jurisdiction ()
     */
    findJurisdiction(identifier: string): Jurisdiction {
      const jurisdiction = this.jurisdictions.find((j) => j.identifier === identifier);
      if (!jurisdiction) {
        throw createError(
          `Jurisdiction "${identifier}" not found`,
          'technical',
          'error',
          {
            identifier,
          }
        );
      }
      return jurisdiction;
    },
  },
});
