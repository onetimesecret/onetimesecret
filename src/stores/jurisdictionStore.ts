// src/stores/jurisdictionStore.ts

import { defineStore } from 'pinia';

// Assuming these are available globally or imported from a config file
const supportedJurisdictions = window.available_jurisdictions || ['US', 'EU', 'UK', 'CA', 'AU'];
const defaultJurisdiction = 'US';

interface JurisdictionState {
  storedJurisdiction: string | null;
  currentJurisdiction: string | null;
  supportedJurisdictions: string[];
  defaultJurisdiction: string;
  isLoading: boolean;
  error: string | null;
}

const LOCAL_STORAGE_KEY = 'selected.jurisdiction';

export const useJurisdictionStore = defineStore('jurisdiction', {
  state: (): JurisdictionState => ({
    storedJurisdiction: localStorage.getItem(LOCAL_STORAGE_KEY),
    currentJurisdiction: null,
    supportedJurisdictions,
    defaultJurisdiction,
    isLoading: false,
    error: null,
  }),

  getters: {
    getCurrentJurisdiction: (state) => state.currentJurisdiction,
    getSupportedJurisdictions: (state) => state.supportedJurisdictions,
  },

  actions: {
    initializeCurrentJurisdiction(deviceJurisdiction: string) {
      this.currentJurisdiction = this.storedJurisdiction || deviceJurisdiction || this.defaultJurisdiction;
      return this.currentJurisdiction;
    },

    determineJurisdiction(preferredJurisdiction?: string): string {
      const jurisdictions = [
        preferredJurisdiction,
        this.currentJurisdiction,
        this.storedJurisdiction,
      ];

      return jurisdictions.find(jurisdiction =>
        jurisdiction && this.supportedJurisdictions.includes(jurisdiction)
      ) ?? this.defaultJurisdiction;
    },

    async updateJurisdiction(newJurisdiction: string) {
      this.isLoading = true;
      this.error = null;

      // Update local state immediately
      this.setCurrentJurisdiction(newJurisdiction);

      /**
      try {
        // Update the jurisdiction for the user using the api instance
        await api.post('/api/v2/account/update-jurisdiction', {
          jurisdiction: newJurisdiction
        });

        this.isLoading = false;
      } catch (error) {
        this.isLoading = false;
        if (axios.isAxiosError(error)) {
          if (error.response && error.response.status >= 400 && error.response.status < 500) {
            this.error = `Failed to update jurisdiction: ${error.response.data.message || 'Unknown error'}`;
          } else {
            this.error = 'An unexpected error occurred while updating the jurisdiction';
          }
        } else {
          this.error = 'An unexpected error occurred';
        }
        console.error('Error updating jurisdiction:', error);
      }
      */
    },

    setCurrentJurisdiction(jurisdiction: string) {
      if (this.supportedJurisdictions.includes(jurisdiction)) {
        this.currentJurisdiction = jurisdiction;
        localStorage.setItem(LOCAL_STORAGE_KEY, jurisdiction);
      } else {
        console.warn(`Unsupported jurisdiction: ${jurisdiction}`);
      }
    },
  },
});
