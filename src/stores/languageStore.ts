// src/stores/languageStore.ts

import { defineStore } from 'pinia';
const supportedLocales = window.supported_locales;
const defaultLocale = 'en';
//import { useCsrfStore } from '@/stores/csrfStore';
//import axios from 'axios';

interface LanguageState {
  storedLocale: string | null;
  currentLocale: string | null;
  supportedLocales: string[];
  defaultLocale: string;
  isLoading: boolean;
  error: string | null;
}

const LOCAL_STORAGE_KEY = 'selected.locale';

export const useLanguageStore = defineStore('language', {
  state: (): LanguageState => ({
    storedLocale: localStorage.getItem(LOCAL_STORAGE_KEY),
    currentLocale: null,
    supportedLocales,
    defaultLocale,
    isLoading: false,
    error: null,
  }),

  getters: {
    getCurrentLocale: (state) => state.currentLocale,
    getSupportedLocales: (state) => state.supportedLocales,
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
      //const csrfStore = undefined; // = useCsrfStore();

      // Update local state immediately
      this.setCurrentLocale(newLocale);

//      try {
//        const response = await axios.post('/api/v2/account/update-locale', {
//          locale: newLocale,
//          shrimp: csrfStore.shrimp
//        });
//
//        // Update the CSRF shrimp if it's returned in the response
//        if (response.data && response.data.shrimp) {
//          csrfStore.updateShrimp(response.data.shrimp);
//        }
//
//        return true;
//      } catch (error) {
//        // Set error, but don't revert the local change
//        this.error = 'Failed to update language on server';
//
//        // Check if the error is due to an invalid CSRF token
//        if (axios.isAxiosError(error) && error.response?.status === 403) {
//          console.log('CSRF token might be invalid. Checking validity...');
//          await csrfStore.checkShrimpValidity();
//
//          if (!csrfStore.isValid) {
//            console.log('CSRF token is invalid. Please refresh the page or try again.');
//          }
//        }
//
//        return false;
//      } finally {
//        this.isLoading = false;
//      }
    },

    setCurrentLocale(locale: string) {
      if (this.supportedLocales.includes(locale)) {
        this.currentLocale = locale;
        localStorage.setItem(LOCAL_STORAGE_KEY, locale);
      } else {
        console.warn(`Unsupported locale: ${locale}`);
      }
    },
  },
});
