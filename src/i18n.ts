import en from '@/locales/en.json';
import { WindowService } from '@/services/window.service';
import { createI18n } from 'vue-i18n';

/**
 * Configures internationalization with key behaviors:
 *
 * Loads English translations as default.
 * Sets English as fallback locale.
 * Detects browser locale, attempts
 * matching translation import.
 * Sets active locale if file loads.
 * Falls back to English if load fails.
 **/

const supportedLocales = WindowService.get('supported_locales') || [];

export type MessageSchema = typeof en;
export type SupportedLocale = (typeof supportedLocales)[number];

// First supported locale is assumed to be the default
const locale = supportedLocales[0] || 'en';

const i18n = createI18n<{ message: typeof en }, SupportedLocale>({
  // legacy: false,  // TODO: https://vue-i18n.intlify.dev/guide/advanced/composition
  locale: locale,
  fallbackLocale: 'en',
  messages: {
    en,
  },
  availableLocales: supportedLocales,
});

export default i18n;

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

export async function setLanguage(lang: string): Promise<void> {
  if (i18n.global.locale === lang) {
    console.debug(`Language is already set to ${lang}. No change needed.`);
    return;
  }

  if (lang === 'en') {
    i18n.global.locale = 'en';
    console.debug(`Language set to: ${lang}`);
    return;
  }
  const messages = await loadLocaleMessages(lang);
  if (messages) {
    i18n.global.setLocaleMessage(lang, messages);
    i18n.global.locale = lang;
    console.debug(`Language set to: ${lang}`);
  } else {
    console.log(`Failed to set language to: ${lang}. Falling back to default.`);
  }
}

/**
 * Creates a compatibility layer for i18n message structure migration
 * Maintains both flat and nested key access patterns for backwards compatibility
 * @param messages - Source message object with nested structure
 * @returns Flattened message object with both original and nested key paths
 */
export function createCompatibilityLayer(messages: Record<string, any>): Record<string, string> {
  const flat: Record<string, string> = {}; /**
   * Recursively flattens nested object structure into dot notation
   * @param obj - Object to flatten
   * @param prefix - Current key path prefix
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
