// src/types/declarations/locales.d.ts
//
// This file provides type declarations for locale JSON imports.
// For type-safe i18n keys, see: src/types/generated/i18n-keys.d.ts
//
// Regenerate i18n key types after modifying locale files:
//   pnpm run i18n:generate-types

// Re-export generated types for convenience
export type { I18nKey, LocaleMessageSchema } from '../generated/i18n-keys';

type JSONValue = string | number | boolean | { [key: string]: JSONValue } | JSONValue[];

// locales.d.ts - Individual locale file declarations
declare module '@/locales/*.json' {
  interface Common {
    button_generate_secret_short: string;
    generate_password_disabled: string;
    email_placeholder: string;
    password_placeholder: string;
    loading: string;
    save_changes: string;
    saving: string;
    error: string;
    warning: string;
    processing: string;
    // Additional keys allowed via index signature
    [key: string]: JSONValue;
  }

  interface Web {
    COMMON: Common;
    LABELS?: { [key: string]: JSONValue };
    STATUS?: { [key: string]: JSONValue };
    TITLES?: { [key: string]: JSONValue };
    login?: { [key: string]: JSONValue };
    signup?: { [key: string]: JSONValue };
    auth?: { [key: string]: JSONValue };
    secrets?: { [key: string]: JSONValue };
    dashboard?: { [key: string]: JSONValue };
    // Additional sections allowed
    [key: string]: JSONValue;
  }

  const value: {
    web: Web;
    email?: { [key: string]: JSONValue };
    [key: string]: JSONValue;
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
