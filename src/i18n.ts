// src/i18n.ts

import en from '@/locales/en.json';
import { WindowService } from '@/services/window.service';
import { createI18n, type Composer } from 'vue-i18n';
import { type Locale } from '@/schemas/i18n/locale';

/**
 * Internationalization configuration and utilities.
 * Sets up Vue i18n instance with locale management and message loading.
 */

type MessageSchema = typeof en;
type GlobalComposer = Composer<{}, {}, {}, Locale>;

/**
 * The list of supported locales comes directly from etc/config.yaml.
 */
const supportedLocales = WindowService.get('supported_locales') || [];
const fallbackLocale = WindowService.get('fallback_locale') || {};
const defaultLocale = WindowService.get('default_locale') || 'en';

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
    messages: {
      en, // Always include default messages
    },
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
   */
  const setLocale = async (locale: string) => {
    if (!composer.availableLocales.includes(locale)) {
      const messages = await loadLocaleMessages(locale);
      if (messages) {
        composer.setLocaleMessage(locale, messages);
      }
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
} = createI18nInstance();
export default i18n;
export { globalComposer, setGlobalLocale };

/**
 * Dynamically imports locale message files.
 * @param locale - Locale code to load (e.g. 'en', 'es')
 * @returns Loaded messages or null if failed
 */
async function loadLocaleMessages(locale: string): Promise<MessageSchema | null> {
  console.debug(`Attempting to load locale: ${locale}`);
  try {
    const messages = await import(`@/locales/${locale}.json`);
    console.debug(`Successfully loaded locale: ${locale}`);
    return messages.default;
  } catch (error) {
    console.error(`Failed to load locale: ${locale}`, error);
    return null;
  }
}

/**
 * Changes active application language.
 * Loads messages file and updates i18n instance if successful.
 * Falls back to default locale on failure.
 * @param lang - Target locale code
 */
export async function setLanguage(lang: string): Promise<void> {
  const composer = i18n.global as GlobalComposer;

  if (composer.locale.value === lang) {
    console.debug(`Language already set to ${lang}`);
    return;
  }

  const messages = await loadLocaleMessages(lang);
  if (messages) {
    composer.setLocaleMessage(lang, messages);
    composer.locale.value = lang;
    console.debug(`Language set to: ${lang}`);
  } else {
    console.warn(`Failed to set language to: ${lang}. Falling back to default.`);
  }
}

/**
 * Flattens nested message structure while maintaining backwards compatibility.
 * Supports both flat and dot-notation key access.
 * @param messages - Nested message object
 * @returns Flattened messages with preserved key paths
 */
export function createCompatibilityLayer(messages: Record<string, any>): Record<string, string> {
  const flat: Record<string, string> = {};

  /**
   * Recursively flattens object into dot notation paths.
   * @param obj - Source object
   * @param prefix - Current key path
   */
  function flattenKeys(obj: Record<string, unknown>, prefix = ''): void {
    Object.entries(obj).forEach(([key, value]) => {
      if (value && typeof value === 'object') {
        flattenKeys(value as Record<string, unknown>, `${prefix}${key}.`);
      } else {
        flat[key] = value as string; // Maintain old keys
        flat[`${prefix}${key}`] = value as string; // Add new nested keys
      }
    });
  }

  flattenKeys(messages);
  return flat;
}
