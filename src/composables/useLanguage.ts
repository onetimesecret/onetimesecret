// src/composables/useLanguage.ts

import { ref, reactive, computed } from 'vue';
import { useLanguageStore } from '@/stores/languageStore';

import { useAsyncHandler, AsyncHandlerOptions } from './useAsyncHandler';

const languageListeners = new Set<(locale: string) => void>();
const isInitialized = ref(false);

/* eslint-disable max-lines-per-function */
export function useLanguage(options?: AsyncHandlerOptions) {
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
    if (!isInitialized.value) {
      isInitialized.value = true;
      return languageStore.init();
    }
  };

  const onLanguageChange = (callback: (locale: string) => void) => {
    languageListeners.add(callback);
    return () => languageListeners.delete(callback);
  };

  const updateLanguage = (newLocale: string) => wrap(() => languageStore.updateLanguage(newLocale));

  return {
    // Expose store values through composable
    currentLocale: computed(() => languageStore.getCurrentLocale),
    supportedLocales: computed(() => languageStore.getSupportedLocales),
    supportedLocalesWithNames: computed(() => languageStore.getSupportedLocalesWithNames),

    // Encapsulate business logic and side effects
    updateLanguage,
    initializeLanguage,
    onLanguageChange,
    state,
  };
}
