// src/stores/languageStore.ts

import { defineStore } from 'pinia';
import { useCsrfStore } from '@/stores/csrfStore';
import axios from 'axios';


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
    currentLocale: localStorage.getItem(LOCAL_STORAGE_KEY) || 'en',
    defaultLocale: 'en',
    supportedLocales: [],
    isLoading: false,
    error: null,
  }),

  getters: {
    getCurrentLocale: (state) => state.currentLocale,
    getSupportedLocales: (state) => state.supportedLocales,
  },

  actions: {
    initializeStore(initialLocale: string, supportedLocales: string[], defaultLocale: string = 'en') {
      this.supportedLocales = supportedLocales;
      this.defaultLocale = defaultLocale;
      this.setCurrentLocale(initialLocale);
    },

    async updateLanguage(newLocale: string) {
      this.isLoading = true;
      this.error = null;
      const csrfStore = useCsrfStore();
      let returnSuccess = false;

      try {
        const response = await axios.post('/api/v2/account/update-locale', {
          locale: newLocale,
          shrimp: csrfStore.shrimp
        });
        this.setCurrentLocale(newLocale);

        returnSuccess = true;

        // Update the CSRF shrimp if it's returned in the response
        if (response.data && response.data.shrimp) {
          csrfStore.updateShrimp(response.data.shrimp);
        }

      } catch (error) {
        this.error = 'Failed to update language';

        // Check if the error is due to an invalid CSRF token
        if (axios.isAxiosError(error) && error.response?.status === 403) {
          console.log('CSRF token might be invalid. Checking validity...');
          await csrfStore.checkShrimpValidity();

          if (!csrfStore.isValid) {
            console.log('CSRF token is invalid. Please refresh the page or try again.');
          }
        }

        // Instead of re-throwing, we'll allow this function
        // to return false to indicate failure.

      } finally {
        this.isLoading = false;
        returnSuccess = true;
      }

      // If we reach here, it means the update was successful
      return returnSuccess;
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
