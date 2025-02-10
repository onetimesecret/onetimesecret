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
const locale = defaultLocale;

/**
 * Core i18n instance configuration:
 * - Uses Composition API (legacy: false)
 * - Enables global injection of $t
 * - Sets default and fallback locales
 * - Loads initial English messages
 */
const i18n = createI18n<false>({
  legacy: false, // Enable composition API.
  globalInjection: true, // allows $t to be used globally.
  missingWarn: true, // these enable browser console logging
  fallbackWarn: true, // and are removed from prod builds.
  locale: locale,
  fallbackLocale: fallbackLocale,
  messages: {
    en,
  },
  availableLocales: supportedLocales,
});

export default i18n;

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
