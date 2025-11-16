// src/i18n.ts

import { type Locale } from '@/schemas/i18n/locale';
import { WindowService } from '@/services/window.service';
import { createI18n, type Composer } from 'vue-i18n';

/**
 * Internationalization configuration and utilities.
 * Sets up Vue i18n instance with locale management and message loading.
 *
 * Locale files are split into 17 categorized JSON files per locale directory
 * (e.g., src/locales/en/*.json). We manually import and merge them to avoid
 * infinite recursion in the Vite i18n plugin's auto-merge.
 */

/**
 * Manually import and merge all locale files for each locale.
 * Files have two possible structures:
 * 1. Structured: {"web": {...}, "email": {...}} - most files
 * 2. Flat: {"key": "value", ...} - uncategorized.json
 */
const localeModules = import.meta.glob<{ default: Record<string, any> }>('@/locales/*/*.json', {
  eager: true,
});

const messages: Record<string, any> = {};

/**
 * Deep merge helper function to recursively merge nested objects.
 * Prevents namespace collisions when multiple locale files share the same top-level keys.
 * @param target - The target object to merge into
 * @param source - The source object to merge from
 * @returns The merged target object
 */
function deepMerge(target: Record<string, any>, source: Record<string, any>): Record<string, any> {
  for (const key in source) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      if (!target[key]) {
        target[key] = {};
      }
      deepMerge(target[key], source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}

// Process each imported module
for (const path in localeModules) {
  // Extract locale code from path: /src/locales/en/file.json -> en
  const match = path.match(/\/locales\/([^\/]+)\//);
  if (match) {
    const locale = match[1];
    const content = localeModules[path].default;

    // Initialize locale if not exists
    if (!messages[locale]) {
      messages[locale] = {};
    }

    // Check if this is a structured file (has "web" or "email" keys)
    // or a flat file (uncategorized)
    const hasStructuredKeys = 'web' in content || 'email' in content;

    if (hasStructuredKeys) {
      // Structured file: merge under "web" or "email" keys using deep merge
      // to prevent namespace collisions (e.g., auth.json and auth-advanced.json both use web.auth)
      Object.keys(content).forEach((topKey) => {
        if (typeof content[topKey] === 'object' && content[topKey] !== null) {
          if (!messages[locale][topKey]) {
            messages[locale][topKey] = {};
          }
          deepMerge(messages[locale][topKey], content[topKey]);
        }
      });
    } else {
      // Flat file (uncategorized): merge keys directly at root level
      Object.assign(messages[locale], content);
    }
  }
}

type GlobalComposer = Composer<{}, {}, {}, Locale>;

/**
 * The list of supported locales comes directly from etc/config.yaml.
 */
const domainBranding = WindowService.get('domain_branding');
const supportedLocales = WindowService.get('supported_locales') || [];
const fallbackLocale = WindowService.get('fallback_locale') || {};
const defaultLocale = WindowService.get('default_locale') || 'en';
const displayLocale = domainBranding?.locale ?? WindowService.get('locale');

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
