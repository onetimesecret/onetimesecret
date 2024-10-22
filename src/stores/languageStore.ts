// src/stores/languageStore.ts

import api from '@/utils/api';
import axios from 'axios';
import { defineStore } from 'pinia';
const supportedLocales = window.supported_locales;
const defaultLocale = 'en';

interface LanguageState {
  storedLocale: string | null;
  currentLocale: string | null;
  supportedLocales: string[];
  defaultLocale: string;
  isLoading: boolean;
  error: string | null;
}

const SESSION_STORAGE_KEY = 'selected.locale';

export const useLanguageStore = defineStore('language', {
  state: (): LanguageState => ({
    storedLocale: sessionStorage.getItem(SESSION_STORAGE_KEY),
    currentLocale: null,
    supportedLocales,
    defaultLocale,
    isLoading: false,
    error: null,
  }),

  getters: {
    getCurrentLocale: (state) => state.currentLocale,
    getSupportedLocales: (state) => state.supportedLocales,
    getStorageKey: () => SESSION_STORAGE_KEY,
  },

  actions: {
    // When we start up, we may have the device locale but we won't have
    // the user's preferred locale yet. This method sets a definite initial
    // locale to get things going with the information we have.
    //
    // Priority: 1. Stored locale, 2. Browser language, 3. Default locale
    initializeCurrentLocale(deviceLocale: string) {
      // Extract the primary language code from a locale
      // string. e.g. 'en-NZ' -> 'en'.
      deviceLocale = deviceLocale.split('-')[0];
      this.currentLocale = this.storedLocale || deviceLocale || this.defaultLocale;
      return this.currentLocale;
    },

    /**
     * Determines the appropriate locale (if supported) based on the following priority:
     * 1. Preferred locale
     * 2. Primary language code of preferred locale
     * 3. Current locale (the intialized locale or modified during this run)
     * 4. Stored locale preference (if set)
     * 5. Default locale (fallback)
     *
     * @param {string} [preferredLocale] - The preferred locale string (e.g., 'en', 'fr-FR')
     * @returns {string} The determined locale that is supported by the application
     */
    determineLocale(preferredLocale?: string): string {
      const locales = [
        preferredLocale,
        preferredLocale?.split('-')[0],
        this.currentLocale,
        this.storedLocale,
      ];

      return locales.find(locale =>
        locale && this.supportedLocales.includes(locale)
      ) ?? this.defaultLocale;
    },

    async updateLanguage(newLocale: string) {
      this.isLoading = true;
      this.error = null;

      // Update local state immediately
      this.setCurrentLocale(newLocale);

      try {
        // Update the language for the user using the api instance
        await api.post('/api/v2/account/update-locale', {
          locale: newLocale
        });

        // The CSRF token (shrimp) will be automatically updated by the api interceptor

        this.isLoading = false;
      } catch (error) {
        this.isLoading = false;
        if (axios.isAxiosError(error)) {
          if (error.response && error.response.status >= 400 && error.response.status < 500) {
            // Handle 4XX errors
            this.error = `Failed to update language: ${error.response.data.message || 'Unknown error'}`;
          } else {
            // Handle other errors
            this.error = 'An unexpected error occurred while updating the language';
          }
        } else {
          this.error = 'An unexpected error occurred';
        }
        console.error('Error updating language:', error);
      }

    },

    setCurrentLocale(locale: string) {
      if (this.supportedLocales.includes(locale)) {
        this.currentLocale = locale; // Direct assignment for reactivity
        sessionStorage.setItem(SESSION_STORAGE_KEY, locale);
      } else {
        console.warn(`Unsupported locale: ${locale}`);
      }
    },
  },
});
