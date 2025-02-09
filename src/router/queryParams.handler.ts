// src/router/queryParams.handler.ts
//
import { useLanguageStore } from '@/stores/languageStore';
import { useTheme } from '@/composables/useTheme';

interface QueryParamHandler {
  key: string;
  process: (value: string) => void;
  validate?: (value: string) => boolean;
}

interface StorageOptions {
  storage?: Storage;
  key: string;
}

export const createQueryParamHandler = (handler: QueryParamHandler, storage?: StorageOptions) => ({
  ...handler,
  storage,
});

export const queryParamHandlers = [
  createQueryParamHandler(
    {
      key: 'locale',
      validate: (locale: string) => /^[a-z]{2}_[A-Z]{2}$/.test(locale),
      process: (locale: string) => {
        const languageStore = useLanguageStore();
        languageStore.setCurrentLocale(locale);
      },
    },
    { storage: sessionStorage, key: 'user_locale' }
  ),
  createQueryParamHandler(
    {
      key: 'theme',
      validate: (theme: string) => ['dark', 'light'].includes(theme),
      process: (theme: string) => {
        const themeStore = useTheme();
        themeStore.setTheme(theme);
      },
    },
    { storage: sessionStorage, key: 'user_theme' }
  ),
];

/**
 * Processes URL query parameters according to registered handlers
 * @param query Vue Router query object
 *
 * Usage:
 * 1. Add new handlers to queryParamHandlers array
 * 2. Define validation and processing logic
 * 3. Optionally specify storage configuration
 *
 * Handler Lifecycle:
 * 1. Validation (optional)
 * 2. Processing (required)
 * 3. Storage (optional)
 */
export function processQueryParams(query: Record<string, string>): void {
  queryParamHandlers.forEach((handler) => {
    const value = query[handler.key];
    if (!value) return;

    if (handler.validate && !handler.validate(value)) {
      return;
    }

    handler.process(value);

    if (handler.storage) {
      handler.storage.storage?.setItem(handler.storage.key, value);
    }
  });
}
