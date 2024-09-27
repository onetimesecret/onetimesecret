// src/stores/languageStore.ts

import { defineStore } from 'pinia';
import { useUnrefWindowProp } from '@/composables/useWindowProps.js';
import { useCsrfStore } from '@/stores/csrfStore';

import axios from 'axios';

const supportedLocales = useUnrefWindowProp('supported_locales');

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
    currentLocale: localStorage.getItem(LOCAL_STORAGE_KEY) || 'en', // Use stored locale or default
    defaultLocale: 'en',
    supportedLocales: supportedLocales,
    isLoading: false,
    error: null,
  }),

  getters: {
    getCurrentLocale: (state) => state.currentLocale,
    getSupportedLocales: (state) => state.supportedLocales,
  },

  actions: {
    async fetchSupportedLocales() {
      this.isLoading = true;
      try {
        const response = await axios.get('/api/v2/supported-locales');
        const { locales, default_locale, locale } = response.data;
        this.supportedLocales = locales;
        this.defaultLocale = default_locale;
        this.setCurrentLocale(locale);
      } catch (error) {
        console.error('Failed to fetch supported locales:', error);
        this.error = 'Failed to fetch supported locales';
      } finally {
        this.isLoading = false;
      }
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
      this.currentLocale = locale;
      // Store the locale in localStorage
      localStorage.setItem(LOCAL_STORAGE_KEY, locale);
    },
  },
});
