
import { createI18n } from 'vue-i18n';
import en from '@/locales/en.json' assert { type: 'json' };



/**
 * This setup accomplishes the following:
 *
 * It loads the English translations by default.
 * It sets English as the fallback locale.
 * It detects the browser's locale and attempts to load the corresponding translation file if it's not English.
 * If the browser locale file is successfully loaded, it sets that as the active locale.
 * If loading fails (e.g., the file doesn't exist), it falls back to English.
 **/

const supportedLocales = window.supported_locales || [];

export type MessageSchema = typeof en;
export type SupportedLocale = typeof supportedLocales[number];


// First supported locale is assumed to be the default
const locale = supportedLocales[0] || 'en';

const i18n = createI18n<{ message: typeof en }, SupportedLocale>({
  //legacy: false,
  locale: locale,
  fallbackLocale: 'en',
  messages: {
    en,
  },
  availableLocales: supportedLocales,
});

export default i18n;

async function loadLocaleMessages(locale: string): Promise<MessageSchema | null> {
  console.log(`Attempting to load locale: ${locale}`);
  try {
    const messages = await import(`@/locales/${locale}.json`);
    console.log(`Successfully loaded locale: ${locale}`);
    return messages.default;
  } catch (error) {
    console.error(`Failed to load locale: ${locale}`, error);
    return null;
  }
}

export async function setLanguage(lang: string): Promise<void> {
  if (i18n.global.locale === lang) {
    console.log(`Language is already set to ${lang}. No change needed.`);
    return;
  }

  console.log(`Setting language to: ${lang}`);
  if (lang === 'en') {
    i18n.global.locale = 'en';
    console.log(`Language set to: ${lang}`);
    return;
  }
  const messages = await loadLocaleMessages(lang);
  if (messages) {
    i18n.global.setLocaleMessage(lang, messages);
    i18n.global.locale = lang;
    console.log(`Language set to: ${lang}`);
  } else {
    console.log(`Failed to set language to: ${lang}. Falling back to default.`);
  }
}
