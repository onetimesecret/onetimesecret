// src/i18n.ts

import { type Locale } from '@/schemas/i18n/locale';
import { getBootstrapValue } from '@/services/bootstrap.service';
import { createI18n, type Composer } from 'vue-i18n';

/**
 * Internationalization configuration and utilities.
 * Sets up Vue i18n instance with locale management and message loading.
 *
 * Locale files are pre-merged by the Python sync script
 * (locales/scripts/i18n content compile) into single files at
 * generated/locales/{locale}.json.
 *
 * Loading strategy (#4288)
 * ------------------------
 * Eagerly importing every merged locale put ~8.8 MB of JSON inside the single
 * customer chunk — 89% of a 2.6 MB gzipped bundle that the secret link page
 * cannot render one character without. Every recipient downloaded all 30
 * languages to read one.
 *
 * So only English is bundled, and it earns its place: it is the source
 * language and the tail of every fallback chain, which makes it the safety net
 * when a locale fetch fails. The other locales are emitted as standalone
 * hashed JSON assets — `?url` keeps the CONTENT out of the chunk and hands
 * back the public URL — and are fetched on demand, one request for the one
 * language the visitor actually reads.
 */
const BUNDLED_LOCALE = 'en';

/**
 * Import the pre-merged locale files from the generated directory.
 *
 * Note: since vite.config.ts sets root: './src', paths starting with / are
 * relative to src/. We use /../generated to go up one level to the project
 * root where generated/ lives.
 *
 * Vite requires these patterns to be literals, so 'en' is spelled out rather
 * than interpolated from BUNDLED_LOCALE — change one and change all three.
 */
const bundledLocaleModules = import.meta.glob('/../generated/locales/en.json', {
  eager: true,
}) as Record<string, { default: Record<string, unknown> }>;

// The bundled locale is excluded from this second glob on purpose: emitting no
// asset for it is what lets the backend decide whether to preload by asking the
// manifest, rather than keeping its own copy of BUNDLED_LOCALE that could drift.
const localeAssetModules = import.meta.glob(
  ['/../generated/locales/*.json', '!/../generated/locales/en.json'],
  {
    eager: true,
    query: '?url',
    import: 'default',
  }
) as Record<string, string>;

/** Locale code from a merged locale path: /../generated/locales/en.json -> en */
const localeCodeFromPath = (path: string): string | undefined =>
  path.match(/\/locales\/([^/]+)\.json$/)?.[1];

/**
 * Messages loaded so far, keyed by locale code. Seeded with the bundled
 * locale and filled in by loadLocaleMessages as other locales arrive.
 */
const messages: Record<string, any> = {};

for (const path in bundledLocaleModules) {
  const locale = localeCodeFromPath(path);
  if (locale) {
    messages[locale] = bundledLocaleModules[path].default;
  }
}

/** Public URL of each locale's standalone JSON asset, keyed by locale code. */
const localeAssetUrls: Record<string, string> = {};

for (const path in localeAssetModules) {
  const locale = localeCodeFromPath(path);
  if (locale) {
    localeAssetUrls[locale] = localeAssetModules[path];
  }
}

/** In-flight fetches, so concurrent callers share one request per locale. */
const pendingLoads = new Map<string, Promise<Record<string, unknown> | null>>();

/**
 * Fetches (once) the messages for a locale that isn't already loaded.
 *
 * @param locale - Locale code, e.g. 'de_AT'
 * @returns The messages, or null when the locale has no asset or the fetch
 *   failed. Callers treat null as "keep what is already loaded" rather than as
 *   a reason to abort: an untranslated page beats a blank one.
 *
 * The bare `fetch(url)` — default `credentials: 'same-origin'` — is
 * load-bearing: it is what matches the anonymous `crossorigin` attribute on
 * the preload link the shell emits for the active locale (see
 * Core::Views::ViteManifest#build_locale_preloads). Chrome compares the two
 * credentials modes, and on a mismatch discards the preloaded response and
 * downloads the file a second time (measured, both ways round). Change one
 * side and you have to change the other.
 */
export function loadLocaleMessages(locale: string): Promise<Record<string, unknown> | null> {
  const loaded = messages[locale];
  if (loaded) return Promise.resolve(loaded);

  const url = localeAssetUrls[locale];
  if (!url) return Promise.resolve(null);

  let pending = pendingLoads.get(locale);
  if (!pending) {
    pending = fetch(url)
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Failed to load locale '${locale}': HTTP ${response.status}`);
        }
        return response.json();
      })
      .then((localeMessages: Record<string, unknown>) => {
        messages[locale] = localeMessages;
        return localeMessages;
      })
      .catch((error: unknown) => {
        console.warn(`[i18n] Falling back to '${BUNDLED_LOCALE}' messages`, error);
        return null;
      })
      .finally(() => {
        pendingLoads.delete(locale);
      });
    pendingLoads.set(locale, pending);
  }

  return pending;
}

type GlobalComposer = Composer<{}, {}, {}, Locale>;

/**
 * The list of supported locales comes directly from etc/config.yaml.
 */
const domainBranding = getBootstrapValue('domain_branding');
const supportedLocales = getBootstrapValue('supported_locales') || [];
const fallbackLocale = getBootstrapValue('fallback_locale') || {};
const defaultLocale = getBootstrapValue('default_locale') || 'en';
// Resolved (never undefined) so loadDisplayLocaleMessages below has a locale
// to load; createI18nInstance's default parameter used to absorb the undefined.
const displayLocale: string =
  domainBranding?.locale ?? getBootstrapValue('locale') ?? defaultLocale;

/**
 * Creates a completely independent i18n instance with its own locale state and message
 * store. We eat this dogfood below to create the global i18n instance as well.
 *
 * This differs from useI18n({ useScope: 'local' }) which only provides component-level
 * message isolation within the global instance. Local scope - still uses global
 * instance but with component-isolated messages. When the global locale changes, the
 * local scope will update accordingly.
 *
 * Use createI18nInstance when you need:
 *
 * - A fully isolated instance that won't affect or be affected by the global app locale
 * - Independent message loading and locale switching
 * - Preview/sandbox functionality that should remain separate from the main app
 * - Testing scenarios where global state isolation is required
 *
 * @param initialLocale - Initial locale to use for this instance
 * @returns Object containing:
 *   - instance (I18n): The raw i18n instance.
 *   - composer (Composer): The composer for accessing translations.
 *   - setLocale (Locale): Function to change locale for this instance only.
 */
export function createI18nInstance(initialLocale: string = defaultLocale) {
  const instance = createI18n<false>({
    legacy: false, // Enable composition API.
    locale: initialLocale,
    fallbackLocale: fallbackLocale,
    globalInjection: true, // allows $t to be used globally.
    missingWarn: true, // these enable browser console logging
    fallbackWarn: true, // and are removed from prod builds.
    messages: { ...messages }, // whatever has been loaded so far; setLocale adds the rest
    availableLocales: supportedLocales,
  });

  /**
   * Access the root Composer for this i18n instance.
   *
   * Vue I18n has a hierarchical structure:
   * - instance.global: The root Composer handling translations at instance level
   * - useI18n(): Component-level Composer that inherits from instance.global
   * - useI18n({ useScope: 'local' }): Isolated component-level Composer
   *
   * Even for non-global instances (like preview instances), we still access
   * the root Composer via .global since it represents the root scope of that
   * specific instance.
   *
   * @see https://vue-i18n.intlify.dev/guide/advanced/scope.html
   */
  const composer = instance.global as GlobalComposer;

  /**
   * Updates locale for this instance only
   * @param locale - Target locale to set
   *
   * Awaits the locale's messages before switching, so the instance never
   * renders a locale it has no messages for. When the load yields nothing
   * (unknown locale, failed fetch) the switch still happens and vue-i18n
   * resolves through the fallback chain to the bundled English.
   */
  const setLocale = async (locale: string) => {
    const localeMessages = await loadLocaleMessages(locale);
    if (localeMessages) {
      composer.setLocaleMessage(locale, localeMessages);
    }
    if (!composer.availableLocales.includes(locale)) {
      console.warn(`Locale ${locale} is not in available locales. Attempting to set anyway.`);
    }
    composer.locale.value = locale;
  };

  return {
    instance,
    composer,
    setLocale,
  };
}

/** Create and export the global instance */
const {
  instance: i18n,
  composer: globalComposer,
  setLocale: setGlobalLocale,
} = createI18nInstance(displayLocale);

/**
 * Loads the messages for the locale the first paint will render in.
 *
 * Call this before mounting: with only English in the bundle, mounting first
 * would flash English at a non-English recipient. Resolves (never rejects)
 * even when the fetch fails, so a locale asset that 404s costs a translation,
 * not the page.
 */
export function loadDisplayLocaleMessages(): Promise<void> {
  return setGlobalLocale(displayLocale);
}

export default i18n;
export { globalComposer, setGlobalLocale };
