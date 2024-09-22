import { createI18n, I18nOptions } from 'vue-i18n';
import enMessages from '@/locales/en.json';

/**
 * This setup accomplishes the following:
 *
 * It loads the English translations by default.
 * It sets English as the fallback locale.
 * It detects the browser's locale and attempts to load the corresponding translation file if it's not English.
 * If the browser locale file is successfully loaded, it sets that as the active locale.
 * If loading fails (e.g., the file doesn't exist), it falls back to English.
 **/


type MessageSchema = typeof enMessages;

const i18nOptions: I18nOptions = {
  legacy: false, // You must set `false`, to use Composition API
  locale: 'en', // set default locale
  fallbackLocale: 'en', // set fallback locale
  messages: {
    en: enMessages, // Load English messages by default
  },
};

const i18n = createI18n(i18nOptions);

export default i18n;

async function loadLocaleMessages(locale: string): Promise<MessageSchema | null> {
  try {
    const messages = await import(`@/locales/${locale}.json`);
    return messages.default; // Note the .default here
  } catch (error) {
    console.error(`Failed to load locale: ${locale}`, error);
    return null;
  }
}

export async function setLanguage(lang: string): Promise<void> {
  console.log(`Setting language to: ${lang}`);
  if (lang === 'en') {
    i18n.global.locale.value = 'en';
    console.log(`Language set to: ${lang}`);
    return;
  }
  const messages = await loadLocaleMessages(lang);
  if (messages) {
    i18n.global.setLocaleMessage(lang, messages);
    i18n.global.locale.value = lang;
    console.log(`Language set to: ${lang}`);
  } else {
    console.log(`Failed to set language to: ${lang}. Falling back to default.`);
  }
}

// ... rest of the file remains the same ...
