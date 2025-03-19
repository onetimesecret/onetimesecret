// src/stores/languageStore.ts

import { setGlobalLocale } from '@/i18n';
import type { PiniaPluginOptions } from '@/plugins/pinia/types';
import { localeSchema } from '@/schemas/i18n/locale';
import { WindowService } from '@/services/window.service';
import type { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, inject, ref, watch } from 'vue';

export const SESSION_STORAGE_KEY = 'selected.locale';
export const DEFAULT_LOCALE = 'en';

interface StoreOptions extends PiniaPluginOptions {
  deviceLocale?: string;
  storageKey?: string;
}

/* eslint-disable max-lines-per-function */
export const useLanguageStore = defineStore('language', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const deviceLocale = ref<string | null>(null);
  const currentLocale = ref<string | null>(null);
  const storageKey = ref<string | null>(null);
  const supportedLocales = ref<string[]>([]);
  const storedLocale = ref<string | null>(null);
  const _initialized = ref(false);

  // Getters
  const getDeviceLocale = computed(() => deviceLocale.value);
  const getCurrentLocale = computed(() => currentLocale.value ?? DEFAULT_LOCALE);
  const getStorageKey = computed(() => storageKey.value ?? SESSION_STORAGE_KEY);
  const getSupportedLocales = computed(() => supportedLocales.value);

  const acceptLanguages = computed(() => getBrowserAcceptLanguage(getCurrentLocale.value));
  const acceptLanguageHeader = computed(() => acceptLanguages.value.join(','));

  // Actions
  function init(options?: StoreOptions) {
    if (_initialized.value) return getCurrentLocale.value;

    if (options?.deviceLocale) {
      deviceLocale.value = validateAndNormalizeLocale(options.deviceLocale);
    }
    if (options?.storageKey) {
      storageKey.value = options.storageKey;
    }

    watch(
      () => currentLocale.value,
      async (newLocale) => {
        if (newLocale) {
          await setGlobalLocale(newLocale);
        }
      }
    );

    return initializeLocale();
  }

  function initializeLocale() {
    try {
      loadSupportedLocales();

      // Check for user preference first
      const userLocale = WindowService.get('cust')?.locale;
      if (userLocale && supportedLocales.value.includes(userLocale)) {
        currentLocale.value = userLocale;
        return getCurrentLocale.value;
      }
      // Fall back to stored/device locale
      storedLocale.value = loadStoredLocale();
      if (storedLocale.value && supportedLocales.value.includes(storedLocale.value)) {
        currentLocale.value = storedLocale.value;
      } else if (deviceLocale.value) {
        const primaryLocale = deviceLocale.value.split('-')[0];
        currentLocale.value = supportedLocales.value.includes(primaryLocale)
          ? primaryLocale
          : DEFAULT_LOCALE;
      }

      _initialized.value = true;
      return getCurrentLocale.value;
    } catch (error) {
      console.error('[initializeLocale] Error:', error);
      currentLocale.value = DEFAULT_LOCALE;
      return DEFAULT_LOCALE;
    }
  }

  function setCurrentLocale(locale: string) {
    const normalizedLocale = validateAndNormalizeLocale(locale);
    if (supportedLocales.value.includes(normalizedLocale)) {
      currentLocale.value = normalizedLocale;
      try {
        sessionStorage.setItem(getStorageKey.value, normalizedLocale);
      } catch (error) {
        console.error('Failed to save locale to session storage:', error);
      }
    }
  }

  function getBrowserAcceptLanguage(selectedLocale: string): Array<string> {
    // Use a Set to remove duplicates
    return [...new Set([selectedLocale, navigator.language])];
  }

  async function updateLanguage(newLocale: string) {
    const validatedLocale = validateAndNormalizeLocale(newLocale);
    if (!supportedLocales.value.includes(validatedLocale)) {
      throw new Error(`Unsupported locale: ${validatedLocale}`);
    }

    await setGlobalLocale(validatedLocale); // via i18n
    setCurrentLocale(validatedLocale); // save to session storage
    await $api.post('/api/v2/account/update-locale', { locale: validatedLocale });
    return validatedLocale;
  }

  function determineLocale(preferredLocale?: string): string {
    if (!preferredLocale) return getCurrentLocale.value;

    const normalizedLocale = validateAndNormalizeLocale(preferredLocale);
    return supportedLocales.value.includes(normalizedLocale)
      ? normalizedLocale
      : getCurrentLocale.value;
  }

  // Private methods
  const validateAndNormalizeLocale = (locale: string): string => {
    try {
      return localeSchema.parse(locale);
    } catch (error) {
      console.warn(`Invalid locale format: ${locale}`, error);
      return DEFAULT_LOCALE;
    }
  };

  const loadSupportedLocales = () => {
    const locales = WindowService.get('supported_locales');
    supportedLocales.value = Array.isArray(locales) ? locales : [];
  };

  const loadStoredLocale = () => {
    try {
      return sessionStorage.getItem(getStorageKey.value);
    } catch (error) {
      console.error('[loadStoredLocale] Error:', error);
      return null;
    }
  };

  function $reset() {
    deviceLocale.value = null;
    currentLocale.value = null;
    storageKey.value = null;
    supportedLocales.value = [];
    storedLocale.value = null;
    _initialized.value = false;
  }

  return {
    _initialized,

    // State
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
    initializeLocale,
    determineLocale,
    updateLanguage,
    setCurrentLocale,
    acceptLanguages,
    acceptLanguageHeader,

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
