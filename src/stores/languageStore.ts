// src/stores/languageStore.ts

import { defineStore } from 'pinia';
import { useUnrefWindowProp, useWindowProp } from '@/composables/useWindowProps.js';
import axios from 'axios';

const shrimp = useWindowProp('shrimp')
const supportedLocales = useUnrefWindowProp('supported_locales');

interface LanguageState {
  currentLocale: string;
  supportedLocales: string[];
  defaultLocale: string;
  isLoading: boolean;
  error: string | null;
}

export const useLanguageStore = defineStore('language', {
  state: (): LanguageState => ({
    currentLocale: 'en', // default language
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
        this.currentLocale = locale;
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
      try {
        await axios.post('/api/v2/account/update-locale', {
          locale: newLocale,
          shrimp: shrimp.value // Include the shrimp value in the request
        });
        this.currentLocale = newLocale;
      } catch (error) {
        console.error('Failed to update language:', error);
        this.error = 'Failed to update language';
        throw error;
      } finally {
        this.isLoading = false;
      }
    },

    setCurrentLocale(locale: string) {
      this.currentLocale = locale;
    },
  },
});
