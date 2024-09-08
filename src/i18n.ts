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
  legacy: false,
  locale: 'en',
  fallbackLocale: 'en',
  messages: { en },
});

async function loadLocaleMessages(locale: string): Promise<MessageSchema | null> {
  try {
    const messages = await import(`@/locales/${locale}.json`);
    return messages.default as MessageSchema;
  } catch (error) {
    console.error(`Failed to load locale: ${locale}`, error);
    return null;
  }
}

export async function setLanguage(lang: string): Promise<void> {
  const messages = await loadLocaleMessages(lang);
  if (messages) {
    i18n.global.setLocaleMessage(lang, messages);
    i18n.global.locale.value = lang;
  }
}

export const browserLocale = navigator.language.split('-')[0];
if (browserLocale !== 'en') {
  setLanguage(browserLocale);
}

export const changeLanguage = async (lang: string) => {
  const { setLanguage } = await import('@/i18n')
  await setLanguage(lang)
}
