// src/stores/jurisdictionStore.ts

import { defineStore } from 'pinia';
import type { Jurisdiction, Regions } from '@/types/onetime';


interface JurisdictionState {
  enabled: boolean;
  currentJurisdiction: Jurisdiction;
  jurisdictions: Jurisdiction[];
  isLoading: boolean;
  error: string | null;
}


export const useJurisdictionStore = defineStore('jurisdiction', {
  state: (): JurisdictionState => ({
    enabled: true,
    currentJurisdiction: {
      identifier: '',
      display_name: '',
      domain: '',
      icon: ''
    },
    isLoading: false,
    error: null,
    jurisdictions: [],
  }),

  getters: {
    getCurrentJurisdiction(): Jurisdiction {
      return this.currentJurisdiction ?? {
        identifier: '',
        display_name: '',
        domain: '',
        icon: ''
      };
    },
    getAllJurisdictions: (state): Jurisdiction[] => {
      return state.jurisdictions;
    },

  },

  actions: {
    initializeStore(regionsConfig: Regions) {
      if (!regionsConfig) {
        this.enabled = false;
        return;
      }
      this.jurisdictions = regionsConfig.jurisdictions;

      // For the time being (i.e. for our first few locations), the region and
      // jurisdiction are the same. EU is EU, US is US. They will differentiate
      // once we get to for example, "California" is US and also California. The
      // reason we make the distinction is that there can be (and are) "layers"
      // of regulations and market forces involved. If I have a business in the
      // US, I probably would prefer to use a US data center given the choice
      // even if the business I'm in is not a regulated industry. I find it
      // helpful to think of it as "compliant by default".
      this.currentJurisdiction = this.findJurisdiction(regionsConfig.current_jurisdiction);

      // If regions are not enabled, ensure we have at least one region
      if (!regionsConfig.enabled && this.jurisdictions.length === 0) {
        const jurisdiction = regionsConfig.jurisdictions[0];
        this.jurisdictions = [{
          identifier: jurisdiction.identifier,
          display_name: jurisdiction.display_name,
          domain: jurisdiction.domain,
          icon: jurisdiction.icon,
        }];
      }
    },
    /**
     * Find a jurisdiction by its identifier.
     * @param identifier - The identifier of the jurisdiction to find.
     * @returns The jurisdiction with the given identifier.
     * @throws Will throw an error if no jurisdiction is found with the given identifier.
     */
    findJurisdiction(identifier: string): Jurisdiction {
      const jurisdiction = this.jurisdictions.find((jurisdiction: Jurisdiction) => jurisdiction.identifier === identifier);
      if (!jurisdiction) {
        throw new Error(`Jurisdiction with identifier "${identifier}" not found.`);
      }
      return jurisdiction;
    },

  },
});
