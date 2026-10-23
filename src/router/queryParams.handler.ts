// src/router/queryParams.handler.ts

import { useTheme } from '@/shared/composables/useTheme';
import { localeCodeSchema } from '@/schemas/i18n/locale';
import { useLanguageStore } from '@/shared/stores/languageStore';
import type { LocationQuery } from 'vue-router';

interface QueryParamHandler {
  key: string;
  /** May return a promise; processQueryParams waits for it to settle. */
  process: (value: string) => void | Promise<unknown>;
  validate?: (value: string) => boolean;
}

/** What became of one query parameter that passed validation. */
export type QueryParamResult =
  | { key: string; ok: true }
  | { key: string; ok: false; error: unknown };

export const queryParamHandlers: QueryParamHandler[] = [
  {
    key: 'locale',
    // Well formed, and one of the supported locales once normalized. An
    // unsupported locale is ignored like a malformed one (the server ignores
    // it too), so a rejection from setCurrentLocale below means the locale's
    // messages did not load.
    validate: (locale: string) =>
      localeCodeSchema.safeParse(locale).success &&
      useLanguageStore().resolveSupportedLocale(locale) !== null,
    // Settles once the locale's messages are loaded and active. A URL locale
    // is kept for the session only; it is never saved to the account.
    process: (locale: string) => useLanguageStore().setCurrentLocale(locale),
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
 * Processes URL query parameters according to registered handlers.
 *
 * Runs every handler whose parameter is present and valid, and resolves once
 * all of them have settled, with one result per handler that ran. Never
 * rejects: a handler that throws or rejects is reported in its result, and
 * the caller decides what that failure means (the route guard fails the
 * initial navigation when the locale does not load).
 *
 * @param query Vue Router query object
 */
export function processQueryParams(query: LocationQuery): Promise<QueryParamResult[]> {
  return Promise.all(
    queryParamHandlers.flatMap((handler) => {
      const value = query[handler.key];
      if (typeof value !== 'string' || !value) return [];

      if (handler.validate && !handler.validate(value)) {
        return [];
      }

      return [runHandler(handler, value)];
    })
  );
}

async function runHandler(handler: QueryParamHandler, value: string): Promise<QueryParamResult> {
  try {
    await handler.process(value);
    return { key: handler.key, ok: true };
  } catch (error) {
    return { key: handler.key, ok: false, error };
  }
}
