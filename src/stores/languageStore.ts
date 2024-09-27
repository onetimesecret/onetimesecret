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
  shrimp: string;
}

export const useLanguageStore = defineStore('language', {
  state: (): LanguageState => ({
    currentLocale: 'en', // default language
    defaultLocale: 'en',
    supportedLocales: supportedLocales,
    isLoading: false,
    error: null,
    shrimp: shrimp.value,
  }),

  getters: {
    getCurrentLocale: (state) => state.currentLocale,
    getSupportedLocales: (state) => state.supportedLocales,
    getShrimp: (state) => state.shrimp,
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
        const response = await axios.post('/api/v2/account/update-locale', {
          locale: newLocale,
          shrimp: this.shrimp
        });
        this.currentLocale = newLocale;

        // Handle the new shrimp value
        if (response.data && response.data.shrimp) {
          this.updateShrimp(response.data.shrimp);
        }
      } catch (error) {
        this.error = 'Failed to update language';
        throw error; // Re-throw the error for the component to handle
      } finally {
        this.isLoading = false;
      }
    },

    updateShrimp(freshShrimp: string) {
      this.shrimp = freshShrimp;
      // Update the window.shrimp value as well
      if (typeof window !== 'undefined') {
        window.shrimp = freshShrimp;
      }
    },

    setCurrentLocale(locale: string) {
      this.currentLocale = locale;
    },
  },
});
