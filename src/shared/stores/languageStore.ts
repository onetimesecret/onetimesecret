// src/shared/stores/languageStore.ts

import { hasLocaleMessages, setGlobalLocale } from '@/i18n';
import { getBootstrapValue } from '@/services/bootstrap.service';
import { loggingService } from '@/services/logging.service';
import type { PiniaPluginOptions } from '@/plugins/pinia/types';
import { localeCodeSchema } from '@/schemas/i18n/locale';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { localeCodes } from '@/sources/languages';
import { useApi } from '@/shared/composables/useApi';
import { withoutForcedReload } from '@/utils/preloadError';
import { defineStore, storeToRefs } from 'pinia';
import { computed, ref } from 'vue';

export const SESSION_STORAGE_KEY = 'selected.locale';
export const DEFAULT_LOCALE = 'en';

/**
 * Thrown (as a rejection) by setCurrentLocale() and updateLanguage() for a
 * locale that matches no supported locale. A URL or stored value naming an
 * unknown language is ordinary input, so callers can tell this apart from a
 * failed message load.
 */
export class UnsupportedLocaleError extends Error {
  readonly locale: string;

  constructor(locale: string) {
    super(`Unsupported locale: ${locale}`);
    this.name = 'UnsupportedLocaleError';
    this.locale = locale;
  }
}

/**
 * A locale whose messages did not load, and the locale the visitor sees
 * instead. LocaleLoadNotice shows it until it is dismissed or a later
 * activation succeeds.
 */
export interface LocaleLoadFailure {
  requested: string;
  shown: string;
}

export interface SetCurrentLocaleOptions {
  /**
   * Store the locale as this session's selection, which preferredLocale()
   * ranks above the domain and device locales. True (the default) for a
   * locale the visitor or the account chose: a URL locale, the account
   * locale, a language picked in the toggle. False for one the app picked
   * for them (the preferred locale, a fallback), which must not outrank a
   * domain locale that changes later in the session.
   */
  remember?: boolean;
}

interface StoreOptions extends PiniaPluginOptions {
  deviceLocale?: string;
  storageKey?: string;
}

/* eslint-disable max-lines-per-function, max-statements */
export const useLanguageStore = defineStore('language', () => {
  const $api = useApi();
  const bootstrapStore = useBootstrapStore();
  const { cust: bootstrapCust, supported_locales: bootstrapSupportedLocales } =
    storeToRefs(bootstrapStore);

  // State
  const deviceLocale = ref<string | null>(null);
  // The locale active in the global i18n composer. Null until the first
  // setCurrentLocale() succeeds; from then on its messages are always loaded.
  const currentLocale = ref<string | null>(null);
  // The target of the latest setCurrentLocale() call while its messages
  // load; null once it settles. A newer call replaces it.
  const pendingLocale = ref<string | null>(null);
  const localeLoadFailure = ref<LocaleLoadFailure | null>(null);
  const storageKey = ref<string | null>(null);
  const supportedLocales = ref<string[]>([]);
  const _initialized = ref(false);

  // Incremented by every setCurrentLocale() call, so only the latest one
  // clears pendingLocale.
  let latestSwitch = 0;

  // Getters
  const getDeviceLocale = computed(() => deviceLocale.value);
  // Before the first activation this reports the locale about to be chosen,
  // not 'en': the axios interceptor sends it as Accept-Language on requests
  // made during the initial navigation.
  const getCurrentLocale = computed(() => currentLocale.value ?? preferredLocale());
  const getStorageKey = computed(() => storageKey.value ?? SESSION_STORAGE_KEY);
  const getSupportedLocales = computed(() => supportedLocales.value);

  const acceptLanguages = computed(() => getBrowserAcceptLanguage(getCurrentLocale.value));
  const acceptLanguageHeader = computed(() => acceptLanguages.value.join(','));

  // Map supported locale codes to their display names
  const supportedLocalesWithNames = computed(() => {
    const result: Record<string, string> = {};
    for (const localeCode of supportedLocales.value) {
      if (localeCode in localeCodes) {
        result[localeCode] = localeCodes[localeCode as keyof typeof localeCodes];
      } else {
        console.warn(`[languageStore] Locale code "${localeCode}" not found in localeCodes map.`, {
          localeCode,
          hasKey: Object.hasOwn(localeCodes, localeCode),
          availableKeys: Object.keys(localeCodes).slice(0, 20),
          localeCodesType: typeof localeCodes,
        });
      }
    }
    return result;
  });

  // Actions
  /**
   * Records the store's options (storage key, device locale) and the
   * supported locales. Synchronous and idempotent: later calls change
   * nothing. Activates no locale; the router does that with
   * setCurrentLocale() during navigation.
   *
   * @returns The preferred locale (see preferredLocale)
   */
  function init(options?: StoreOptions): string {
    if (!_initialized.value) {
      _initialized.value = true;

      if (options?.storageKey) {
        storageKey.value = options.storageKey;
      }

      // Load supported locales BEFORE normalizing deviceLocale so that
      // validateAndNormalizeLocale can match against the actual list
      // (e.g. normalizing browser's "it-IT" to our "it_IT").
      loadSupportedLocales();

      if (options?.deviceLocale) {
        try {
          deviceLocale.value = validateAndNormalizeLocale(options.deviceLocale);
        } catch (error) {
          console.warn(`Invalid device locale: ${options.deviceLocale}`, error);
          deviceLocale.value = null;
        }
      }
    }

    return preferredLocale();
  }

  /**
   * The locale this visitor should see when the URL does not name one.
   * Recomputed from the current bootstrap snapshot on every call, so it
   * follows a customer swapped in by an auth refresh.
   *
   * Order: account preference > in-session selection > custom-domain brand
   * locale > device locale > the installation's default_locale > DEFAULT_LOCALE,
   * each taken only when it is among the supported locales (the operator's
   * list less the locales this build has no messages for, see
   * loadSupportedLocales). DEFAULT_LOCALE ends the list even when the
   * operator's locale list omits it (see resolveSupportedLocale), so a config
   * gap never leaves the visitor without a locale to start in.
   */
  function preferredLocale(): string {
    try {
      const isSupported = (locale: string | null | undefined): locale is string =>
        !!locale && supportedLocales.value.includes(locale);

      const candidates = [
        // Check for user preference first
        bootstrapCust.value?.locale,
        // An explicit in-session selection (recipient picking a language on the
        // page) wins over the domain default.
        loadStoredLocale(),
        // Custom-domain recipient pages default to the domain's brand locale,
        // ahead of the visitor's browser language. Without this, the saved
        // Delivery language is overwritten by navigator.language / 'en'.
        getBootstrapValue('domain_branding')?.locale,
        // Fall back to device locale, then default. deviceLocale was already
        // normalized by validateAndNormalizeLocale in init(), so it matches the
        // server's format (e.g. "it_IT").
        deviceLocale.value,
        getBootstrapValue('default_locale'),
      ];
      return candidates.find(isSupported) ?? DEFAULT_LOCALE;
    } catch (error) {
      console.error('[preferredLocale] Error:', error);
      return DEFAULT_LOCALE;
    }
  }

  /**
   * The supported locale `locale` normalizes to (it-IT -> it_IT, de-CH -> de),
   * or null when none matches. A listed locale this build has no messages for
   * is not a supported locale here (see loadSupportedLocales), so it resolves
   * to null like an unknown one. Loads and activates nothing.
   *
   * DEFAULT_LOCALE itself is always accepted, listed or not: its messages are
   * bundled, and it is preferredLocale()'s last resort, so an operator's
   * locale list without it (or an empty list) cannot fail startup.
   */
  function resolveSupportedLocale(locale: string): string | null {
    const normalizedLocale = validateAndNormalizeLocale(locale);
    if (supportedLocales.value.includes(normalizedLocale)) return normalizedLocale;
    return normalizedLocale.toLowerCase() === DEFAULT_LOCALE ? DEFAULT_LOCALE : null;
  }

  /** @throws UnsupportedLocaleError when `locale` matches no supported locale */
  function requireSupportedLocale(locale: string): string {
    const supportedLocale = resolveSupportedLocale(locale);
    if (supportedLocale === null) {
      throw new UnsupportedLocaleError(validateAndNormalizeLocale(locale));
    }
    return supportedLocale;
  }

  /**
   * Activates a locale in the global i18n instance and, unless told not to,
   * remembers it for this browser session (see SetCurrentLocaleOptions). The
   * locale changes only once its messages (and its fallbacks) are loaded and
   * registered; pendingLocale names it meanwhile. A successful activation
   * clears localeLoadFailure: the notice would name a language no longer
   * shown.
   *
   * Does not touch the account preference; updateLanguage() does that.
   *
   * @returns The active locale: `locale` normalized, or, when a newer call
   *   superseded this one before it finished, whatever is active now
   *   (unchanged by this call; 'en' before any activation).
   * @throws UnsupportedLocaleError when `locale` matches no supported locale,
   *   or the load error when its messages fail to load. Either way the active
   *   locale and session storage are unchanged.
   */
  async function setCurrentLocale(
    locale: string,
    { remember = true }: SetCurrentLocaleOptions = {}
  ): Promise<string> {
    const normalizedLocale = requireSupportedLocale(locale);

    const request = ++latestSwitch;
    pendingLocale.value = normalizedLocale;
    // Before the first activation nothing is shown yet, and a failed chunk
    // may reload the page: the deployment-skew recovery of
    // src/utils/preloadError.ts. Once a locale is shown, a reload would
    // discard LocaleLoadNotice and any unsaved input, so the switch fails in
    // place and the caller keeps that locale.
    const load = () => setGlobalLocale(normalizedLocale);
    let activated: boolean;
    try {
      activated = await (currentLocale.value === null ? load() : withoutForcedReload(load));
    } finally {
      if (request === latestSwitch) pendingLocale.value = null;
    }
    if (!activated) return currentLocale.value ?? DEFAULT_LOCALE;

    currentLocale.value = normalizedLocale;
    localeLoadFailure.value = null;
    if (remember) {
      try {
        sessionStorage.setItem(getStorageKey.value, normalizedLocale);
      } catch (error) {
        console.error('Failed to save locale to session storage:', error);
      }
    }
    return normalizedLocale;
  }

  /**
   * Settles which locale the visitor sees after `requested` failed to load,
   * and records the failure for LocaleLoadNotice. A failed language never
   * blocks the visitor:
   *  - with a locale already active, it stays;
   *  - before the first activation, the installation's default_locale is
   *    activated when it is supported, is not `requested`, and loads;
   *    otherwise DEFAULT_LOCALE, whose messages are bundled.
   * Neither is remembered as the session's selection. Logs nothing about
   * `requested` itself; the caller owns that error.
   *
   * @returns The locale shown
   * @throws Only when DEFAULT_LOCALE cannot be activated either
   */
  async function recoverFromLocaleLoadFailure(requested: string): Promise<string> {
    const failed = resolveSupportedLocale(requested) ?? requested;
    const shown = currentLocale.value ?? (await activateFallbackLocale(failed));
    localeLoadFailure.value = { requested: failed, shown };
    return shown;
  }

  async function activateFallbackLocale(failed: string): Promise<string> {
    const configured = getBootstrapValue('default_locale');
    if (
      configured &&
      configured !== failed &&
      configured !== DEFAULT_LOCALE &&
      supportedLocales.value.includes(configured)
    ) {
      try {
        return await setCurrentLocale(configured, { remember: false });
      } catch (error) {
        loggingService.error(
          error instanceof Error ? error : new Error(`[languageStore] ${String(error)}`)
        );
      }
    }
    return setCurrentLocale(DEFAULT_LOCALE, { remember: false });
  }

  /** Hides LocaleLoadNotice; the active locale stays. */
  function dismissLocaleLoadFailure(): void {
    localeLoadFailure.value = null;
  }

  function getBrowserAcceptLanguage(selectedLocale: string): Array<string> {
    // Use a Set to remove duplicates
    return [...new Set([selectedLocale, navigator.language])];
  }

  /**
   * Switches the language and saves it as the account preference. The
   * request goes out only after the locale is active; a failed switch, or
   * one superseded by a newer switch, sends nothing. A switch whose messages
   * fail to load is recorded for LocaleLoadNotice before the load error is
   * rethrown.
   */
  async function updateLanguage(newLocale: string): Promise<string> {
    const validatedLocale = requireSupportedLocale(newLocale);
    let activeLocale: string;
    try {
      activeLocale = await setCurrentLocale(validatedLocale);
    } catch (error) {
      // validatedLocale is supported, so this is a load failure.
      await recoverFromLocaleLoadFailure(validatedLocale);
      throw error;
    }
    if (activeLocale !== validatedLocale) return activeLocale;

    // Remember who asked. An auth refresh can swap the bootstrap customer
    // while the request is in flight; the snapshot patch below belongs to the
    // account that made the request, not to whoever is signed in afterwards.
    const requester = bootstrapCust.value;
    await $api.post('/api/account/update-locale', { locale: validatedLocale });

    // The server now holds the new preference, so the local bootstrap snapshot
    // must say the same. The auth route guard re-applies
    // bootstrapStore.cust.locale on every protected navigation and nothing
    // refreshes that snapshot on navigation, so a stale value there reverted
    // the user's choice (and overwrote the stored locale) on the next page.
    const current = bootstrapCust.value;
    if (requester && current && current.extid === requester.extid) {
      bootstrapStore.update({ cust: { ...current, locale: validatedLocale } });
    }
    return validatedLocale;
  }

  function determineLocale(candidate?: string): string {
    if (!candidate) return getCurrentLocale.value;

    try {
      const normalizedLocale = validateAndNormalizeLocale(candidate);
      return supportedLocales.value.includes(normalizedLocale)
        ? normalizedLocale
        : getCurrentLocale.value;
    } catch {
      return getCurrentLocale.value;
    }
  }

  // Private methods
  /**
   * Validates and normalizes a locale string against available locales.
   *
   * This function implements custom locale matching logic because:
   * 1. Vue-i18n doesn't provide locale negotiation/matching utilities
   * 2. The Intl.LocaleMatcher proposal (TC39) is not yet standardized (as of 2025)
   *    @see https://github.com/tc39/proposal-intl-localematcher
   * 3. Our server uses underscores (it_IT) while browsers often use hyphens (it-IT)
   * 4. Locale codes may have different casing (IT_IT vs it_IT)
   *
   * Matching strategy:
   * 1. First attempts exact case-insensitive match (it-IT → it_IT)
   * 2. Falls back to matching primary language code (de-CH → de if de_CH unavailable)
   * 3. Returns server's exact format to maintain consistency
   *
   * @param locale - Locale string to validate (e.g., 'en', 'it_IT', 'fr-CA')
   * @returns Normalized locale matching server's format, or original if no match found
   *
   * @example
   * // Server has: ['en', 'it_IT', 'fr_FR']
   * validateAndNormalizeLocale('it-IT')  // → 'it_IT' (case-insensitive, separator normalized)
   * validateAndNormalizeLocale('IT_IT')  // → 'it_IT' (case normalized)
   * validateAndNormalizeLocale('de-CH')  // → 'de' if 'de' available, 'de-CH' otherwise
   */
  const validateAndNormalizeLocale = (locale: string): string => {
    // A visitor's locale is untrusted input, not an API contract: malformed
    // values (mangled Accept-Language, stale stored preferences) are expected
    // and must degrade to the matching below, never be captured to Sentry
    // (#4284). Hence safeParse here instead of gracefulParse.
    const localeResult = localeCodeSchema.safeParse(locale);
    const validatedLocale = localeResult.success ? localeResult.data : locale;

    // Normalize separators for comparison (both hyphen and underscore → underscore).
    // Global replace: BCP 47 tags can carry multiple hyphens (zh-Hant-TW).
    const normalizeForComparison = (loc: string) => loc.toLowerCase().replaceAll('-', '_');

    // Strategy 1: Find exact match (case-insensitive, separator-agnostic)
    // Handles: it-IT → it_IT, IT_IT → it_IT, fr-CA → fr_CA
    const normalizedInput = normalizeForComparison(validatedLocale);
    const exactMatch = supportedLocales.value.find(
      (supported) => normalizeForComparison(supported) === normalizedInput
    );

    if (exactMatch) {
      return exactMatch; // Return server's exact format
    }

    // Strategy 2: Match primary language code only
    // Handles: de-CH → de (if de_CH unavailable but 'de' is)
    // This provides graceful degradation when exact regional variant isn't available
    const primaryCode = validatedLocale.split(/[_-]/)[0].toLowerCase();
    const primaryMatch = supportedLocales.value.find(
      (supported) => supported.toLowerCase().split(/[_-]/)[0] === primaryCode
    );

    return primaryMatch || validatedLocale;
  };

  /**
   * The operator's locale list, less any locale this build has no messages
   * for. The two can disagree: the server keeps a configured locale in
   * supported_locales when its file is missing (load_all_locales_from_source
   * in lib/onetime/initializers/load_locales.rb logs "Missing locale file"
   * and goes on to the next), and a frontend build may have been given a
   * different set of files. Dropping such a locale here keeps every reader of
   * the list consistent: the preference hierarchy and resolveSupportedLocale
   * pass over it as they pass over an unsupported one, so the visitor is
   * never shown the fallback and LocaleLoadNotice for a locale that cannot
   * load (see recoverFromLocaleLoadFailure), and the language pickers do not
   * offer a language that cannot be shown. DEFAULT_LOCALE is bundled with the
   * entry and is never dropped.
   */
  const loadSupportedLocales = () => {
    const locales = bootstrapSupportedLocales.value;
    supportedLocales.value = (Array.isArray(locales) ? locales : []).filter(
      (locale) => locale === DEFAULT_LOCALE || hasLocaleMessages(locale)
    );
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
    pendingLocale.value = null;
    localeLoadFailure.value = null;
    storageKey.value = null;
    supportedLocales.value = [];
    _initialized.value = false;
  }

  return {
    _initialized,

    // State
    deviceLocale,
    storageKey,
    supportedLocales,
    supportedLocalesWithNames,
    currentLocale,
    pendingLocale,
    localeLoadFailure,

    // Getters
    getDeviceLocale,
    getCurrentLocale,
    getStorageKey,
    getSupportedLocales,

    // Actions
    init,
    preferredLocale,
    resolveSupportedLocale,
    determineLocale,
    updateLanguage,
    setCurrentLocale,
    recoverFromLocaleLoadFailure,
    dismissLocaleLoadFailure,
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
