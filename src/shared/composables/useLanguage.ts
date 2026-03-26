// src/shared/composables/useLanguage.ts

import { useLanguageStore } from '@/shared/stores/languageStore';
import { ref, reactive, computed } from 'vue';

import { useAsyncHandler, AsyncHandlerOptions } from './useAsyncHandler';

const isInitialized = ref(false);

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

  const updateLanguage = (newLocale: string) => wrap(() => languageStore.updateLanguage(newLocale));

  return {
    // Expose store values through composable (wrapped in computed for reactivity)
    currentLocale: computed(() => languageStore.getCurrentLocale),
    supportedLocales: computed(() => languageStore.getSupportedLocales),
    supportedLocalesWithNames: computed(() => languageStore.supportedLocalesWithNames),

    // Encapsulate business logic and side effects
    updateLanguage,
    initializeLanguage,
    state,
  };
}
