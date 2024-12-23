// src/stores/languageStore.ts

import { useStoreError } from '@/composables/useStoreError';
import { ApiError } from '@/schemas';
import { createApi } from '@/utils/api';
import { defineStore } from 'pinia';
import { z } from 'zod';

const api = createApi();

const supportedLocales = window.supported_locales;
const defaultLocale = 'en';

// Schema for locale validation
const localeSchema = z
  .string()
  .min(2)
  .max(5)
  .regex(/^[a-z]{2}(-[A-Z]{2})?$/);

interface StoreState {
  isLoading: boolean;
  error: ApiError | null;
  storedLocale: string | null;
  currentLocale: string | null;
  supportedLocales: string[];
  defaultLocale: string;
}

const SESSION_STORAGE_KEY = 'selected.locale';

export const useLanguageStore = defineStore('language', {
  state: (): StoreState => ({
    isLoading: false,
    error: null,
    storedLocale: sessionStorage.getItem(SESSION_STORAGE_KEY),
    currentLocale: null,
    supportedLocales,
    defaultLocale,
  }),

  getters: {
    getCurrentLocale: (state) => state.currentLocale,
    getSupportedLocales: (state) => state.supportedLocales,
    getStorageKey: () => SESSION_STORAGE_KEY,
  },

  actions: {
    handleError(error: unknown): ApiError {
      const { handleError } = useStoreError();
      this.error = handleError(error);
      throw this.error;
    },

    /**
     * Sets initial locale based on priority:
     * 1. Stored locale
     * 2. Browser language
     * 3. Default locale
     *
     * NOTE: When we start up, we may have the device locale but we won't have
     * the user's preferred locale yet. This method sets a definite initial
     * locale to get things going with the information we have.
     */
    initializeCurrentLocale(deviceLocale: string) {
      try {
        // Extract primary language code (e.g., 'en-NZ' -> 'en')
        const primaryLocale = deviceLocale.split('-')[0];
        this.currentLocale = this.storedLocale || primaryLocale || this.defaultLocale;
        return this.currentLocale;
      } catch (error) {
        console.error('Error initializing current locale:', error);
        this.currentLocale = this.defaultLocale;
        return this.defaultLocale;
      }
    },

    /**
     * Determines the appropriate locale (if supported) based on the following priority:
     * 1. Preferred locale
     * 2. Primary language code of preferred locale
     * 3. Current locale (the initialized locale or modified during this run)
     * 4. Stored locale preference (if set)
     * 5. Default locale (fallback)
     *
     * Implementation Note:
     * The array-based approach is intentionally chosen over simplified conditionals because:
     * - It makes the priority order above directly visible in the code
     * - It matches standard browser locale negotiation patterns
     * - It enables safe, documented evolution of the fallback strategy
     * - It prevents subtle bugs by making all fallbacks explicit
     */
    determineLocale(preferredLocale?: string): string {
      const locales = [
        preferredLocale,
        preferredLocale?.split('-')[0],
        this.currentLocale,
        this.storedLocale,
      ];

      const supported = locales.find(
        (locale) => locale && this.supportedLocales.includes(locale)
      );

      return supported ?? this.defaultLocale;
    },

    async updateLanguage(newLocale: string) {
      this.isLoading = true;
      this.error = null;

      try {
        // Validate locale format
        const validatedLocale = localeSchema.parse(newLocale);

        // Update local state
        this.setCurrentLocale(validatedLocale);

        // Update the language for the user using the api instance
        await api.post('/api/v2/account/update-locale', {
          locale: validatedLocale,
        });

        // The CSRF token (shrimp) will be automatically updated by the api interceptor
      } catch (error) {
        this.handleError(error);
      } finally {
        this.isLoading = false; // <-- Single assignment in finally block
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
