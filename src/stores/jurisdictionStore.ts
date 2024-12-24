// src/stores/jurisdictionStore.ts

import { useStoreError } from '@/composables/useStoreError';
import { ApiError } from '@/schemas';
import type { Jurisdiction, RegionsConfig } from '@/schemas/models';
import { defineStore } from 'pinia';

interface StoreState {
  isLoading: boolean;
  error: ApiError | null;
  enabled: boolean;
  currentJurisdiction: Jurisdiction | null;
  jurisdictions: Jurisdiction[];
}

export const useJurisdictionStore = defineStore('jurisdiction', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    enabled: true,
    currentJurisdiction: null,
    jurisdictions: [],
  }),

  getters: {
    getCurrentJurisdiction(): StoreState['currentJurisdiction'] {
      return this.currentJurisdiction;
    },
    getAllJurisdictions: (state): Jurisdiction[] => {
      return state.jurisdictions;
    },
  },

  actions: {
    handleError(error: unknown): never {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      throw this.error;
    },

    /**
     * Initialize the jurisdiction store with configuration from API
     * Handles both enabled and disabled region scenarios
     */
    initializeStore(config: RegionsConfig) {
      if (!config) {
        this.enabled = false;
        return;
      }
      this.jurisdictions = config.jurisdictions;

      // For the time being (i.e. for our first few locations), the region and
      // jurisdiction are the same. EU is EU, US is US. They will differentiate
      // once we get to for example, "California" is US and also California. The
      // reason we make the distinction is that there can be (and are) "layers"
      // of regulations and market forces involved. If I have a business in the
      // US, I probably would prefer to use a US data center given the choice
      // even if the business I'm in is not a regulated industry. I find it
      // helpful to think of it as "compliant by default".
      this.currentJurisdiction = this.findJurisdiction(config.current_jurisdiction);

      // If regions are not enabled, ensure we have at least one region
      if (!config.enabled && this.jurisdictions.length === 0) {
        this.jurisdictions = [config.jurisdictions[0]];
      }
    },

    /**
     * Find a jurisdiction by its identifier.
     * @param identifier - The identifier of the jurisdiction to find.
     * @returns The jurisdiction with the given identifier.
     * @throws ApiError if no jurisdiction is found with the given identifier.
     */
    findJurisdiction(identifier: string): Jurisdiction {
      const jurisdiction = this.jurisdictions.find((j) => j.identifier === identifier);
      if (!jurisdiction) {
        throw this.handleError(new Error(`Jurisdiction "${identifier}" not found`));
      }
      return jurisdiction;
    },
  },
});
