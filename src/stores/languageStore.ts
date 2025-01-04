// src/stores/languageStore.ts

import { AsyncHandlerOptions, useAsyncHandler } from '@/composables/useAsyncHandler';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, ref, watch } from 'vue';
import { z } from 'zod';

import { setLanguage } from '@/i18n';
import { WindowService } from '@/services/window.service';

export const SESSION_STORAGE_KEY = 'selected.locale';
export const DEFAULT_LOCALE = 'en';

const localeSchema = z
  .string()
  .min(2)
  .max(5)
  .regex(/^[a-z]{2}(-[A-Z]{2})?$/);

interface StoreOptions {
  deviceLocale?: string;
  storageKey?: string;
}

/* eslint-disable max-lines-per-function */
export const useLanguageStore = defineStore('language', () => {
  // State
  const isLoading = ref<boolean>(false);
  const deviceLocale = ref<string | null>(null);
  const currentLocale = ref<string | null>(null);
  const storageKey = ref<string | null>(null);
  const supportedLocales = ref<string[]>([]);
  const storedLocale = ref<string | null>(null);
  const _initialized = ref(false);

  // Private state
  let _api: AxiosInstance | null = null;
  let _errorHandler: ReturnType<typeof useAsyncHandler> | null = null;

  // Getters
  const getDeviceLocale = computed(() => deviceLocale.value);
  const getCurrentLocale = computed(() => currentLocale.value ?? DEFAULT_LOCALE);
  const getStorageKey = computed(() => storageKey.value ?? SESSION_STORAGE_KEY);
  const getSupportedLocales = computed(() => supportedLocales.value);

  // Actions
  function init(api?: AxiosInstance, options?: StoreOptions) {
    _ensureAsyncHandler(api);

    // Set device locale from options if provided
    if (options?.deviceLocale) {
      deviceLocale.value = options.deviceLocale;
    }

    // Set custom storage key if provided
    if (options?.storageKey) {
      storageKey.value = options.storageKey;
    }

    setLanguage(getCurrentLocale.value);

    watch(
      () => currentLocale.value,
      async (newLocale) => {
        if (newLocale) {
          await setLanguage(newLocale);
        }
      }
    );

    return initializeLocale();
  }

  function setupAsyncHandler(
    api: AxiosInstance = createApi(),
    options: AsyncHandlerOptions = {}
  ) {
    _api = api;
    _errorHandler = useAsyncHandler({
      setLoading: (loading) => (isLoading.value = loading),
      notify: options.notify,
      log: options.log,
    });
  }

  function _ensureAsyncHandler(api?: AxiosInstance) {
    if (!_errorHandler) setupAsyncHandler(api);
  }

  function initializeLocale() {
    try {

      supportedLocales.value = WindowService.get("supported_locales", []);

      storedLocale.value = sessionStorage.getItem(getStorageKey.value);

      // First try to use stored locale
      if (storedLocale.value) {
        currentLocale.value = storedLocale.value;
      }
      // Then fallback to device locale if available
      else if (deviceLocale.value) {
        const primaryLocale = deviceLocale.value.split('-')[0];
        currentLocale.value = primaryLocale;
      }

      return getCurrentLocale;
    } catch (error) {
      console.error('[initializeLocale] Error:', error, currentLocale.value);
      return (currentLocale.value = deviceLocale.value);
    }
  }

  function determineLocale(preferredLocale?: string): string {
    const locales = [
      preferredLocale,
      preferredLocale?.split('-')[0],
      currentLocale.value,
      storedLocale.value,
    ];

    const supported = locales.find(
      (locale) => locale && supportedLocales.value.includes(locale)
    );

    return supported ?? DEFAULT_LOCALE;
  }

  function setCurrentLocale(locale: string) {
    if (supportedLocales.value.includes(locale)) {
      currentLocale.value = locale;
      sessionStorage.setItem(getStorageKey.value, locale);
    } else {
      console.warn(`Unsupported locale: ${locale}`);
    }
  }

  async function updateLanguage(newLocale: string) {
    return await _errorHandler!.withErrorHandling(async () => {
      const validatedLocale = localeSchema.parse(newLocale);
      setCurrentLocale(validatedLocale);
      await _api!.post('/api/v2/account/update-locale', {
        locale: validatedLocale,
      });
    });
  }

  function $reset() {
    isLoading.value = false;
    deviceLocale.value = null;
    currentLocale.value = null;
    storageKey.value = null;
    supportedLocales.value = [];
    storedLocale.value = null;
    _initialized.value = false;
  }

  return {
    // State
    isLoading,
    deviceLocale,
    storageKey,
    supportedLocales,
    storedLocale,
    currentLocale,

    // Getters
    getDeviceLocale,
    getCurrentLocale,
    getStorageKey,
    getSupportedLocales,

    // Actions
    init,
    setupAsyncHandler,
    initializeLocale,
    determineLocale,
    updateLanguage,
    setCurrentLocale,

    $reset,
  };
});

/**
 * Future considerations:
 *   1. API requests: Include language in request headers
 *     axios.defaults.headers.common['Accept-Language'] = newLocale;
 *   2. SEO: Update URL to include language code
 *     router.push(`/${newLocale}${router.currentRoute.value.path}`);
 *   3. SSR: If using SSR, ensure server-side logic is updated
 *     This might involve server-side routing or state management
 */
