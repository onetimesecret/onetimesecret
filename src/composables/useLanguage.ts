// src/composables/useLanguage.ts

import { ref, inject, reactive, computed } from 'vue';
import type { AxiosInstance } from 'axios';
import { useLanguageStore } from '@/stores/languageStore';
import { setLanguage } from '@/i18n';
import { localeSchema } from '@/schemas/i18n/locale';
import { useAsyncHandler, AsyncHandlerOptions } from './useAsyncHandler';

const languageListeners = new Set<(locale: string) => void>();
const isInitialized = ref(false);

/* eslint-disable max-lines-per-function */
export function useLanguage(options?: AsyncHandlerOptions) {
  const $api = inject('api') as AxiosInstance;
  const languageStore = useLanguageStore();

  const state = reactive({
    isLoading: false,
    error: '',
    success: '',
  });

  const defaultOptions: AsyncHandlerOptions = {
    notify: (message, severity) => {
      if (severity === 'error') {
        state.error = message;
      } else {
        state.success = message;
      }
    },
    setLoading: (loading) => (state.isLoading = loading),
    onError: () => (state.success = ''),
    ...options,
  };

  const { wrap } = useAsyncHandler(defaultOptions);

  const initializeLanguage = () => {
    if (isInitialized.value) return;

    const locale = languageStore.getCurrentLocale;
    if (locale) {
      setLanguage(locale);
      notifyListeners(locale);
    }

    isInitialized.value = true;
    return locale;
  };

  const onLanguageChange = (callback: (locale: string) => void) => {
    languageListeners.add(callback);
    return () => languageListeners.delete(callback);
  };

  const notifyListeners = (locale: string) => {
    languageListeners.forEach((listener) => listener(locale));
  };

  const updateLanguage = (newLocale: string) =>
    wrap(async () => {
      const validatedLocale = localeSchema.parse(newLocale);

      if (!languageStore.getSupportedLocales.includes(validatedLocale)) {
        throw new Error(`Unsupported locale: ${validatedLocale}`);
      }

      await Promise.all([
        setLanguage(validatedLocale),
        languageStore.setCurrentLocale(validatedLocale),
      ]);

      notifyListeners(validatedLocale);
      return validatedLocale;
    });

  const saveLanguage = (newLocale: string) =>
    wrap(async () => {
      const validatedLocale = localeSchema.parse(newLocale);
      await $api.post('/api/v2/account/update-locale', { locale: validatedLocale });
    });

  return {
    // Expose store values through composable
    currentLocale: computed(() => languageStore.getCurrentLocale),
    supportedLocales: computed(() => languageStore.getSupportedLocales),

    // Encapsulate business logic and side effects
    updateLanguage,
    saveLanguage,
    initializeLanguage,
    onLanguageChange,
    state,
  };
}
