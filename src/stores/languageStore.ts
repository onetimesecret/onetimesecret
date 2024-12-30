// src/stores/languageStore.ts

import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { z } from 'zod';

import { useWindowStore } from './windowStore';

const SESSION_STORAGE_KEY = 'selected.locale';
const DEFAULT_LOCALE = 'en';

//const supportedLocales = window.supported_locales;

// Schema for locale validation
const localeSchema = z
  .string()
  .min(2)
  .max(5)
  .regex(/^[a-z]{2}(-[A-Z]{2})?$/);

interface LanguageStoreOptions {
  deviceLocale?: string;
  storageKey?: string;
}

interface StoreState {
  isLoading: boolean;
  deviceLocale: string;
  storageKey: string;
  supportedLocales: string[];
  storedLocale: string | null;
  currentLocale: string | null;
}

export const useLanguageStore = defineStore('language', {
  state: (options?: LanguageStoreOptions): StoreState => ({
    isLoading: false,
    deviceLocale: options?.deviceLocale ?? DEFAULT_LOCALE,
    storageKey: options?.storageKey ?? SESSION_STORAGE_KEY,
    supportedLocales: [],
    storedLocale: null,
    currentLocale: null,
  }),

  getters: {
    getDeviceLocale: (state) => state.deviceLocale,
    getCurrentLocale: (state) => state.currentLocale,
    getStorageKey: (state) => state.storageKey,
    getSupportedLocales: (state) => state.supportedLocales,
  },

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    init(api?: AxiosInstance) {
      this._ensureErrorHandler(api);

      const windowStore = useWindowStore();
      windowStore.init();

      this.supportedLocales = windowStore.supported_locales ?? [];

      return this.initializeLocale();
    },

    _ensureErrorHandler(api?: AxiosInstance) {
      if (!this._errorHandler) this.setupErrorHandler(api);
    },

    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify,
        log: options.log,
      });
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
     *
     * This is a synchronous method that should be called once during store initialization.
     */
    initializeLocale() {
      try {
        this.storedLocale = sessionStorage.getItem(this.storageKey);

        // Extract primary language code (e.g., 'en-NZ' -> 'en')
        const primaryLocale = this.deviceLocale.split('-')[0];
        this.currentLocale = this.storedLocale || primaryLocale;

        return this.currentLocale;
      } catch (error) {
        console.error('[initializeLocale] Error:', error, this.currentLocale);
        return (this.currentLocale = this.deviceLocale);
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

      return supported ?? DEFAULT_LOCALE;
    },

    async updateLanguage(newLocale: string) {
      return await this._errorHandler!.withErrorHandling(async () => {
        // Validate locale format
        const validatedLocale = localeSchema.parse(newLocale);

        // Update local state
        this.setCurrentLocale(validatedLocale);

        // Update the language for the user using the api instance
        await this._api!.post('/api/v2/account/update-locale', {
          locale: validatedLocale,
        });
      });
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
