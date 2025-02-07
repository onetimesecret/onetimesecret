// src/composables/useLanguage.ts

import { ref, inject } from 'vue';
import type { AxiosInstance } from 'axios';
import { useLanguageStore } from '@/stores/languageStore';
import { setLanguage } from '@/i18n';
import { z } from 'zod';

const languageListeners = new Set<(locale: string) => void>();
const isInitialized = ref(false);

const localeSchema = z
  .string()
  .min(2)
  .max(5)
  .regex(/^([a-z]{2})([_\-]([a-z]{2}))?$/i);

export function useLanguage() {
  const $api = inject('api') as AxiosInstance;
  const languageStore = useLanguageStore();

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

  const updateLanguage = async (newLocale: string) => {
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
  };

  const saveLanguage = async (newLocale: string) => {
    const validatedLocale = localeSchema.parse(newLocale);
    await $api.post('/api/v2/account/update-locale', { locale: validatedLocale });
  };

  return {
    currentLocale: languageStore.getCurrentLocale,
    supportedLocales: languageStore.getSupportedLocales,
    isInitialized,
    initializeLanguage,
    onLanguageChange,
    updateLanguage,
    saveLanguage,
    clearLanguageListeners: () => languageListeners.clear(),
  };
}
