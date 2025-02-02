// src/stores/languageStore.ts

import type { PiniaCustomProperties } from 'pinia';
import { defineStore } from 'pinia';
import { computed, inject, ref, watch } from 'vue';
import { z } from 'zod';

import { setLanguage } from '@/i18n';
import { PiniaPluginOptions } from '@/plugins/pinia/types';
import { WindowService } from '@/services/window.service';
import { AxiosInstance } from 'axios';

export const SESSION_STORAGE_KEY = 'selected.locale';
export const DEFAULT_LOCALE = 'en';

const localeSchema = z
  .string()
  .min(2)
  .max(5)
  .regex(/^[a-z]{2}(-[A-Z]{2})?$/);

interface StoreOptions extends PiniaPluginOptions {
  deviceLocale?: string;
  storageKey?: string;
}

/**
 * Type definition for LanguageStore.
 */
export type LanguageStore = {
  // State
  deviceLocale: string | null;
  currentLocale: string;
  storageKey: string;
  supportedLocales: string[];
  storedLocale: string | null;
  _initialized: boolean;

  // Getters
  getDeviceLocale: string | null;
  getCurrentLocale: string;
  getStorageKey: string;
  getSupportedLocales: string[];

  // Actions
  init: (options?: StoreOptions) => void;
  initializeLocale: () => string | null;
  determineLocale: (preferredLocale?: string) => string;
  setCurrentLocale: (locale: string) => void;
  updateLanguage: (newLocale: string) => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

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

  // Actions

  function init(options?: StoreOptions) {
    // Set device locale from options if provided
    if (options?.deviceLocale) {
      deviceLocale.value = options.deviceLocale;
    }

    // Set custom storage key if provided
    if (options?.storageKey) {
      storageKey.value = options.storageKey;
    }
    // console.log(100000, options);
    // // Set custom storage key if provided
    // if (options?.api) {
    //   $api = options.api;
    // }

    // Don't set language here. We want to allow the calling code to set the
    // language if it so chooses. It does this for example in the LanguageToggle
    // component.
    //
    // ❌ setLanguage(getCurrentLocale.value);

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

  function initializeLocale() {
    try {
      supportedLocales.value = WindowService.get('supported_locales') ?? [];

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

    const supported = locales.find((locale) => locale && supportedLocales.value.includes(locale));

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
    const validatedLocale = localeSchema.parse(newLocale);
    setCurrentLocale(validatedLocale);
    await $api.post('/api/v2/account/update-locale', {
      locale: validatedLocale,
    });
  }

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
