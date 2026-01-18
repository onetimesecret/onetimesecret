// src/types/declarations/locales.d.ts

//
// This file provides type declarations for locale JSON imports.
// For type-safe i18n keys, see: generated/types/i18n-keys.d.ts
//
// Regenerate i18n key types after modifying locale files:
//   pnpm run i18n:generate-types

// Re-export generated types for convenience
export type { I18nKey, LocaleMessageSchema } from '@generated/types/i18n-keys';

type JSONValue = string | number | boolean | { [key: string]: JSONValue } | JSONValue[];

// Generated locale file declarations (single merged file per locale)
declare module '@generated/locales/*.json' {
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
