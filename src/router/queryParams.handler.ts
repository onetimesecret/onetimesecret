// src/router/queryParams.handler.ts

import { localeSchema } from '@/schemas/i18n/locale';
import { useLanguageStore } from '@/stores/languageStore';
import { useTheme } from '@/composables/useTheme';

interface QueryParamHandler {
  key: string;
  process: (value: string) => void;
  validate?: (value: string) => boolean;
}

export const queryParamHandlers: QueryParamHandler[] = [
  {
    key: 'locale',
    validate: (locale: string) => localeSchema.safeParse(locale).success,
    process: (locale: string) => {
      const languageStore = useLanguageStore();
      languageStore.setCurrentLocale(locale);
    },
  },
  {
    key: 'theme',
    validate: (theme: string) => ['dark', 'light'].includes(theme),
    process: (theme: string) => {
      const themeStore = useTheme();
      themeStore.setTheme(theme);
    },
  },
];

/**
 * Processes URL query parameters according to registered handlers
 * @param query Vue Router query object
 *
 */
export function processQueryParams(query: Record<string, string>): void {
  queryParamHandlers.forEach((handler) => {
    const value = query[handler.key];
    if (!value) return;

    if (handler.validate && !handler.validate(value)) {
      return;
    }

    handler.process(value);
  });
}
