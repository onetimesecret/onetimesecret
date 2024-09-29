// src/stores/languageStore.ts

import { defineStore } from 'pinia';
const supportedLocales = window.supported_locales;
const defaultLocale = 'en';
//import { useCsrfStore } from '@/stores/csrfStore';
//import axios from 'axios';

interface LanguageState {
  currentLocale: string;
  supportedLocales: string[];
  defaultLocale: string;
  isLoading: boolean;
  error: string | null;
}

const LOCAL_STORAGE_KEY = 'selected.locale';

export const useLanguageStore = defineStore('language', {
  state: (): LanguageState => ({
    currentLocale: localStorage.getItem(LOCAL_STORAGE_KEY) || defaultLocale,
    defaultLocale,
    supportedLocales,
    isLoading: false,
    error: null,
  }),

  getters: {
    getCurrentLocale: (state) => state.currentLocale,
    getSupportedLocales: (state) => state.supportedLocales,
  },

  actions: {
    initializeStore(supportedLocales: string[], defaultLocale: string = 'en') {
      this.supportedLocales = supportedLocales;
      this.defaultLocale = defaultLocale;
    },

    setInitialLocale(initialLocale: string) {
      this.setCurrentLocale(initialLocale);
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
