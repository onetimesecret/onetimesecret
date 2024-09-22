import { createI18n } from 'vue-i18n';
import en from '@/locales/en.json';

type MessageSchema = typeof en;

/**
 * This setup accomplishes the following:
 *
 * It loads the English translations by default.
 * It sets English as the fallback locale.
 * It detects the browser's locale and attempts to load the corresponding translation file if it's not English.
 * If the browser locale file is successfully loaded, it sets that as the active locale.
 * If loading fails (e.g., the file doesn't exist), it falls back to English.
 **/

export const i18n = createI18n<[MessageSchema], 'en'>({
  locale: 'en',
  fallbackLocale: 'en',
  messages: { en },
});

async function loadLocaleMessages(locale: string): Promise<MessageSchema | null> {
  try {
    console.log(`Attempting to load locale: ${locale}`);
    const messages = await import(`@/locales/${locale}.json`);
    console.log(`Successfully loaded locale: ${locale}`);
    return messages.default as MessageSchema;
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
    i18n.global.locale = lang as "en";
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
