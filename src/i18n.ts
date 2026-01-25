// src/i18n.ts

import { type Locale } from '@/schemas/i18n/locale';
import { getBootstrapValue } from '@/services/bootstrap.service';
import { createI18n, type Composer } from 'vue-i18n';

/**
 * Internationalization configuration and utilities.
 * Sets up Vue i18n instance with locale management and message loading.
 *
 * Locale files are pre-merged by the Python sync script into single files
 * at generated/locales/{locale}.json. This simplifies the frontend loading
 * by eliminating the need for runtime merging of split locale files.
 */

/**
 * Import pre-merged locale files directly from generated directory.
 * The Python sync script (locales/scripts/build/compile.py --merged) produces
 * these files during development and build.
 */
// Using type assertion for Vite's import.meta.glob (types from vite/client reference)
// Note: Since vite.config.ts sets root: './src', paths starting with / are relative to src/
// We use /../generated to go up one level to the project root where generated/ lives
const localeModules = (import.meta as any).glob('/../generated/locales/*.json', {
  eager: true,
}) as Record<string, { default: Record<string, any> }>;

const messages: Record<string, any> = {};

// Simple extraction - files are already merged by the Python sync script
for (const path in localeModules) {
  // Extract locale code from path: /generated/locales/en.json -> en
  const match = path.match(/\/locales\/([^/]+)\.json$/);
  if (match) {
    const locale = match[1];
    messages[locale] = localeModules[path].default;
  }
}

type GlobalComposer = Composer<{}, {}, {}, Locale>;

/**
 * The list of supported locales comes directly from etc/config.yaml.
 */
const domainBranding = getBootstrapValue('domain_branding');
const supportedLocales = getBootstrapValue('supported_locales') || [];
const fallbackLocale = getBootstrapValue('fallback_locale') || {};
const defaultLocale = getBootstrapValue('default_locale') || 'en';
const displayLocale = domainBranding?.locale ?? getBootstrapValue('locale');

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
    messages, // All locales pre-loaded and merged via import.meta.glob()
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
   * Note: All locales are pre-loaded and merged at module load time
   * via import.meta.glob() in this file, so no dynamic loading is needed.
   */
  const setLocale = async (locale: string) => {
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
export default i18n;
export { globalComposer, setGlobalLocale };
