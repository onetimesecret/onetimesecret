import { createI18n, I18nOptions } from 'vue-i18n';

/**
 * This setup accomplishes the following:
 *
 * It loads the English translations by default.
 * It sets English as the fallback locale.
 * It detects the browser's locale and attempts to load the corresponding translation file if it's not English.
 * If the browser locale file is successfully loaded, it sets that as the active locale.
 * If loading fails (e.g., the file doesn't exist), it falls back to English.
 **/

// Import the type only, not the actual module
type MessageSchema = typeof import('@/locales/en.json');

// Define the type for the i18n options
const i18nOptions: I18nOptions = {
  locale: 'en', // set default locale
  messages: {} as Record<string, MessageSchema>, // initialize with empty messages
};

const i18n = createI18n(i18nOptions);

export default i18n;

async function loadLocaleMessages(locale: string): Promise<MessageSchema | null> {
  try {
    const messages = await import(`@/locales/${locale}.json`);
    return messages;
  } catch (error) {
    console.error(`Failed to load locale: ${locale}`, error);
    return null;
  }
}

export async function setLanguage(lang: string): Promise<void> {
  console.log(`Setting language to: ${lang}`);
  const messages = await loadLocaleMessages(lang);
  if (messages) {
    i18n.global.setLocaleMessage(lang, messages);
    i18n.global.locale = lang;
    console.log(`Language set to: ${lang}`);
  } else {
    console.log(`Failed to set language to: ${lang}. Falling back to default.`);
  }
}

export const browserLocale = navigator.language.split('-')[0];
console.log(`Detected browser locale: ${browserLocale}`);
if (browserLocale !== 'en') {
  setLanguage(browserLocale);
}

export const changeLanguage = async (lang: string) => {
  console.log(`Language change requested to: ${lang}`);
  await setLanguage(lang);
}

// Add a function to get available languages
export async function getAvailableLanguages(): Promise<string[]> {
  // This is a placeholder. In a real-world scenario, you might want to
  // dynamically fetch this list from your server or generate it based on
  // available translation files.
  return ['en', 'fr', 'es', 'de'];
}
