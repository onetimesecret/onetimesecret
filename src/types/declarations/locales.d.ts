type JSONValue = string | number | boolean | { [key: string]: JSONValue } | JSONValue[];

// locales.d.ts - Individual locale file declarations (legacy)
declare module '@/locales/*.json' {
  interface Common {
    button_generate_secret_short: string;
    generate_password_disabled: string;
    email_placeholder: string;
    password_placeholder: string;
    // Add other common keys as needed
    [key: string]: JSONValue; // Allow additional keys
  }

  interface Web {
    COMMON: Common;
    // Add other sections as needed
    [key: string]: JSONValue; // Allow additional keys
  }

  const value: {
    web: Web;
    // Add other top-level sections as needed
    [key: string]: JSONValue; // Allow additional keys
  };

  export default value;
}

/**
 * Vue I18n Plugin - Virtual Module Declaration
 * ------------------------------------------------
 * The @intlify/unplugin-vue-i18n plugin creates a virtual module that
 * automatically merges all locale files from src/locales/ subdirectories.
 *
 * Each locale directory (e.g., en/, fr_FR/, etc.) contains 17 JSON files
 * that are merged at build time into a single locale object:
 * - messages.en = merged content from src/locales/en/*.json
 * - messages.fr_FR = merged content from src/locales/fr_FR/*.json
 * - etc.
 */
declare module '@intlify/unplugin-vue-i18n/messages' {
  interface LocaleMessages {
    [locale: string]: {
      web: {
        [key: string]: JSONValue;
      };
      [key: string]: JSONValue;
    };
  }

  const messages: LocaleMessages;
  export default messages;
}
